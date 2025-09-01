{ pkgs, ... }:
{
  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment = {
    systemPackages = with pkgs; [
      git
      neovim 
      nixfmt-rfc-style
      wget
      zsh
      gcc15
    ];

    shellAliases = {
      vim = "nvim";
    };

    sessionVariables = {
      LC_COLLATE = "C";  # ls list .dotfiles before others
      EDITOR = "nvim";
      VISUAL = "nvim";
    };
  };
}
