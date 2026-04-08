{
  pkgs,
  lib,
  config,
  ...
}@args:
let
  hasOsConfig = args ? osConfig;
in
{
  options.modules.nixAccessTokens.enable = lib.mkOption {
    type = lib.types.bool;
    default = hasOsConfig;
    description = "Whether to enable nix access tokens from sops";
  };

  config = lib.mkIf config.modules.nixAccessTokens.enable {
    nix.extraOptions = ''
      !include ${args.osConfig.sops.secrets."nix-access-tokens-user".path}
    '';
  };
}
