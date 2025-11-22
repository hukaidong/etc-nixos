{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.kaidong-desktop.programs.emacs;

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
  options.kaidong-desktop.programs.emacs = {
    enable = lib.mkEnableOption "Emacs with custom configuration";

    enableMailSupport = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable mail support with mu4e, davmail, and isync";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages =
      with pkgs;
      [
        tex
        (emacs.pkgs.withPackages (epkgs: [ epkgs.mu4e ]))
      ]
      ++ lib.optionals cfg.enableMailSupport [
        davmail
        isync
        mu
      ];
  };
}
