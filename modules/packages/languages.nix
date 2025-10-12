{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    # Python development
    (python313.withPackages (p: with p; [
      pip
      numpy
      ipython
      jupyter
    ]))

    nodejs_latest
  ];
}
