{ pkgs, ... }:
{
  environment = {
    systemPackages = with pkgs; [
      bash
      comma
      davfs2
      gcc15
      git
      neovim-unwrapped
      ntfs3g
      wget
      xclip
      xsel
      zsh
    ];
  };
}
