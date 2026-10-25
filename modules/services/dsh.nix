{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.kaidong-desktop.services.dshWeb;

  # dsh is an agent: it needs the user's whole toolchain on PATH, not just
  # what the unit declares.  Prepend the Home Manager profile (all
  # `home.packages`) to the PATH the unit already receives.  This is the
  # same pattern Home Manager uses for its opencode-web service.
  dshWebLauncher = pkgs.writeShellScriptBin "dsh-web-launcher" ''
    export PATH="${config.home-manager.users.kaidong.home.profileDirectory}/bin''${PATH:+:$PATH}"
    exec ${pkgs.ai-tools.dsh}/bin/dsh web --no-open
  '';
in
{
  options.kaidong-desktop.services.dshWeb = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable the DeepSeek Harness Web UI service (`dsh web`)";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services.dsh-web = {
      enable = true;
      description = "DeepSeek Harness Web UI (dsh web)";
      after = [ "network.target" ];

      wantedBy = [ "default.target" ];

      unitConfig.ConditionUser = "kaidong";
      serviceConfig = {
        Type = "simple";
        # dshWebLauncher prepends the Home Manager profile to this PATH; see
        # `home-manager.useUserPackages` in home/nixos-home.nix.
        ExecStart = lib.getExe dshWebLauncher;
        Restart = "on-failure";
        RestartSec = "5s";
        Environment = [
          # The Web UI keeps its state (profiles, credentials, sessions) here.
          "DSH_HOME=/home/kaidong/.dsh"
          # The harness spawns subprocesses (git, node tooling) during sessions.
          "PATH=/run/current-system/sw/bin:/usr/local/bin:/usr/bin:/bin"
        ];
      };
    };
  };
}
