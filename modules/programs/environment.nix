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
      neovim-unwrapped
      nixfmt-rfc-style
      ntfs3g
      sops
      wget
      xclip
      xsel
      zsh
    ];

    sessionVariables = {
      LC_COLLATE = "C";
      EDITOR = "nvim";
      VISUAL = "nvim";
    };
  };

  programs.neovim.vimAlias = true;
  programs.nix-ld.enable = true;
}
