{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.kaidong-desktop.virtualization.virtManager;
in
{
  options.kaidong-desktop.virtualization.virtManager = {
    enable = mkEnableOption "Virtual Machine Manager";
  };

  config = mkIf cfg.enable {
    programs.virt-manager.enable = true;
    users.groups.libvirtd.members = [ "kaidong" ];
    virtualisation.libvirtd.enable = true;
    virtualisation.spiceUSBRedirection.enable = true;
  };
}
