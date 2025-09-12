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
      nixs = "xdg-open https://search.nixos.org/packages";
      groot = "cd $(git rev-parse --show-toplevel)";
    };
  };
}
