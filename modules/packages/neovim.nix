{ pkgs, ... }:
{
  environment = {
    systemPackages = with pkgs; [
      neovim-unwrapped
      # Generally required by Github copilot
      nodejs_24
    ];
  };
}
