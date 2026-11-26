# nix-darwin machines: the system layer (the Nix daemon, boot-time launchd
# jobs such as the GitHub Actions runners). The same machine's user layer is
# a standalone Home Manager configuration, in home.nix.
inputs@{ self, ... }:
{
  Kaidong-Mac-Studio = inputs.nix-darwin.lib.darwinSystem {
    specialArgs = { inherit inputs; };
    modules = [
      { nixpkgs.overlays = [ self.overlays.default ]; }
      { system.configurationRevision = self.rev or self.dirtyRev or null; }
      inputs.sops-nix.darwinModules.sops
      ./kaidong-mac-studio/configuration.nix
      ../modules/darwin
    ];
  };
}
