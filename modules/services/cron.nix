{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    cron
  ];
  services.cron.enable = true;
}
