# The containerized Linux runner: a Colima VM, and a launcher that runs every
# job in a fresh container from an image built by Nix
# (github-runner-linux/image.nix). The options shared with the macOS runner
# are in github-runners.nix.
{
  config,
  inputs,
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
  # Colima's directory, with Lima's in its _lima. Colima ignores COLIMA_HOME
  # unless it exists (and falls back to ~/.colima), so it is the state
  # directory itself, which activation creates; a subdirectory would also
  # make the VM's sockets too long (see the assertion).
  colimaHome = stateDir;
in
{
  options.kaidong-desktop.services.githubRunners.linux = {
    enable = lib.mkEnableOption ''
      the containerized Linux runner: a Colima VM plus a launcher that runs
      every job in a fresh container, from an image built by Nix, as an
      ephemeral runner registered for that job (labels self-hosted, Linux,
      ARM64). Both are boot-time launchd daemons running as the hidden
      `${user}` user
    '';

    extraLabels = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Labels added to the default self-hosted, Linux and ARM64.";
    };

    runnerGroup = lib.mkOption {
      type = lib.types.str;
      default = "Default";
      description = "Organization runner group the ephemeral runners join.";
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

  config = lib.mkIf lcfg.enable (
    let
      # aarch64 or x86_64: the VM, the image and the runner's architecture
      # label all follow this Mac's CPU.
      cpu = pkgs.stdenv.hostPlatform.parsed.cpu.name;

      image = pkgs.callPackage ./github-runner-linux/image.nix {
        # Plain nixpkgs, without this flake's overlays or config, so every
        # Linux store path is one Hydra built.
        linuxPkgs = inputs.nixpkgs.legacyPackages."${cpu}-linux";
      };

      dockerEnv = {
        HOME = stateDir;
        DOCKER_CONFIG = "${stateDir}/docker";
      };
    in
    {
      assertions =
        let
          # The VM's longest unix socket, Lima's for Colima's user-v2
          # network, at the path Lima checks: /var is a symlink to
          # /private/var.
          longestSocket =
            lib.optionalString (lib.hasPrefix "/var/" stateDir) "/private"
            + "${colimaHome}/_lima/_networks/user-v2/user-v2_qemu.sock";
        in
        [
          {
            # macOS caps a unix socket path below UNIX_PATH_MAX, 104 bytes.
            assertion = lib.stringLength longestSocket < 104;
            message = "kaidong-desktop.services.githubRunners.name is too long for the Linux runner's VM sockets: ${longestSocket} is ${toString (lib.stringLength longestSocket)} bytes, macOS allows 103.";
          }
        ];

      users = {
        users.${user} = {
          uid = lib.mkDefault 540;
          gid = config.users.groups.${group}.gid;
          home = stateDir;
          createHome = false;
          shell = "/bin/bash";
          description = "GitHub Actions runner (Linux VM)";
        };
        groups.${group} = {
          gid = lib.mkDefault 540;
          description = "GitHub Actions runner (Linux VM)";
        };
        knownUsers = [ user ];
        knownGroups = [ group ];
      };

      sops.secrets."github-runner-token-linux" = {
        key = cfg.tokenSecret;
        owner = user;
        mode = "0400";
      };

      # The daemons' directories must exist, owned by the service user, before
      # launchd starts them.
      system.activationScripts.launchd.text =
        let
          install = "${pkgs.coreutils}/bin/install";
        in
        lib.mkBefore ''
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
            --runtime docker --arch ${cpu} \
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
        command =
          let
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
                RUNNER_LABELS = lib.concatStringsSep "," lcfg.extraLabels;
                TOKEN_FILE = config.sops.secrets."github-runner-token-linux".path;
                IMAGE_STREAM = "${image}";
                IMAGE_NAME = image.imageName;
                IMAGE_TAG = image.imageTag;
                IMAGE_HOME = image.home;
                CACHE_VOLUMES = lib.boolToString lcfg.cacheVolumes;
              };
              text = builtins.readFile ../../../configs/github-runner-linux/launcher.sh;
            };
          in
          lib.getExe launcher;
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
    }
  );
}
