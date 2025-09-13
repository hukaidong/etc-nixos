{ config, pkgs, ... }:

{
  imports = [
    ./programs/environment.nix
    ./programs/git.nix
    ./programs/zoom.nix
    ./programs/zsh.nix
    ./security/sops.nix
    ./services/desktop.nix
    ./services/printing.nix
    ./storage/filesystems.nix
    ./system/audio.nix
    ./system/boot.nix
    ./system/fonts.nix
    ./system/locale.nix
    ./system/misc.nix
    ./system/networking.nix
  ];
}
