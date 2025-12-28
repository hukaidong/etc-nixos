{ pkgs, lib, ... }:
{
  # For sudo invoked by LLM agents
  environment = {
    systemPackages = with pkgs; [
      zsh
      oh-my-zsh

      x11_ssh_askpass
    ];
    variables = {
      SUDO_ASKPASS = "${lib.getExe' pkgs.x11_ssh_askpass "x11-ssh-askpass"}";
    };
  };

  # Generic zsh configuration for all users
  programs.zsh = {
    enable = true;

    ohMyZsh = {
      enable = true;
      theme = "robbyrussell";
    };

    shellAliases = {
      nixb = "sudo nixos-rebuild";
      groot = "git status >/dev/null && cd $(git rev-parse --show-toplevel)";
    };
  };
}
