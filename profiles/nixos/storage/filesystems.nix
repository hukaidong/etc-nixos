{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    fuse3
  ];
  services.davfs2.enable = true;
  fileSystems."/mnt/datadav" = {
    device = "https://dav.hukaidong.com";
    fsType = "davfs";
    options = [
      "auto"
      "nofail"
      "user"
      "permissions"
      "uid=1000"
      "gid=100"
      "dmask=0027"
      "fmask=0137"
    ];
  };
}
