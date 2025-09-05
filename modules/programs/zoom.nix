{ pkgs, ... }:
{
  # Zoom needs system integartion with plasma 6 and not able
  # to be installed by home-manager
  environment = {
    systemPackages = with pkgs; [
      zoom-us
    ];
  };

  programs.zoom-us.enable = true;
}
