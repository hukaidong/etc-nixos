{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    # Build tools
    gcc
    gnumake
    unzip
    rclone
    devenv

    # Development utilities
    bat
    fd
    fzf
    btop
    htop
    jq
    ripgrep
    tree
  ];
}
