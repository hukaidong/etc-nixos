{ config, pkgs, ... }:

{
  services.udev.extraRules = ''
    KERNEL=="uinput", GROUP="input", MODE="0660", OPTIONS+="static_node=uinput"
  '';

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.kaidong = {
    isNormalUser = true;
    shell = pkgs.zsh;
    description = "Kaidong Hu";
    extraGroups = [
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
