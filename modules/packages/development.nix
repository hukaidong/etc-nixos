{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    # Build tools
    gcc
    gnumake
    unzip
    rclone

    # Development utilities
    bat
    fd
    fzf
    htop
    jq
    ripgrep
    tree
  ];
}
