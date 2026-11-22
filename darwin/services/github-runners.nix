{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.kaidong-desktop.services.githubRunners;
  dcfg = cfg.darwin;

  stat = "${pkgs.coreutils}/bin/stat";

  # The external volume that stateRoot is on: /Volumes/<name> for a path
  # under it, otherwise null.
  rootParts = lib.splitString "/" cfg.stateRoot;
  volume =
    if lib.length rootParts >= 3 && lib.elemAt rootParts 1 == "Volumes" then
      "/Volumes/${lib.elemAt rootParts 2}"
    else
      null;

  # While an external volume is not mounted, /Volumes/<name> can still exist
  # as a plain directory on the internal disk (a stale mount point), and
  # anything written there lands on the internal disk, hidden once the volume
  # mounts over it. A mount point is on another device than /Volumes.
  isMounted = vol: ''[[ -d ${vol} && $(${stat} -c %d ${vol}) != "$(${stat} -c %d /Volumes)" ]]'';

  # Run first by every daemon whose state is under stateRoot.
  requireStateDir = pkgs.writeShellApplication {
    name = "github-runners-state-dir";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      # github-runners-state-dir DIR: wait up to STATE_DIR_TIMEOUT seconds
      # (default 120) for the state directory DIR to exist and, if it is under
      # /Volumes, for its external volume to be mounted; exit 1 otherwise, so
      # launchd (KeepAlive) tries again later. The directory alone proves nothing: a stale mount
      # point is a plain directory on the internal disk.
      dir=$1
      volume=
      if [[ $dir =~ ^/Volumes/([^/]+) ]]; then
        volume=/Volumes/''${BASH_REMATCH[1]}
      fi

      mounted() {
        [[ -z $volume ]] ||
          { [[ -d $volume ]] && [[ $(stat -c %d "$volume") != "$(stat -c %d /Volumes)" ]]; }
      }

      for ((waited = 0; waited < ''${STATE_DIR_TIMEOUT:-120}; waited += 5)); do
        if mounted && [[ -d $dir ]]; then
          exit 0
        fi
        sleep 5
      done
      if ! mounted; then
        echo "$volume is not mounted; not starting" >&2
      else
        echo "$dir does not exist; activate the system again (darwin-rebuild switch) to create it" >&2
      fi
      exit 1
    '';
  };
in
{
  # Options shared by all runners, the state root they keep their VMs in, and
  # the native macOS runner. The Linux runner (Colima VM + one container per
  # job) is in github-runner-linux.nix, the macOS runner VM in
  # github-runner-macos-vm.nix.
  options.kaidong-desktop.services.githubRunners = {
    name = lib.mkOption {
      type = lib.types.strMatching "[A-Za-z0-9][A-Za-z0-9._-]*";
      example = "Kaidong-Mac-Studio";
      description = ''
        Base name of this machine's runners; they register as `<name>-darwin`
        and `<name>-linux`.
      '';
    };

    org = lib.mkOption {
      type = lib.types.str;
      default = "kd-lapwings";
      description = "GitHub organization the runners register with.";
    };

    tokenSecret = lib.mkOption {
      type = lib.types.str;
      default = "github-runner-token";
      description = ''
        Key in secrets/secrets.yaml holding a fine-grained personal access
        token owned by {option}`org` with the organization permission
        "Self-hosted runners: Read and write". It stays on the host: the Linux
        runner uses it to get a registration token for every job's ephemeral
        runner, and the macOS runner VM's provisioner to get one when the
        runner in the VM has to register.
      '';
    };

    stateRoot = lib.mkOption {
      type = lib.types.strMatching "/.*[^/]";
      default = "/var/lib/github-runners";
      example = "/Volumes/RunnerVMs";
      description = ''
        Directory holding the runners' VMs, in a directory per runner. On an
        external volume (`/Volumes/<name>/...`), activation creates nothing
        there while the volume is not mounted, the daemons wait for it, and
        the volume is set to mount at boot without a login. It must be an
        APFS volume with ownership enabled.
      '';
    };

    stateDirs = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            owner = lib.mkOption { type = lib.types.str; };
            group = lib.mkOption { type = lib.types.str; };
          };
        }
      );
      default = { };
      internal = true;
      description = ''
        Directories under {option}`stateRoot` that activation creates (mode
        0700) for the runner daemons, by path.
      '';
    };

    requireStateDir = lib.mkOption {
      type = lib.types.package;
      default = requireStateDir;
      readOnly = true;
      internal = true;
      description = ''
        `github-runners-state-dir DIR`, which a daemon runs before it uses its
        state directory DIR; see the script.
      '';
    };

    darwin = {
      enable = lib.mkEnableOption ''
        the native macOS runner `<name>-darwin`: a boot-time launchd daemon
        running as the hidden `_github-runner` user, with labels self-hosted,
        macOS and ARM64. Jobs run on this machine itself, so the Mac Studio
        runs it in a VM (github-runner-macos-vm.nix) rather than natively
      '';

      tokenFile = lib.mkOption {
        type = lib.types.str;
        example = "/var/lib/github-runners/registration-token";
        description = ''
          File the runner reads a registration token (or a personal access
          token) from when it is not registered yet. It has to be readable by
          the runner, and therefore by its jobs.
        '';
      };

      extraLabels = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Labels added to the default self-hosted, macOS and ARM64.";
      };

      extraPackages = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
        description = "Extra packages on the job PATH.";
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (cfg.stateDirs != { }) {
      # Before the launchd step, which starts the daemons.
      system.activationScripts.launchd.text = lib.mkBefore ''
        echo >&2 "setting up GitHub runner state in ${cfg.stateRoot}..."
        ${lib.optionalString (volume != null) ''
          # Mount external volumes at boot, before anyone logs in.
          if [[ $(/usr/bin/defaults read /Library/Preferences/SystemConfiguration/autodiskmount AutomountDisksWithoutUserLogin 2>/dev/null) != 1 ]]; then
            /usr/bin/defaults write /Library/Preferences/SystemConfiguration/autodiskmount AutomountDisksWithoutUserLogin -bool true
          fi
        ''}
        if ${if volume == null then "true" else isMounted volume}; then
          ${lib.optionalString (volume != null) ''
            # Without ownership, every file there looks owned by whoever looks,
            # and the per-runner directories protect nothing.
            if [[ $(/usr/sbin/diskutil info -plist ${volume} | /usr/bin/plutil -extract GlobalPermissionsEnabled raw -o - -) != true ]]; then
              printf >&2 '\e[1;31mwarning: ownership is disabled on ${volume}; enable it (Get Info > Ignore ownership on this volume)\e[0m\n'
            fi
          ''}
          ${pkgs.coreutils}/bin/mkdir -p ${lib.escapeShellArg cfg.stateRoot}
          ${lib.concatStrings (
            lib.mapAttrsToList (dir: d: ''
              ${pkgs.coreutils}/bin/install -d -m 0700 -o ${d.owner} -g ${d.group} ${lib.escapeShellArg dir}
            '') cfg.stateDirs
          )}
        else
          printf >&2 '\e[1;31mwarning: ${toString volume} is not mounted, so the GitHub runners have no state directories yet; they wait for it. Mount it, then activate again.\e[0m\n'
        fi
      '';
    })

    (lib.mkIf dcfg.enable {
      # State in /var/lib/github-runners/<name>-darwin, work tree in
      # /var/lib/github-runners/_work/<name>-darwin (cleared on every service
      # start), logs in /var/log/github-runners/<name>-darwin.
      services.github-runners.darwin = {
        enable = true;
        url = "https://github.com/${cfg.org}";
        name = "${cfg.name}-darwin";
        inherit (dcfg) tokenFile;
        # Re-registering after the state directory is lost reuses the name.
        replace = true;
        inherit (dcfg) extraLabels;
        # The org's workflows expect rustup, make, a C++ compiler, the Xcode
        # command-line tools and Nix with flakes. The upstream module provides
        # bash, coreutils, git, gnutar, gzip and Nix; make, the compiler and
        # Xcode's tools come from /usr/bin, appended below.
        extraPackages = [ pkgs.rustup ] ++ dcfg.extraPackages;
      };

      launchd.daemons.github-runner-darwin = {
        path = lib.mkAfter [
          "/usr/bin"
          "/bin"
          "/usr/sbin"
          "/sbin"
        ];
        # Upstream writes `{ Crashed = false; } // mkIf cfg.ephemeral { ... }`,
        # which turns the whole value into that mkIf, so a persistent runner gets
        # no KeepAlive and launchd never restarts it after it exits.
        serviceConfig.KeepAlive = lib.mkForce true;
      };
    })
  ];
}
