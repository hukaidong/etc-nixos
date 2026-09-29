{
  pkgs,
  lib,
  config,
  ...
}:
{
  options.modules.desktop.enable = lib.mkOption {
    type = lib.types.bool;
    default = pkgs.stdenv.hostPlatform.isLinux;
    description = "Whether to enable desktop packages";
  };

  config = lib.mkIf config.modules.desktop.enable {
    home.packages = with pkgs; [
      # Productivity applications
      keepassxc
      zotero
      zathura
      thunderbird
      discord
      gimp3
      libreoffice

      # Creative and engineering applications
      blender
      freecad
      kicad
    ];
  };
}
