{ config, pkgs, ... }:

{
  services.udev.extraRules = ''
    KERNEL=="uinput", GROUP="input", MODE="0660", OPTIONS+="static_node=uinput"
    SUBSYSTEM=="hidraw", KERNELS=="*:9000:400D.*", MODE="0666"
  '';

  users.users.kaidong = {
    isNormalUser = true;
    shell = pkgs.zsh;
    initialPassword = "changethis";
    description = "Kaidong Hu";

    extraGroups = [
      "docker"
      "networkmanager"
      "wheel"
      "dialout"
      "input"
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
