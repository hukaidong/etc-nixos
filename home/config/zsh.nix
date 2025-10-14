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
    DOCKER_HOST = "unix:///run/podman/podman.sock";
    KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
  };

  home.shellAliases = {
    vim = "nvim";
  };

  home.sessionPath = [ "/home/kaidong/bin" ];
}
