{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.kaidong-desktop.services.dshWeb;
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
        # WORKAROUND -- dsh-patched instead of ai-tools.dsh; see the dsh-patched
        # override in flake.nix and upstream-checks/dsh.sh.  Revert once the
        # probe reports the upstream path clear.
        # ExecStart = "${pkgs.ai-tools.dsh}/bin/dsh web --no-open";
        ExecStart = "${pkgs.dsh-patched}/bin/dsh web --no-open";
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
