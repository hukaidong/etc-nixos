{
  description = "Modular NixOS configuration managing multiple machines with shared infrastructure";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-ruby.url = "github:bobvanderlinden/nixpkgs-ruby";
    nix-ai-tools.url = "github:numtide/nix-ai-tools";
    fakwin.url = "github:DMaroo/fakwin";
    home-manager.url = "github:nix-community/home-manager/release-26.05";
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-index-database.url = "github:nix-community/nix-index-database";
    plover-flake.url = "github:openstenoproject/plover-flake";
    sops-nix.url = "github:Mic92/sops-nix";
    fontconfig.url = "github:hukaidong/flake-fonts";
    lapwingqt.url = "github:kd-lapwings/lapwingqt";

    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    fakwin.inputs.nixpkgs.follows = "nixpkgs";
    fontconfig.inputs.nixpkgs.follows = "nixpkgs";
  };

  # Each output is built in the file named here; see the README for the layout.
  outputs = inputs: {
    nixosConfigurations = import ./hosts/nixos.nix inputs;
    darwinConfigurations = import ./hosts/darwin.nix inputs;
    homeConfigurations = import ./hosts/home.nix inputs;

    overlays.default = import ./overlays inputs;
    checks = import ./tests inputs;
    devShells = import ./shell.nix inputs;
  };
}
