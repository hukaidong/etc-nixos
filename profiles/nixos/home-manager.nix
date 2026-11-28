# The user layer of a NixOS host: Home Manager runs as part of the system
# switch, with the same pkgs (overlays included) as the system.
{ inputs, ... }:
{
  _class = "nixos";

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;

    backupFileExtension = "pre-homemanager";

    sharedModules = [
      inputs.plover-flake.homeManagerModules.plover
      inputs.sops-nix.homeManagerModules.sops
    ];

    users.kaidong.imports = [
      ../home/base.nix
      ../../modules/home
      ../home/desktop.nix
    ];
  };
}
