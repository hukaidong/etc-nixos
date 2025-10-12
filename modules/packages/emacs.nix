{ pkgs, ... }:
let
  # Minimum set of packages for Emacs org mode, see https://wiki.nixos.org/wiki/TexLive
  tex = (
    pkgs.texlive.combine {
      inherit (pkgs.texlive)
        scheme-medium
        dvisvgm
        dvipng # for preview and export as html
        wrapfig
        amsmath
        ulem
        hyperref
        capt-of
        ;
      #(setq org-latex-compiler "lualatex")
      #(setq org-preview-latex-default-process 'dvisvgm)
    }
  );
in
{
  environment.systemPackages = with pkgs; [
    davmail
    isync
    mu
    tex

    (emacs.pkgs.withPackages (epkgs: [ epkgs.mu4e ]))
  ];
}
