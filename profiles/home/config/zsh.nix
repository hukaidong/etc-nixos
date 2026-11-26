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
      # Interpolated, so only this directory is copied to the store and the
      # generation depends on it. A bare path points into the store copy of
      # the whole flake, without depending on it (#11).
      ZSH_CUSTOM = "${../../../configs/omz-custom}";
    };

    initContent = ''
      # Source custom RC file if it exists
      if [ -f "$HOME/.customrc" ]; then
        source "$HOME/.customrc"
      fi
    ''
    + lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''
      # Nix
      if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
        . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
      fi
      # End Nix

      # nix-darwin's system profile (darwin-rebuild, and the Nix that
      # nix-darwin manages) goes ahead of the installer's default profile but
      # after the user's own. nix-darwin leaves /etc/zshrc alone, so it is
      # added here.
      if [[ -d /run/current-system/sw/bin && ''${path[(Ie)/run/current-system/sw/bin]} -eq 0 ]]; then
        path[''${path[(ie)/nix/var/nix/profiles/default/bin]},0]=(/run/current-system/sw/bin)
      fi
    '';
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
    gca = "git commit --verbose --all";
    groot = "git status >/dev/null && cd $(git rev-parse --show-toplevel)";
  };
}
