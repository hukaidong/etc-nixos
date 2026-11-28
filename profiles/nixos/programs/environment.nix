{
  environment = {
    sessionVariables = {
      LC_COLLATE = "C";
      EDITOR = "nvim";
      VISUAL = "nvim";
    };
  };

  programs = {
    direnv = {
      enable = true;
      settings = {
        global = {
          warn_timeout = "30s";
          hide_env_diff = true;
        };
      };
    };
    neovim.vimAlias = true;
    nix-ld.enable = true;
  };
}
