# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:
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

  # Inhibit shutdown during work hours (9am-9pm)
  services.shutdownInhibit.enable = true;

  programs.steam.enable = true;
  programs.steam.protontricks.enable = true;

  kaidong-desktop.desktopEnvironment.plasma6.enable = true;

  system.stateVersion = "25.11";
}
