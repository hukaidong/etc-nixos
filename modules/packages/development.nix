{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    # Build tools
    gcc
    gnumake
    unzip
    rclone

    # devenv perfers unstable packages for quicker iteration
    unstable.devenv

    # Development utilities
    bat
    btop
    fd
    fzf
    htop
    jq
    ripgrep
    tree
  ];
}
