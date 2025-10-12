{ pkgs, plover-flake, ... }:

{
  programs.plover = {
    enable = true;

    # Use plover package with additional plugins
    package = plover-flake.packages.${pkgs.system}.plover.withPlugins (
      ps: with ps; [
        plover-lapwing-aio # Lapwing stenography theory
        plover-clippy-2
      ]
    );

    # Plover will manage its own settings
    settings = null;
  };
}
