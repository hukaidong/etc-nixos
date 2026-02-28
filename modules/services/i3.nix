{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.kaidong-desktop.desktopEnvironment.i3;
in
{
  # TODO: Remove unstable import once services.dunst is available in stable nixpkgs
  imports = [
    "${inputs.nixpkgs-unstable}/nixos/modules/services/desktops/dunst.nix"
  ];

  options.kaidong-desktop.desktopEnvironment.i3 = {
    enable = lib.mkEnableOption "i3 only with de support (X11)";
  };

  config = lib.mkMerge [
    (lib.mkIf (cfg.enable && config.system.nixos.release != "25.11") {
      warnings = [
        "kaidong-desktop.desktopEnvironment.i3: services.dunst is imported from nixpkgs-unstable. Since NixOS is no longer 25.11, this module may now be available in stable nixpkgs. Consider removing the unstable import in modules/services/i3.nix."
      ];
    })

    (lib.mkIf cfg.enable {
      environment.systemPackages = with pkgs; [
        kdePackages.kwallet
      ];

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
          configFile = ../../configs/i3-config;
        };
      };

      environment.etc."i3/workspace-layout.sh" = {
        source = ../../configs/i3-workspace-layout.sh;
        mode = "0755";
      };

      environment.etc."i3/wallpapers" = {
        source = ../../configs/wallpapers;
      };

      services = {
        picom.enable = true;
        dunst.enable = true;
        displayManager.sddm.enable = true;
        autorandr.enable = true;
        gvfs.enable = true;
        tumbler.enable = true;
      };

      programs = {
        thunar.enable = true;
        thunar.plugins = with pkgs.xfce; [
          thunar-archive-plugin
          thunar-media-tags-plugin
          thunar-volman
        ];
      };

      systemd.services.autorandr.enable = false;
    })
  ];
}
