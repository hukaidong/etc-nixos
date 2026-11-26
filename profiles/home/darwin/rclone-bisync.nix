{ pkgs, config, ... }:
{
  home.packages = [ pkgs.rclone ];

  launchd.agents.rclone-bisync-org = {
    enable = true;
    config = {
      Label = "org.nix.rclone-bisync-org";
      ProgramArguments = [
        "${pkgs.rclone}/bin/rclone"
        "bisync"
        "${config.home.homeDirectory}/org"
        "gdrive:org"
        "--create-empty-src-dirs"
        "--compare"
        "size,modtime,checksum"
        "--resilient"
        "-v"
      ];
      StartCalendarInterval = [{ Minute = 5; }];
      UserName = config.home.username;
      StandardOutPath = "/tmp/rclone-bisync-org.log";
      StandardErrorPath = "/tmp/rclone-bisync-org.err";
    };
  };
}
