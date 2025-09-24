# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{
  config,
  pkgs,
  modulePath,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ./users.nix
  ];

  networking.hostName = "Kaidong-MBP14";

  nixpkgs.config.allowUnfree = true;

  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.kernelParams = [
    "mem_sleep_default=s2idle"
    "no_console_suspend"
  ];
  boot.tmp.useTmpfs = false;

  system.stateVersion = "25.05";

}
