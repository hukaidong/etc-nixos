{ pkgs, ... }:
{
  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment = {
    systemPackages = with pkgs; [
      # some bash scripts needs /bin/bash or gcc
      bash
      gcc15

      # system configuring tools, wl-copy / wl-paste
      wl-clipboard
      # provides xclip & xsel for wayland
      wl-clipboard-x11
      comma
      git
      neovim
      nixfmt-rfc-style
      wget

      # system requirement
      davfs2
      ntfs3g
      zsh
      sops
      age
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
