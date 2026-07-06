{ config, lib, pkgs, ... }:
let
  cfg = config.kaidong-desktop.desktopEnvironment.plasma6;
in
{
  options.kaidong-desktop.desktopEnvironment.plasma6 = {
    enable = lib.mkEnableOption "Plasma 6 with Wayland";
  };

  config = lib.mkIf cfg.enable {
    services.desktopManager.plasma6.enable = true;

    services.displayManager.sddm = {
      enable = true;
      wayland.enable = true;
    };
    services.displayManager.defaultSession = "plasma";

    # Wayland-specific settings for Electron apps
    environment.sessionVariables = {
      NIXOS_OZONE_WL = "1";
    };
  };
}
