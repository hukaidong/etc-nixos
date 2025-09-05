{ pkgs, ... }:
{
  environment = {
    systemPackages = with pkgs; [
      bash
      gcc15
      wl-clipboard
      wl-clipboard-x11
      comma
      git
      neovim
      nixfmt-rfc-style
      wget
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
      LC_COLLATE = "C";
      EDITOR = "nvim";
      VISUAL = "nvim";
    };
  };

  nixpkgs.config.allowUnfree = true;
}
