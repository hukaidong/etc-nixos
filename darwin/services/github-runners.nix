{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.kaidong-desktop.services.githubRunners;
in
{
  # Options shared by both runners, plus the native macOS runner. The Linux
  # runner (Colima VM + one container per job) is in github-runner-linux.nix.
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
        "Self-hosted runners: Read and write". The macOS runner uses it to
        register itself; the Linux runner uses it to create a just-in-time
        runner for every job.
      '';
    };

    darwin = {
      enable = lib.mkEnableOption ''
        the native macOS runner: a boot-time launchd daemon running as the
        hidden `_github-runner` user, with labels self-hosted, macOS and ARM64
      '';

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

  config = lib.mkIf cfg.darwin.enable {
    # State in /var/lib/github-runners/<name>-darwin, work tree in
    # /var/lib/github-runners/_work/<name>-darwin (cleared on every service
    # start), logs in /var/log/github-runners/<name>-darwin.
    services.github-runners.darwin = {
      enable = true;
      url = "https://github.com/${cfg.org}";
      name = "${cfg.name}-darwin";
      tokenFile = config.sops.secrets."github-runner-token-darwin".path;
      # Re-registering after the state directory is lost reuses the name.
      replace = true;
      inherit (cfg.darwin) extraLabels;
      # The org's workflows expect rustup, make, a C++ compiler, the Xcode
      # command-line tools and Nix with flakes. The upstream module provides
      # bash, coreutils, git, gnutar, gzip and Nix; make, the compiler and
      # Xcode's tools come from /usr/bin, appended below.
      extraPackages = [ pkgs.rustup ] ++ cfg.darwin.extraPackages;
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

    sops.secrets."github-runner-token-darwin" = {
      key = cfg.tokenSecret;
      owner = "_github-runner";
      mode = "0400";
    };
  };
}
