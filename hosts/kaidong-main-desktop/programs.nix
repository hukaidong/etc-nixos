{ pkgs, ... }:
with pkgs;
{
  kaidong-desktop.programs.emacs = {
    enable = true;
    enableMailSupport = true;
  };

  kaidong-desktop.services = {
    davMail.enable = true;
    davMail-backup.enable = true;
  };

  services.ollama.enable = true;
  services.ollama.package = unstable.ollama-rocm;

  nixpkgs.config.rocmSupport = true;
}
