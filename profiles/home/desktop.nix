# Desktop applications for the users of my NixOS machines: turns on the
# package sets in ../../modules/home/packages.
{
  _class = "homeManager";

  modules.desktop.enable = true;
  modules.plover.enable = true;
}
