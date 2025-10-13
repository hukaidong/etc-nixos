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
  ];
}
