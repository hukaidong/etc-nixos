{ pkgs, ... }:
{
  # Polonium is disabled due to minimal support over x11 backend
  environment.systemPackages = with pkgs; [
    # polonium
    telegram-desktop
    obs-studio

    unstable.code-cursor-fhs
  ];
}
