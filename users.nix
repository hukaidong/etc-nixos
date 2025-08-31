{ config, pkgs, ... }:

{
  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.kaidong = {
    isNormalUser = true;
    shell = pkgs.zsh;
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
