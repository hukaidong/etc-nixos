{
  pkgs,
  lib,
  config,
  ...
}:
{
  # Enabled on the NixOS machines by profiles/home/desktop.nix.
  options.modules.desktop.enable = lib.mkEnableOption "desktop packages";

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
      lapwing-qt

      # Creative and engineering applications
      blender
      freecad
      kicad
      bambu-studio
    ];
  };
}
