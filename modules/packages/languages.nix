{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    # keep here minimum with only language use for quick
    # scripts and development environment setup
    ruby_3_4

    (python313.withPackages (
      ps: with ps; [
        isort
        pytest
      ]
    ))
    pipenv

    rustc
    cargo

    shellcheck
    pandoc
  ];
}
