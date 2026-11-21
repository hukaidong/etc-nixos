{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.kaidong-desktop.services.githubRunners;
  lcfg = cfg.linux;

  user = "_github-runner-linux";
  group = user;
  runnerName = "${cfg.name}-linux";
  # Same layout nix-darwin's github-runner module uses for the macOS runner.
  stateDir = "/var/lib/github-runners/${runnerName}";
  logDir = "/var/log/github-runners/${runnerName}";
  colimaHome = "${stateDir}/colima";
  install = "${pkgs.coreutils}/bin/install";

  isAarch64 = pkgs.stdenv.hostPlatform.isAarch64;

  dockerEnv = {
    HOME = stateDir;
    DOCKER_CONFIG = "${stateDir}/docker";
  };

  # Image and launcher sources (see the comments in each file).
  dockerfile = ../../configs/github-runner-linux/Dockerfile;
  # Both runners run the same release: nixpkgs' github-runner here, the
  # matching ghcr.io/actions/actions-runner tag in the image.
  runnerVersion = pkgs.github-runner.version;
  # The image installs the Nix release the host daemon runs, without nixpkgs'
  # patch suffix ("2.34.9+1" -> "2.34.9").
  nixVersion = lib.head (lib.splitString "+" config.nix.package.version);
  imageTag = builtins.substring 0 12 (
    builtins.hashString "sha256" (builtins.readFile dockerfile + runnerVersion + nixVersion)
  );

  launcher = pkgs.writeShellApplication {
    name = "github-runner-linux";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      docker
      jq
    ];
    runtimeEnv = {
      ORG = cfg.org;
      RUNNER_NAME = runnerName;
      RUNNER_GROUP = lcfg.runnerGroup;
      RUNNER_LABELS = lib.concatStringsSep "," (
        [
          "self-hosted"
          "Linux"
          (if isAarch64 then "ARM64" else "X64")
        ]
        ++ lcfg.extraLabels
      );
      TOKEN_FILE = config.sops.secrets."github-runner-token-linux".path;
      DOCKERFILE = "${dockerfile}";
      RUNNER_VERSION = runnerVersion;
      NIX_VERSION = nixVersion;
      IMAGE_TAG = imageTag;
      CACHE_VOLUMES = lib.boolToString lcfg.cacheVolumes;
      DOCKER_CONFIG_JSON = pkgs.writeText "docker-config.json" (
        builtins.toJSON {
          cliPluginsExtraDirs = [ "${pkgs.docker-buildx}/libexec/docker/cli-plugins" ];
        }
      );
    };
    text = builtins.readFile ../../configs/github-runner-linux/launcher.sh;
  };
in
{
  options.kaidong-desktop.services.githubRunners.linux = {
    enable = lib.mkEnableOption ''
      the containerized Linux runner: a Colima VM plus a launcher that runs
      every job in a fresh container as an ephemeral just-in-time runner
      (labels self-hosted, Linux, ARM64). Both are boot-time launchd daemons
      running as the hidden `${user}` user
    '';

    extraLabels = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Labels added to the default self-hosted, Linux and ARM64.";
    };

    runnerGroup = lib.mkOption {
      type = lib.types.str;
      default = "Default";
      description = "Organization runner group the just-in-time runners join.";
    };

    cpus = lib.mkOption {
      type = lib.types.ints.positive;
      default = 4;
      description = "CPUs of the Colima VM.";
    };

    memory = lib.mkOption {
      type = lib.types.ints.positive;
      default = 8;
      description = "Memory of the Colima VM, in GiB.";
    };

    disk = lib.mkOption {
      type = lib.types.ints.positive;
      default = 100;
      description = "Disk of the Colima VM, in GiB. Sparse, and it can only grow.";
    };

    vmType = lib.mkOption {
      type = lib.types.enum [
        "vz"
        "qemu"
      ];
      default = "vz";
      description = ''
        Colima VM backend: Apple's Virtualization.framework (`vz`, faster) or
        QEMU with HVF. Switch to `qemu` if the VM will not start from a
        launchd daemon; existing VMs keep their type until
        `colima delete` (run as `${user}` with COLIMA_HOME=${colimaHome}).
      '';
    };

    cacheVolumes = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Keep the Nix store, rustup toolchains and cargo's registry in volumes
        that later jobs reuse. Jobs start much faster, but they are no longer
        isolated from what earlier jobs left in those directories.
      '';
    };
  };

  config = lib.mkIf lcfg.enable {
    assertions = [
      {
        # Lima keeps unix sockets under the VM directory, and macOS caps a
        # socket path at 104 bytes.
        assertion = lib.stringLength stateDir <= 60;
        message = "kaidong-desktop.services.githubRunners.name is too long for the Linux runner's VM sockets under ${stateDir}.";
      }
    ];

    users.users.${user} = {
      uid = lib.mkDefault 540;
      gid = config.users.groups.${group}.gid;
      home = stateDir;
      createHome = false;
      shell = "/bin/bash";
      description = "GitHub Actions runner (Linux VM)";
    };
    users.groups.${group} = {
      gid = lib.mkDefault 540;
      description = "GitHub Actions runner (Linux VM)";
    };
    users.knownUsers = [ user ];
    users.knownGroups = [ group ];

    sops.secrets."github-runner-token-linux" = {
      key = cfg.tokenSecret;
      owner = user;
      mode = "0400";
    };

    # The daemons' directories must exist, owned by the service user, before
    # launchd starts them.
    system.activationScripts.launchd.text = lib.mkBefore ''
      echo >&2 "setting up GitHub Runner '${runnerName}'..."
      ${install} -d -m 0755 /var/lib/github-runners /var/log/github-runners
      ${install} -d -m 0700 -o ${user} -g ${group} ${stateDir}
      ${install} -d -m 0750 -o ${user} -g ${group} ${logDir}
    '';

    # The VM: Colima running Docker, with no host directory mounted into it.
    launchd.daemons.github-runner-linux-vm = {
      path =
        (with pkgs; [
          colima
          coreutils
          curl
          docker
          openssh
        ])
        ++ [
          "/usr/bin"
          "/bin"
          "/usr/sbin"
          "/sbin"
        ];
      environment = dockerEnv // {
        COLIMA_HOME = colimaHome;
      };
      script = ''
        exec colima start default --foreground \
          --save-config=false --activate=false --ssh-config=false \
          --runtime docker --arch ${if isAarch64 then "aarch64" else "x86_64"} \
          --vm-type ${lcfg.vmType} --cpus ${toString lcfg.cpus} \
          --memory ${toString lcfg.memory} --disk ${toString lcfg.disk} \
          --mount none
      '';
      serviceConfig = {
        UserName = user;
        GroupName = group;
        RunAtLoad = true;
        KeepAlive = true;
        ThrottleInterval = 30;
        # Time for Colima to shut the VM down cleanly.
        ExitTimeOut = 60;
        ProcessType = "Interactive";
        SoftResourceLimits.NumberOfFiles = 4096;
        WorkingDirectory = stateDir;
        StandardOutPath = "${logDir}/vm.log";
        StandardErrorPath = "${logDir}/vm.log";
      };
    };

    # One ephemeral runner per job; KeepAlive starts the next one.
    launchd.daemons.github-runner-linux = {
      environment = dockerEnv // {
        DOCKER_HOST = "unix://${colimaHome}/default/docker.sock";
      };
      command = lib.getExe launcher;
      serviceConfig = {
        UserName = user;
        GroupName = group;
        RunAtLoad = true;
        KeepAlive = true;
        ThrottleInterval = 30;
        ProcessType = "Interactive";
        WorkingDirectory = stateDir;
        StandardOutPath = "${logDir}/runner.log";
        StandardErrorPath = "${logDir}/runner.log";
      };
    };
  };
}
