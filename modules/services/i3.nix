{ config, lib, pkgs, ... }:
let
  cfg = config.kaidong-desktop.desktopEnvironment.i3;
in
{
  options.kaidong-desktop.desktopEnvironment.i3 = {
    enable = lib.mkEnableOption "i3 only with de support (X11)";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      kdePackages.kwallet
      kdePackages.dolphin
    ];

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
    };

    services.picom.enable = true;

    services.displayManager.sddm.enable = true;
  };
}
