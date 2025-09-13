# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:
{
  nixpkgs.config.allowUnfree = true;

  imports = [
    ./hardware-configuration.nix
    ./users.nix
    ./backup.nix
  ];

  networking.hostName = "Kaidong-Main-Desktop";

  home-manager.extraSpecialArgs = {
    homePath = "/home";
  };

  system.stateVersion = "25.05";
}
