{ ... }:
{
  services.davfs2.enable = true;

  fileSystems."/mnt/datahdd" = {
    device = "/dev/disk/by-partuuid/c006ab82-5d80-4498-a990-8b02586c39b0";
    fsType = "ntfs-3g";
    options = [
      "permissions"
      "uid=1000"
      "gid=100"
      "auto"
      "nofail"
      "windows_names"
      "dmask=0027"
      "fmask=0137"
      "locale=en_US.utf8"
    ];
  };

  fileSystems."/mnt/datadav" = {
    device = "https://webdav.hukaidong.com";
    fsType = "davfs";
    options = [
      "auto"
      "nofail"
      "user"
    ];
  };
}