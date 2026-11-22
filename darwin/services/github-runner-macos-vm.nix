{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.kaidong-desktop.services.githubRunners;
  vcfg = cfg.darwinVM;

  # --- Host side ---------------------------------------------------------------

  user = "_github-runner-macos";
  group = user;
  runnerName = "${cfg.name}-darwin";
  stateDir = "${cfg.stateRoot}/${runnerName}-vm";
  logDir = "/var/log/github-runners/${runnerName}-vm";
  install = "${pkgs.coreutils}/bin/install";

  guestCfg = vcfg.system.config;
  guestRunner = guestCfg.services.github-runners.darwin;

  # The official installer, which checks the hash of the Nix it downloads.
  # Same Nix version as nixpkgs', which runs the daemon once the guest's
  # nix-darwin system is active.
  nixInstaller = pkgs.fetchurl {
    url = "https://releases.nixos.org/nix/nix-2.34.9/install";
    hash = "sha256-oDzi6er06hVgJguak+MR269YnSj7XJMY+NnnaO5jOdg=";
  };

  guestScript = pkgs.writeTextFile {
    name = "github-runner-macos-vm-guest.sh";
    text = builtins.readFile ../../configs/github-runner-macos-vm/guest.sh;
    checkPhase = ''
      ${pkgs.stdenv.shellDryRun} "$target"
      ${lib.getExe pkgs.shellcheck-minimal} "$target"
    '';
  };

  # The scripts' inputs, as defaults that the caller's environment overrides,
  # so the scripts also run by hand (another user, another VM; see the
  # scripts).
  withDefaults =
    vars:
    ''
      default() {
        if [[ -z ''${!1:-} ]]; then
          printf -v "$1" '%s' "$2"
        fi
        export "''${1?}"
      }
    ''
    + lib.concatStrings (
      lib.mapAttrsToList (name: value: "default ${name} ${lib.escapeShellArg value}\n") vars
    );

  vmEnv = {
    STATE_DIR = stateDir;
    TART_HOME = "${stateDir}/tart";
    VM_NAME = vcfg.vmName;
    KEY_DIR = "${stateDir}/ssh";
  };

  vmScript = pkgs.writeShellApplication {
    name = "github-runner-macos-vm";
    runtimeInputs = [
      cfg.requireStateDir
      pkgs.coreutils
      pkgs.jq
      pkgs.openssh
      pkgs.tart
    ];
    text =
      withDefaults (
        vmEnv
        // {
          IMAGE = vcfg.image;
          CPUS = toString vcfg.cpus;
          MEMORY_MIB = toString (vcfg.memory * 1024);
          DISK_GB = toString vcfg.disk;
        }
      )
      + builtins.readFile ../../configs/github-runner-macos-vm/vm.sh;
  };

  provisionScript = pkgs.writeShellApplication {
    name = "github-runner-macos-vm-provision";
    runtimeInputs = [
      cfg.requireStateDir
      config.nix.package
      pkgs.coreutils
      pkgs.curl
      pkgs.jq
      pkgs.openssh
      pkgs.sshpass
      pkgs.tart
    ];
    text =
      withDefaults (
        vmEnv
        // {
          TOKEN_FILE = config.sops.secrets."github-runner-token-macos".path;
          REGISTRATION_TOKEN_FILE = "";
          ORG = cfg.org;
          GUEST_SYSTEM = "${guestCfg.system.build.toplevel}";
          GUEST_SCRIPT = "${guestScript}";
          NIX_INSTALLER = "${nixInstaller}";
          SSHD_CONFIG = "${sshdConfig}";
          GUEST_TOKEN_FILE = guestRunner.tokenFile;
          # nix-darwin's runner module keeps a runner's state there, and runs
          # it as this group when it makes the user itself.
          GUEST_RUNNER_DIR = "/var/lib/github-runners/${guestRunner.name}";
          GUEST_RUNNER_GROUP = "_github-runner";
          INTERVAL = "300";
        }
      )
      + builtins.readFile ../../configs/github-runners/common.sh
      + builtins.readFile ../../configs/github-runner-macos-vm/provision.sh;
  };

  # --- Shared with the guest ---------------------------------------------------

  # The guest's SSH hardening. The provisioner writes it before Nix is in the
  # guest, then the guest's nix-darwin system takes the file over: activation
  # replaces a file whose hash it knows.
  sshdConfig = ../../configs/github-runner-macos-vm/sshd.conf;
  sshdConfigPath = "ssh/sshd_config.d/000-github-runner-vm.conf";
in
{
  options.kaidong-desktop.services.githubRunners.darwinVM = {
    enable = lib.mkEnableOption ''
      the macOS runner `<name>-darwin` in a Tart VM: macOS jobs run in the VM,
      never on this machine, and the organization token stays here. Two
      boot-time launchd daemons, running as the hidden `${user}` user, keep
      the VM running and provision it over SSH with the nix-darwin system
      {option}`kaidong-desktop.services.githubRunners.darwinVM.system`
    '';

    system = lib.mkOption {
      type = lib.types.raw;
      example = lib.literalExpression "inputs.self.darwinConfigurations.Kaidong-Mac-Studio-runner-vm";
      description = ''
        The VM's nix-darwin system (a `darwinSystem`), which sets
        {option}`kaidong-desktop.services.githubRunners.darwinVM.guest.enable`.
        This machine builds it, so it must have the same platform.
      '';
    };

    vmName = lib.mkOption {
      type = lib.types.strMatching "[A-Za-z0-9][A-Za-z0-9._-]*";
      default = "runner";
      description = "Name of the Tart VM (in TART_HOME=${stateDir}/tart).";
    };

    image = lib.mkOption {
      type = lib.types.str;
      # macos-golden-gate-vanilla:27.2: macOS 27.2, user admin (password
      # admin, passwordless sudo), SSH on. No guest agent, Xcode or Nix.
      default = "ghcr.io/cirruslabs/macos-golden-gate-vanilla@sha256:b35695ce30453bcc1db961a476740be72a44c2a2e464b73ece1ff0fcac12a873";
      description = ''
        OCI image the VM is cloned from when it does not exist. Changing it
        does not touch an existing VM; delete the VM (as `${user}`, with
        TART_HOME set) to start over from the new image.
      '';
    };

    cpus = lib.mkOption {
      type = lib.types.ints.positive;
      default = 4;
      description = "CPUs of the VM.";
    };

    memory = lib.mkOption {
      type = lib.types.ints.positive;
      default = 8;
      description = "Memory of the VM, in GiB.";
    };

    disk = lib.mkOption {
      type = lib.types.ints.positive;
      default = 100;
      description = "Disk of the VM, in GB. Sparse, and it can only grow.";
    };

    guest.enable = lib.mkEnableOption ''
      the guest side of the macOS runner VM: this nix-darwin system runs in
      the VM. It runs the native macOS runner, which registers with the token
      the host's provisioner leaves in its token file, lets admin (the
      provisioner's SSH user) copy unsigned store paths in, and keeps SSH
      key-only
    '';
  };

  config = lib.mkMerge [
    (lib.mkIf vcfg.enable {
      assertions = [
        {
          assertion = !cfg.darwin.enable;
          message = "kaidong-desktop.services.githubRunners: darwin and darwinVM would both register ${runnerName}; enable one.";
        }
        {
          assertion = guestCfg.kaidong-desktop.services.githubRunners.darwinVM.guest.enable;
          message = "kaidong-desktop.services.githubRunners.darwinVM.system must enable darwinVM.guest.";
        }
        {
          assertion =
            guestCfg.kaidong-desktop.services.githubRunners.name == cfg.name
            && guestCfg.kaidong-desktop.services.githubRunners.org == cfg.org;
          message = "kaidong-desktop.services.githubRunners.darwinVM.system must use the same runner name and org as this machine.";
        }
        {
          # The provisioner makes the token file readable by that user's group.
          assertion = guestRunner.user == null && guestRunner.group == null;
          message = "kaidong-desktop.services.githubRunners.darwinVM.system must run its runner as nix-darwin's _github-runner user.";
        }
        {
          assertion = vcfg.system.pkgs.stdenv.hostPlatform.system == pkgs.stdenv.hostPlatform.system;
          message = "kaidong-desktop.services.githubRunners.darwinVM.system must be for ${pkgs.stdenv.hostPlatform.system}; this machine builds it.";
        }
        {
          assertion = (guestCfg.sops.secrets or { }) == { };
          message = "kaidong-desktop.services.githubRunners.darwinVM.system must not have sops secrets: the VM gets no age key.";
        }
      ];

      # Tart's license (Fair Source) counts as unfree.
      nixpkgs.config.allowUnfreePredicate = pkg: lib.getName pkg == "tart";

      users.users.${user} = {
        uid = lib.mkDefault 541;
        gid = config.users.groups.${group}.gid;
        home = stateDir;
        createHome = false;
        shell = "/bin/bash";
        description = "GitHub Actions runner (macOS VM)";
      };
      users.groups.${group} = {
        gid = lib.mkDefault 541;
        description = "GitHub Actions runner (macOS VM)";
      };
      users.knownUsers = [ user ];
      users.knownGroups = [ group ];

      sops.secrets."github-runner-token-macos" = {
        key = cfg.tokenSecret;
        owner = user;
        mode = "0400";
      };

      # The VM, the provisioning key and the pinned guest host key, in
      # stateDir/tart and stateDir/ssh. github-runners.nix creates stateDir,
      # once its volume is mounted.
      kaidong-desktop.services.githubRunners.stateDirs.${stateDir} = {
        owner = user;
        inherit group;
      };
      system.activationScripts.launchd.text = lib.mkBefore ''
        ${install} -d -m 0755 /var/log/github-runners
        ${install} -d -m 0750 -o ${user} -g ${group} ${logDir}
      '';

      # Creates the VM if needed and runs it; see vm.sh.
      launchd.daemons.github-runner-macos-vm = {
        command = lib.getExe vmScript;
        environment.HOME = stateDir;
        serviceConfig = {
          UserName = user;
          GroupName = group;
          RunAtLoad = true;
          KeepAlive = true;
          ThrottleInterval = 30;
          # vm.sh's clean shutdown of the guest takes up to a minute.
          ExitTimeOut = 75;
          ProcessType = "Interactive";
          StandardOutPath = "${logDir}/vm.log";
          StandardErrorPath = "${logDir}/vm.log";
        };
      };

      # Sets the guest up, deploys its system and registers its runner, then
      # checks again every five minutes; see provision.sh. Its script names
      # the guest system, so a switch that changes the guest restarts it.
      launchd.daemons.github-runner-macos-vm-provision = {
        command = lib.getExe provisionScript;
        environment.HOME = stateDir;
        serviceConfig = {
          UserName = user;
          GroupName = group;
          RunAtLoad = true;
          KeepAlive = true;
          ThrottleInterval = 60;
          StandardOutPath = "${logDir}/provision.log";
          StandardErrorPath = "${logDir}/provision.log";
        };
      };
    })

    (lib.mkIf vcfg.guest.enable {
      assertions = [
        {
          assertion = !vcfg.enable;
          message = "kaidong-desktop.services.githubRunners: the runner VM cannot run a runner VM itself.";
        }
      ];

      # The provisioner writes a registration token there when the runner has
      # to register, and deletes it once it has.
      kaidong-desktop.services.githubRunners.darwin = {
        enable = true;
        tokenFile = lib.mkDefault "/var/lib/github-runners/registration-token";
      };

      # The provisioner copies this system's closure in as admin, over SSH;
      # it is built on the host, so it is not signed.
      nix.settings.trusted-users = [ "admin" ];

      # `text`, not `source`: a path in this flake would link /etc into the
      # flake's source, which is not in the closure.
      environment.etc.${sshdConfigPath} = {
        text = builtins.readFile sshdConfig;
        knownSha256Hashes = [ (builtins.hashFile "sha256" sshdConfig) ];
      };
    })
  ];
}
