{ pkgs, ... }:

{
  programs.gh = {
    enable = true;
    gitCredentialHelper = {
      enable = true;
    };
  };

  programs.git = {
    enable = true;
    attributes = [
      "*.lock binary"
      "gemset.nix binary"
    ];
    ignores = [
      # IntelliJ project files
      ".idea"
      ".idea/*"
      ".iml"
      "out"
      "gen"

      # Vim
      "*~"
      "*.swp"
      "tags"

      # Emacs
      ".auctex-auto"

      # R
      ".RData"
      ".Rhistory"

      # Ruby yard
      ".yardoc"

      # Local files / runtimes
      ".localfiles"
      ".lvimrc"
      ".envrc"
      ".direnv"
      "result"

      # Git merges
      "*.orig"

      # Claude
      ".claude/*"
      "!.claude/skills"
    ];
    settings = {
      user.name = "Kaidong Hu";
      user.email = "hukaidonghkd@gmail.com";
      diff.tool = "nvimdiff";
      merge.tool = "nvimdiff";
    };
  };
}
