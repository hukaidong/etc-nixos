{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.services.shutdownInhibit;

  # Detect display server from NixOS config
  useX11 = config.services.xserver.enable;
  useWayland = !useX11;

  # Select appropriate tool for simulating activity
  activityTool = if useX11 then pkgs.xdotool else pkgs.ydotool;
  activityCmd =
    if useX11 then
      "${pkgs.xdotool}/bin/xdotool mousemove_relative 1 0"
    else
      "${pkgs.ydotool}/bin/ydotool mousemove -x 1 -y 0";

  # Script to check time and manage inhibitor
  checkAndManage = pkgs.writeShellScript "shutdown-inhibit-check" ''
    HOUR=$(date +%H)
    if [ "$HOUR" -ge ${toString cfg.startHour} ] && [ "$HOUR" -lt ${toString cfg.endHour} ]; then
      # Within inhibit hours, start inhibitor if not running
      if ! systemctl is-active --quiet shutdown-inhibit.service; then
        systemctl start shutdown-inhibit.service
      fi
    else
      # Outside inhibit hours, stop inhibitor if running
      if systemctl is-active --quiet shutdown-inhibit.service; then
        systemctl stop shutdown-inhibit.service
      fi
    fi
  '';

  # Script to stop inhibitor and simulate activity to reset idle timer
  stopAndResetIdle = pkgs.writeShellScript "shutdown-inhibit-stop" ''
    systemctl stop shutdown-inhibit.service

    # Simulate brief mouse activity to reset powerdevil's idle timer
    # This allows powerdevil to re-evaluate and trigger shutdown if still idle
    ${lib.optionalString useX11 "export DISPLAY=:0"}
    ${activityCmd} || true
  '';
in
{
  options.services.shutdownInhibit = {
    enable = lib.mkEnableOption "shutdown inhibitor during specified hours";

    startHour = lib.mkOption {
      type = lib.types.int;
      default = 9;
      description = "Hour to start inhibiting shutdown (24-hour format)";
    };

    endHour = lib.mkOption {
      type = lib.types.int;
      default = 21;
      description = "Hour to stop inhibiting shutdown (24-hour format)";
    };

    message = lib.mkOption {
      type = lib.types.str;
      default = "Shutdown inhibited during work hours";
      description = "Message shown when shutdown is attempted";
    };
  };

  config = lib.mkIf cfg.enable {
    # Add the appropriate activity simulation tool
    environment.systemPackages = [ activityTool ];

    # Enable ydotoold service for Wayland
    systemd.services.ydotoold = lib.mkIf useWayland {
      description = "ydotool daemon for Wayland input simulation";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.ydotool}/bin/ydotoold";
        Restart = "on-failure";
      };
    };

    # The actual inhibitor service (holds the lock)
    systemd.services.shutdown-inhibit = {
      description = "Inhibit shutdown during specified hours";
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.systemd}/bin/systemd-inhibit --what=shutdown --mode=delay --who=ShutdownInhibit --why='${cfg.message}' sleep infinity";
        Restart = "on-failure";
      };
    };

    # Boot-time check service
    systemd.services.shutdown-inhibit-boot-check = {
      description = "Check if shutdown inhibitor should be active on boot";
      wantedBy = [ "multi-user.target" ];
      after = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = checkAndManage;
        RemainAfterExit = false;
      };
    };

    # Timer to start the inhibitor
    systemd.timers.shutdown-inhibit-start = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* ${lib.fixedWidthString 2 "0" (toString cfg.startHour)}:00:00";
        Persistent = true;
      };
    };

    systemd.services.shutdown-inhibit-start = {
      description = "Start shutdown inhibitor";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.systemd}/bin/systemctl start shutdown-inhibit.service";
      };
    };

    # Timer to stop the inhibitor and reset idle timer
    systemd.timers.shutdown-inhibit-stop = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* ${lib.fixedWidthString 2 "0" (toString cfg.endHour)}:00:00";
        Persistent = true;
      };
    };

    systemd.services.shutdown-inhibit-stop = {
      description = "Stop shutdown inhibitor and reset idle timer";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = stopAndResetIdle;
      };
    };
  };
}
