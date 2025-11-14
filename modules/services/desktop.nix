{ pkgs, ... }:
{
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

  # Use x11 as default plasma session until plover find a solution
  # running keyboard emulator in wayland
  #services.displayManager.sddm.settings.General.DisplayServer = "x11-user";

  # Create a systemd user service for fakwin
  systemd.user.services.plasma-kwin_x11.enable = false;
  services.fakwin.enable = true;
}
