{ ... }:
{
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
    persistent = true;
    randomizedDelaySec = "45min";
  };

  nix.settings.auto-optimise-store = true;
}
