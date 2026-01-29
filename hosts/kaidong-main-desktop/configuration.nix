# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:
let
  usei3 = false;
in
{
  nixpkgs.config.allowUnfree = true;

  imports = [
    ./hardware-configuration.nix
    ./filesystem.nix
    ./users.nix
    ./programs.nix
    ./virtualization.nix
  ];

  networking.hostName = "Kaidong-Main-Desktop";

  boot.kernelPackages = pkgs.linuxPackages_latest;

  programs.steam.enable = true;
  programs.steam.protontricks.enable = true;

  kaidong-desktop.desktopEnvironment.plasma-i3.enable = usei3;
  kaidong-desktop.desktopEnvironment.plasma6.enable = !usei3;

  system.stateVersion = "25.11";
}
