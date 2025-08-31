{ config, pkgs, ... }:

let
  home-manager = builtins.fetchTarball "https://github.com/nix-community/home-manager/archive/release-25.05.tar.gz";
  # Use a existing upstream version
  # home-manager-configuration = builtins.fetchGit {
  #   url = "https://github.com/hukaidong/dotconfig-home-manager.git";
  #   rev = "3361fcda961bf609b74e2e2660c094561a78f68d";
  # }

  # Use a local clone to in-place configuration update
  home-manager-configuration = "/home/kaidong/.config/home-manager/";
in
{
  imports = [
    (import "${home-manager}/nixos")
  ];

  home-manager.users.kaidong = (import "${home-manager-configuration}/home.nix");

  # Used for plover reading UNI inputs
  services.udev.extraRules = ''
    KERNEL=="uinput", GROUP="input", MODE="0660", OPTIONS+="static_node=uinput"
  '';

  users.users.kaidong = {
    isNormalUser = true;
    description = "Kaidong Hu";
    extraGroups = [
      "networkmanager"
      "wheel"
      "dialout"
    ];
    packages = with pkgs; [
      kdePackages.kate
      google-chrome
      kitty
    ];
  };

  xdg.terminal-exec.settings = {
    default = [ "kitty.desktop" ];
  };

  # Install firefox.
  programs.firefox.enable = true;

}
