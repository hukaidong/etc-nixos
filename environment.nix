{ pkgs, ... }:
{
  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment = {
    systemPackages = with pkgs; [
      # some bash scripts needs /bin/bash or gcc
      bash
      gcc15

      # system configuring tools
      wl-clipboard
      comma
      git
      neovim
      nixfmt-rfc-style
      wget
      zsh
    ];

    shellAliases = {
      vim = "nvim";
    };

    sessionVariables = {
      LC_COLLATE = "C"; # ls list .dotfiles before others
      EDITOR = "nvim";
      VISUAL = "nvim";
    };
  };
}
