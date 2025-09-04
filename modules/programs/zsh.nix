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
    };
  };
}
