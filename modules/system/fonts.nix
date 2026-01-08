{ config, pkgs, ... }:

{
  fonts = {
    packages = with pkgs; [
      fira-sans
      fira-mono
      fira-code

      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-cjk-serif
      noto-fonts-color-emoji

      nerd-fonts.jetbrains-mono

      myfonts
    ];

    fontconfig = {
      enable = true;
      defaultFonts = {
        sansSerif = [
          "Noto Sans CJK SC"
          "Noto Sans CJK JP"
          "Noto Sans"
        ];
        serif = [
          "Noto Serif CJK SC"
          "Noto Serif CJK JP"
          "Noto Serif"
        ];
        monospace = [
          "Noto Sans Mono CJK JP"
          "Noto Sans Mono"
        ];
      };
    };
  };
}
