{ pkgs, lib, ... }:
{
  programs.zsh = {
    enable = true;
    enableCompletion = true;

    plugins = [
      {
        name = "fzf-tab";
        src = "${pkgs.zsh-fzf-tab}/share/fzf-tab";
      }
    ];

    oh-my-zsh = {
      enable = true;
      theme = lib.mkDefault "robbyrussell";
    };

    sessionVariables = {
      ZSH_CUSTOM = ../../configs/omz-custom;
    };

    initContent = ''
      # Source custom RC file if it exists
      if [ -f "$HOME/.customrc" ]; then
        source "$HOME/.customrc"
      fi
    ''
    + lib.optionalString pkgs.stdenv.isDarwin ''
      # Nix
      if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
        . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
      fi
      # End Nix
    '';
  };

  home.sessionVariables = {
    KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
  };

  home.sessionPath = [
    "$HOME/.config/emacs/bin" # Doom Emacs
  ];

  home.shellAliases = {
    vim = "nvim";
    e = "emacsclient -c -n";

    gs = "git status";
    gd = "git diff";
    gdd = "git diff --cached";
    gl = "git log --oneline --graph --decorate";
    gca = "git commit --amend";
    groot = "git status >/dev/null && cd $(git rev-parse --show-toplevel)";
  };
}
