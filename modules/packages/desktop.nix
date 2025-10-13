{ pkgs, ... }:
{
  # Polonium is disabled due to minimal support over x11 backend
  environment.systemPackages = with pkgs; [
    # polonium
    telegram-desktop
    obs-studio

    # Fast developing application using unstable packages
    unstable.code-cursor-fhs
    unstable.android-studio

    # Daily updated nix ai tool sets
    ai-tools.opencode
    ai-tools.claude-code
    ai-tools.cursor-agent
  ];
}
