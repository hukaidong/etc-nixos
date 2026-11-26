{ pkgs, ... }:
let
  tex = pkgs.texlive.combine {
    inherit (pkgs.texlive)
      scheme-medium
      dvisvgm
      dvipng
      wrapfig
      amsmath
      ulem
      hyperref
      capt-of
      ;
  };
in
{
  home.packages = [
    tex
    pkgs.emacs
    pkgs.libnotify
  ];

  services.emacs = {
    enable = true;
    defaultEditor = true;
  };
}
