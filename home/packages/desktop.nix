{
  pkgs,
  lib,
  config,
  ...
}:
{
  options.modules.desktop.enable = lib.mkOption {
    type = lib.types.bool;
    default = pkgs.stdenv.isLinux;
    description = "Whether to enable desktop packages";
  };

  config = lib.mkIf config.modules.desktop.enable {
    home.packages = with pkgs; [
      # Productivity applications
      anki
      keepassxc
      zotero
      zathura
      thunderbird
      discord
      gimp3
    ];
  };
}
