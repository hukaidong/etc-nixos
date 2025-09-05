{ ... }:
{
  programs.zsh = {
    enable = true;

    ohMyZsh = {
      enable = true;
      theme = "robbyrussell";
    };

    shellAliases = {
      nixb = "sudo nixos-rebuild";
      nixh = "( pushd /etc/nixos > /dev/null ; sudo nix flake update home; popd > /dev/null )";
      groot = "cd $(git rev-parse --show-toplevel)";
    };
  };
}
