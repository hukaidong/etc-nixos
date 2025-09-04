{ ... }:
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
}