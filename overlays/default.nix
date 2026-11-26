# Packages this flake adds to nixpkgs, available as pkgs.<name> on every
# machine. Package sets from other flakes are exposed whole, per system.
inputs: final: _prev:
let
  inherit (final.stdenv.hostPlatform) system;
in
{
  # Fast-moving packages, e.g. pkgs.unstable.devenv
  unstable = import inputs.nixpkgs-unstable {
    inherit system;
    config.allowUnfree = true;
  };

  # Daily updated AI tools, e.g. pkgs.ai-tools.claude-code
  ai-tools = inputs.nix-ai-tools.packages.${system};

  # Plover and its plugins, e.g. pkgs.plover-flake.plover.withPlugins
  plover-flake = inputs.plover-flake.packages.${system};

  ruby-custom = (inputs.nixpkgs-ruby.packages.${system}."ruby-4.0.0").override {
    docSupport = true;
  };
  myfonts = inputs.fontconfig.packages.${system}.default;
  lapwing-qt = inputs.lapwingqt.packages.${system}.default;
}
