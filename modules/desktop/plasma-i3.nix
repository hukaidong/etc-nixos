{ config, options, lib, pkgs, ... }:
let
  cfg = config.kaidong-desktop.desktopEnvironment.plasma-i3;
in
{
  options.kaidong-desktop.desktopEnvironment.plasma-i3 = {
    enable = lib.mkEnableOption "Plasma 6 with i3 window manager (X11)";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        services.xserver = {
          enable = true;
          xkb = {
            layout = "us";
            variant = "dvp";
          };

          windowManager.i3 = {
            enable = true;
            extraPackages = with pkgs; [
              dmenu
              feh
              i3status
              picom
            ];
            configFile = ../../configs/i3-plasma-config;
          };
          desktopManager.session = [
            {
              manage = "desktop";
              name = "plasma-i3wm";
              start = "KDEWM=${pkgs.i3}/bin/i3 /run/current-system/sw/bin/startplasma-x11";
            }
          ];
        };

        services.desktopManager.plasma6.enable = true;

        # Troubleshooting flickering issues with nvidia drivers
        # See https://nixos.wiki/wiki/Nvidia#Fix_app_flickering_with_Picom
        services.picom.enable = true;

        services.displayManager.sddm.enable = true;
        services.displayManager.defaultSession = "plasma-i3wm+i3";

        # Disable the real KWin, fakwin stands in for it (see below)
        systemd.user.services.plasma-kwin_x11.enable = false;
      }

      # This module is imported by every configuration (via modules/all.nix),
      # but the fakwin module is not: flake.nix only pulls it in for hosts that
      # actually need it.  An option definition written here is checked for
      # existence regardless of the enclosing mkIf (the check runs on the
      # definition, before conditions are applied), so a plain
      # `services.fakwin.enable = true` would make *every* configuration
      # require the fakwin module.  Emit the definition only when the option is
      # actually declared, i.e. when the fakwin module is imported.  `options`
      # is the declaration tree, so testing it here cannot recurse back into
      # this definition the way `config.services ? fakwin` would.
      (lib.optionalAttrs (options.services ? fakwin) {
        services.fakwin.enable = true;
      })
    ]
  );
}
