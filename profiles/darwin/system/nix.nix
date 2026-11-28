{ ... }:
{
  # nix-darwin manages the Nix daemon and /etc/nix/nix.conf (the GitHub runner
  # module requires it), replacing the official installer's copies. The
  # settings below carry over what the installer-era nix.conf held; the
  # daemon itself comes from nixpkgs' `nix`.
  nix.enable = true;
  nix.settings = {
    experimental-features = [
      "fetch-tree"
      "flakes"
      "nix-command"
    ];
    accept-flake-config = true;
    # nix-darwin already trusts root.
    trusted-users = [ "kaidong" ];
  };

  # Home-manager owns interactive shell setup (profiles/home/config/zsh.nix), so
  # nix-darwin leaves /etc/zshrc and /etc/bashrc alone. The zsh config puts
  # /run/current-system/sw/bin (darwin-rebuild, this Nix) on PATH instead.
  programs.zsh.enable = false;
  programs.bash.enable = false;
}
