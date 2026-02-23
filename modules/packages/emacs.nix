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

  emacsPackage = pkgs.emacs.pkgs.withPackages (epkgs: [ epkgs.mu4e ]);
in
{
  options.kaidong-desktop.programs.emacs = {
    enable = lib.mkEnableOption "Emacs with custom configuration";

    enableMailSupport = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable mail support with mu4e, davmail, and isync";
    };

    enableService = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable the Emacs daemon service with emacsclient as default editor";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages =
      [
        tex
        emacsPackage
        pkgs.libnotify
      ]
      ++ lib.optionals cfg.enableMailSupport (
        with pkgs;
        [
          davmail
          isync
          mu
        ]
      );

    services.emacs = lib.mkIf cfg.enableService {
      enable = true;
      package = emacsPackage;
      defaultEditor = true;
      startWithGraphical = true;
    };
  };
}
