{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    # Build tools
    gcc
    gnumake
    unzip

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
