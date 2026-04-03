{ pkgs, ... }:
{
  environment = {
    systemPackages = with pkgs; [
      bash
      davfs2
      gcc15
      git
      ntfs3g
      wget
      xclip
      xsel
      zsh
    ];

    homeBinInPath = true;
    localBinInPath = true;
  };
}
