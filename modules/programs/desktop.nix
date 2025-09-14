{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    polonium
  ];
}
