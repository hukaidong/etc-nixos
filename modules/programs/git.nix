{ ... }:
{
  programs.git = {
    enable = true;
    lfs.enable = true;

    config = {
      init.defaultBranch = "main";

      safe.directory = [ "/etc/nixos" ];
    };
  };
}
