# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./users.nix
    ./modules/system/boot.nix
    ./modules/system/networking.nix
    ./modules/system/locale.nix
    ./modules/system/audio.nix
    ./modules/services/printing.nix
    ./modules/services/desktop.nix
    ./modules/programs/environment.nix
    ./modules/programs/git.nix
    ./modules/programs/zsh.nix
    ./modules/programs/zoom.nix
    ./modules/storage/filesystems.nix
    ./modules/security/sops.nix
  ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  system.stateVersion = "25.05";
}
