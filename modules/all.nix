{ config, pkgs, ... }:

{
  imports = [
    ./system/boot.nix
    ./system/networking.nix
    ./system/locale.nix
    ./system/audio.nix
    ./system/fonts.nix
    ./services/printing.nix
    ./services/desktop.nix
    ./programs/environment.nix
    ./programs/git.nix
    ./programs/zsh.nix
    ./programs/zoom.nix
    ./storage/filesystems.nix
    ./security/sops.nix
  ];
}
