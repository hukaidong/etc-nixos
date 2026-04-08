{
  pkgs,
  lib,
  config,
  plover-flake,
  ...
}:
{
  options.modules.plover.enable = lib.mkOption {
    type = lib.types.bool;
    default = pkgs.stdenv.isLinux;
    description = "Whether to enable Plover stenography";
  };

  config = lib.mkIf config.modules.plover.enable {
    programs.plover = {
      enable = true;

      # Use plover package with additional plugins
      package = plover-flake.packages.${pkgs.stdenv.hostPlatform.system}.plover.withPlugins (
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
