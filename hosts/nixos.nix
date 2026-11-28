# NixOS machines. A host's configuration.nix holds its hardware and settings
# and imports the profiles it uses; every host also gets the modules below.
inputs@{ self, nixpkgs, ... }:
let
  mkNixos =
    host:
    nixpkgs.lib.nixosSystem {
      specialArgs = { inherit inputs; };
      modules = [
        { nixpkgs.overlays = [ self.overlays.default ]; }
        { system.configurationRevision = self.rev or self.dirtyRev or null; }
        inputs.home-manager.nixosModules.home-manager
        inputs.sops-nix.nixosModules.sops
        inputs.fakwin.nixosModules.default
        host
        ../modules/nixos
      ];
    };
in
{
  # Main desktop, booting into i3
  Kaidong-Main-Desktop = mkNixos ./kaidong-main-desktop/configuration.nix;

  # The same machine with Plasma 6 on Wayland
  Kaidong-Main-Desktop-Plasma = self.nixosConfigurations.Kaidong-Main-Desktop.extendModules {
    modules = [ { kaidong-desktop.desktopEnvironment.session = "plasma6"; } ];
  };

  Kaidong-MBP14 = mkNixos ./kaidong-mbp14/configuration.nix;
}
