{ config, lib, ... }:
let
  cfg = config.kaidong-desktop.desktopEnvironment;
in
{
  # Picks exactly one of the desktop modules beside this file, so two of them
  # can never be enabled together. hosts/nixos.nix uses it to build the main
  # desktop a second time with Plasma 6.
  options.kaidong-desktop.desktopEnvironment.session = lib.mkOption {
    type = lib.types.nullOr (
      lib.types.enum [
        "i3"
        "plasma-i3"
        "plasma6"
      ]
    );
    default = null;
    example = "plasma6";
    description = ''
      The desktop session this machine boots into: i3 alone (X11), Plasma 6
      with i3 as its window manager (X11), or Plasma 6 on Wayland. Enables the
      matching `kaidong-desktop.desktopEnvironment.<session>` module.
    '';
  };

  config.kaidong-desktop.desktopEnvironment = {
    i3.enable = lib.mkIf (cfg.session == "i3") true;
    plasma-i3.enable = lib.mkIf (cfg.session == "plasma-i3") true;
    plasma6.enable = lib.mkIf (cfg.session == "plasma6") true;
  };
}
