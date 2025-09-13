{
  config,
  pkgs,
  lib,
  ...
}:
{
  systemd.user.services.davmail = {
    enable = true;
    description = "DavMail POP/IMAP/SMTP/Caldav/Carddav/LDAP Exchange Gateway";
    after = [ "network.target" ];
    wantedBy = lib.mkForce [ ]; # Manual start only
    unitConfig.ConditionUser = "kaidong"; # Only run for user kaidong (UID 1000)
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.davmail}/bin/davmail /home/kaidong/.config/davmail.properties";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };
}
