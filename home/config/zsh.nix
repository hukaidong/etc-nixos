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

    initContent = ''
      # Source custom RC file if it exists
      if [ -f "$HOME/.customrc" ]; then
        source "$HOME/.customrc"
      fi
    '';
  };

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
  };

  home.shellAliases = {
    vim = "nvim";
  };
}
