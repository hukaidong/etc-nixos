{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.kaidong-desktop.desktopEnvironment.plasma-i3;
in
{
  options.kaidong-desktop.desktopEnvironment.plasma-i3 = {
    enable = lib.mkEnableOption "Plasma 6 with i3 window manager (X11)";
  };

  config = lib.mkIf cfg.enable {
    services = {
      xserver = {
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
          configFile = ../../../configs/i3-plasma-config;
        };
        desktopManager.session = [
          {
            manage = "desktop";
            name = "plasma-i3wm";
            start = "KDEWM=${pkgs.i3}/bin/i3 /run/current-system/sw/bin/startplasma-x11";
          }
        ];
      };

      desktopManager.plasma6.enable = true;

      # Troubleshooting flickering issues with nvidia drivers
      # See https://nixos.wiki/wiki/Nvidia#Fix_app_flickering_with_Picom
      picom.enable = true;

      displayManager.sddm.enable = true;
      displayManager.defaultSession = "plasma-i3wm+i3";

      # Stands in for KWin, disabled below. Every NixOS host imports fakwin's
      # module (hosts/nixos.nix).
      fakwin.enable = true;
    };

    # Disable the real KWin; fakwin answers its D-Bus calls instead, so
    # Plasma's logout, reboot and shutdown keep working.
    systemd.user.services.plasma-kwin_x11.enable = false;
  };
}
