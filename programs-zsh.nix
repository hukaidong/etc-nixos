{ ... }:
{
  programs.zsh = {
    enable = true;

    ohMyZsh = {
      enable = true;
      theme = "robbyrussell";
    };

    shellAliases = {
      vim = "nvim";
      nixb = "sudo nixos-rebuild";
    };
  };
}
