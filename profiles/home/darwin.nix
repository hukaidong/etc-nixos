# The user environment of the Mac, where Home Manager runs on its own instead
# of inside a NixOS system (hosts/home.nix). The pieces cover what NixOS
# hosts get from their system profile, plus macOS-only jobs (launchd).
{ config, pkgs, ... }:
{
  _class = "homeManager";

  imports = [
    ./darwin/direnv.nix
    ./darwin/emacs.nix
    ./darwin/nix.nix
    ./darwin/rclone-bisync.nix
    ./darwin/ruby.nix
  ];

  home.username = "kaidong";
  home.homeDirectory = "/Users/${config.home.username}";
  home.packages = [ pkgs.home-manager ];
}
