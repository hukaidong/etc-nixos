{ pkgs, ... }:
# TODO: There's a duplicate zsh configuration in module/program/zsh.nix,
# Research and merge them together.
# home.* should be used for user specific configuration
# and program.* should be configured for cross-user settings.
{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    oh-my-zsh = {
      enable = true;
      theme = "robbyrussell";
    };
    sessionVariables = { };
  };

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };

  home.shellAliases = {
    vim = "nvim";
  };

  home.sessionPath = [ "/home/kaidong/bin" ];
}
