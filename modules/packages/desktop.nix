{ pkgs, ... }:
{
  # Polonium is disabled due to minimal support over x11 backend
  environment.systemPackages = with pkgs; [
    # polonium
    telegram-desktop
    obs-studio
    mpv
    maim
    flameshot

    # I might not need those cli now but might regret later
    # so they are just commented and might be removed later
    # Fast developing application using unstable packages
    # unstable.antigravity-fhs

    # Daily updated nix ai tool sets
    # ai-tools.codex
    ai-tools.opencode
    ai-tools.claude-code

    # required by opencode
    bun

    # paper document scanning
    xsane
    unpaper
    imagemagick
    ocrmypdf
    ghostscript
    poppler-utils
  ];
}
