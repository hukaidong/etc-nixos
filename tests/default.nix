# Flake checks: the VM tests of the virtualisation modules, plus every
# machine's system (and the Mac's Home Manager generation), so a machine that
# no longer evaluates or builds fails `nix flake check`. A machine's check
# sits under the system it builds on; `nix flake check --no-build
# --all-systems` evaluates all of them from any one machine. Each system also
# has the formatting check.
{
  self,
  nixpkgs,
  treefmt-nix,
  ...
}:
let
  inherit (nixpkgs) lib;
  pkgs = nixpkgs.legacyPackages.x86_64-linux;

  # <prefix>-<name> = drv for every configuration in `configs`.
  machines =
    prefix: drv: configs:
    lib.mapAttrs' (name: config: lib.nameValuePair "${prefix}-${name}" (drv config)) configs;
  system = config: config.config.system.build.toplevel;

  # Fails when `nix fmt` would change a file or a lint is left that it cannot
  # fix (treefmt.nix). Run `nix fmt` and commit the result.
  formatting =
    system:
    let
      treefmt = treefmt-nix.lib.evalModule nixpkgs.legacyPackages.${system} ../treefmt.nix;
    in
    {
      formatting = treefmt.config.build.check self;
    };
in
{
  x86_64-linux = {
    virtualisation-test = pkgs.testers.nixosTest (
      import ./modules/virtualisation-test.nix { inherit pkgs lib; }
    );
    virt-manager-test = pkgs.testers.nixosTest (
      import ./modules/virt-manager-test.nix { inherit pkgs lib; }
    );
  }
  // machines "nixos" system self.nixosConfigurations
  // formatting "x86_64-linux";

  aarch64-darwin =
    machines "darwin" system self.darwinConfigurations
    // machines "home" (config: config.activationPackage) self.homeConfigurations
    // formatting "aarch64-darwin";
}
