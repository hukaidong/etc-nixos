{ pkgs, ... }:
{
  environment = {
    systemPackages = with pkgs; [
      age
      bash
      comma
      davfs2
      gcc15
      git
      neovim
      nixfmt-rfc-style
      ntfs3g
      sops
      wget
      xclip
      xsel
      zsh
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
