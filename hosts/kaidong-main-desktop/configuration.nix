# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:
let
  linux_6_12_pinned = pkgs.linux_6_12.override {
    argsOverride = rec {
      src = pkgs.fetchurl {
        url = "mirror://kernel/linux/kernel/v6.x/linux-${version}.tar.xz";
        sha256 = "sha256-j5WoVJz737icEYGh9VqXHwTfzWKVCKLtcLd3q5L52z4=";
      };
      version = "6.12.45";
      modDirVersion = "6.12.45";
    };
  };
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

  # Inhibit shutdown during work hours (9am-9pm)
  services.shutdownInhibit.enable = true;

  system.stateVersion = "25.11";
}
