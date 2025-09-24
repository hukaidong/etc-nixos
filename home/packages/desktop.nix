{
  pkgs,
  pkgs-unstable,
  nix-ai-tools-pkgs,
  ...
}:
{
  home.packages = with pkgs; [
    # Productivity applications
    anki
    keepassxc
    zotero
    zathura
    thunderbird
    discord
    gimp3

    # Fast developing application using unstable packages
    pkgs-unstable.android-studio
    pkgs-unstable.jetbrains-toolbox

    # Development IDEs and editors
    nix-ai-tools-pkgs.opencode
    nix-ai-tools-pkgs.claude-code
    nix-ai-tools-pkgs.cursor-agent
  ];
}
