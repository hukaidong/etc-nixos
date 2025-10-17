{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    # TODO: The interaction between davfs2 and fuse3 is unchecked. davfs2
    # seems suffer from using fuse2 with Invalid argument errors, go back and
    # check if fuse3 could fix it.
    fuse3
  ];
  services.davfs2.enable = true;
  fileSystems."/mnt/datadav" = {
    device = "https://webdav.hukaidong.com";
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
