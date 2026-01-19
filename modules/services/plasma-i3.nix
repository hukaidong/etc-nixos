{ config, lib, pkgs, ... }:
let
  cfg = config.kaidong-desktop.desktopEnvironment.plasma-i3;
in
{
  options.kaidong-desktop.desktopEnvironment.plasma-i3 = {
    enable = lib.mkEnableOption "Plasma 6 with i3 window manager (X11)";
  };

  config = lib.mkIf cfg.enable {
    services.xserver = {
      enable = true;
      xkb = {
        layout = "us";
        variant = "dvp";
      };

      windowManager.i3 = {
        enable = true;
        extraPackages = with pkgs; [
          dmenu
          feh
          i3status
          picom
        ];
        configFile = ../../configs/i3-config;
      };
      desktopManager.session = [
        {
          manage = "desktop";
          name = "plasma-i3wm";
          start = "KDEWM=${pkgs.i3}/bin/i3 /run/current-system/sw/bin/startplasma-x11";
        }
      ];
    };

    services.desktopManager.plasma6.enable = true;

    # Troubleshooting flickering issues with nvidia drivers
    # See https://nixos.wiki/wiki/Nvidia#Fix_app_flickering_with_Picom
    services.picom.enable = true;

    services.displayManager.sddm.enable = true;
    services.displayManager.defaultSession = "plasma-i3wm+i3";

    # Create a systemd user service for fakwin
    systemd.user.services.plasma-kwin_x11.enable = false;
    services.fakwin.enable = true;
  };
}
