{ osConfig, ... }:
{
  nix.extraOptions = ''
    !include ${osConfig.sops.secrets."nix-access-tokens-user".path}
  '';
}
