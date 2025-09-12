{ pkgs, ... }:
{
  services.xserver = {
    enable = true;
    xkb = {
      layout = "us";
      variant = "dvp";
    };
  };

  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

  # Use x11 as default plasma session until plover find a solution
  # running keyboard emulator in wayland
  services.displayManager.defaultSession = "plasmax11";
  services.displayManager.sddm.settings.General.DisplayServer = "x11-user";
}
