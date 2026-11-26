{
  pkgs,
  lib,
  config,
  ...
}:
{
  # Enabled on the NixOS machines by profiles/home/desktop.nix.
  options.modules.plover.enable = lib.mkEnableOption "Plover stenography";

  config = lib.mkIf config.modules.plover.enable {
    programs.plover = {
      enable = true;

      # Use plover package with additional plugins
      package = pkgs.plover-flake.plover.withPlugins (
        ps: with ps; [
          plover-lapwing-aio # Lapwing stenography theory
          plover-clippy-2
        ]
      );

      # Plover will manage its own settings
      settings = null;
    };
  };
}
