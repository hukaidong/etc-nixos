{ pkgs, ... }:
{
  environment = {
    sessionVariables = {
      LC_COLLATE = "C";
      EDITOR = "nvim";
      VISUAL = "nvim";
    };
  };

  programs.direnv.enable = true;
  programs.neovim.vimAlias = true;
  programs.nix-ld.enable = true;

  programs.direnv.settings = {
    global = {
      warn_timeout = "30s";
      hide_env_diff = true;
    };
  };
}
