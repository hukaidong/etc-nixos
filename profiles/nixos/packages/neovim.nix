{ pkgs, ... }:
{
  environment = {
    systemPackages = with pkgs; [
      # matches neovim configuration in github:hukaidong/dotconfig-nvim.git
      neovim-unwrapped
      tree-sitter
      stylua

      # Generally required by Github copilot
      nodejs_24
    ];
  };
}
