{
  description = "Modular NixOS configuration managing multiple machines with shared infrastructure";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-ruby.url = "github:bobvanderlinden/nixpkgs-ruby";
    nix-ai-tools.url = "github:numtide/nix-ai-tools";
    fakwin.url = "github:DMaroo/fakwin";
    home-manager.url = "github:nix-community/home-manager/release-26.05";
    nix-index-database.url = "github:nix-community/nix-index-database";
    plover-flake.url = "github:openstenoproject/plover-flake";
    sops-nix.url = "github:Mic92/sops-nix";
    fontconfig.url = "github:hukaidong/flake-fonts";

    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    fakwin.inputs.nixpkgs.follows = "nixpkgs";
    fontconfig.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nix-index-database,
      fakwin,
      ...
    }:
    let
      extraPkgsOverlay = {
        nixpkgs.overlays = [
          (
            final: prev:
            let
              system = final.stdenv.hostPlatform.system;
            in
            {
              # Custom package collections
              unstable = import inputs.nixpkgs-unstable {
                inherit system;
                config.allowUnfree = true;
              };
              ai-tools = inputs.nix-ai-tools.packages.${system};
              # WORKAROUND -- remove once upstream is fixed
              # (probe: upstream-checks/dsh.sh).  nixpkgs builds nodejs with
              # `zerocallusedregs` hardening, which breaks the
              # `node-addon-require-builtin` native addon that
              # `@deepseek-ai/dsh-app-boot` uses to reach Node internals.
              # Mounting any dsh profile then aborts in
              # installRuntimeInterception() with `Unsupported/no-getter`, so
              # `dsh` cannot start at all.
              #   https://github.com/numtide/llm-agents.nix/issues/9994
              #   https://github.com/NixOS/nixpkgs/issues/565667
              # The override rewrites the one offending call in
              # dsh-app-boot/lib/index.js to a plain `createRequire` (the
              # launcher already runs node with --expose-internals).  Call sites:
              # modules/packages/desktop.nix, modules/services/dsh.nix.
              dsh-patched = inputs.nix-ai-tools.packages.${system}.dsh.overrideAttrs (old: {
                postInstall = (old.postInstall or "") + ''
                        substituteInPlace \
                          $out/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-app-boot/lib/index.js \
                          --replace-fail \
                        'createRequire(import.meta.url)("node-addon-require-builtin")' \
                  '{ requireBuiltin: createRequire(import.meta.url) }'
                '';
              });

              # Custom packages
              ruby-custom = (inputs.nixpkgs-ruby.packages.${system}."ruby-4.0.0").override {
                docSupport = true;
              };
              myfonts = inputs.fontconfig.packages.${system}.default;

              # Workaround (gated: pipx < 1.16).  pipx 1.8.0's test suite
              # hardcodes the pre-spacing package-specifier format (`black@ url`)
              # while `packaging` 26 in nixos-26.05 serialises direct references
              # with a space (`black @ url`, pypa/packaging#953).  7 checkPhase
              # cases in test_fix_package_name / test_parse_specifier_for_metadata
              # fail; Hydra fails identically, so the output is not in
              # cache.nixos.org.  The package itself is fine (both spellings are
              # valid PEP 508), so deselect just those two tests and keep the
              # rest of the suite running.
              #
              # nixpkgs fixed this by moving to pipx >= 1.16 (NixOS/nixpkgs#536749,
              # not backported to 26.05 as of #522307).  Any version at or above
              # that line gets no override; instead it warns so we remember to
              # delete this gate once the pinned nixpkgs catches up.
              pipx =
                if prev.lib.versionOlder prev.pipx.version "1.16" then
                  prev.pipx.overridePythonAttrs (old: {
                    disabledTests = (old.disabledTests or [ ]) ++ [
                      "test_fix_package_name"
                      "test_parse_specifier_for_metadata"
                    ];
                  })
                else
                  prev.lib.warn ''
                    pipx ${prev.pipx.version} is at or above the 1.16 fix line, so
                    the packaging-26 test workaround in flake.nix is obsolete.
                    Please remove the pipx gate in extraPkgsOverlay and add an
                    upstream check (see upstream-checks/) if one is still needed.'' prev.pipx;
            }
          )
        ];
      };

      sysRevConfig = {
        system.configurationRevision = self.rev or self.dirtyRev or null;
      };

      commonNixModules = with inputs; [
        extraPkgsOverlay
        sysRevConfig
        fakwin.nixosModules.default
        home-manager.nixosModules.home-manager
        sops-nix.nixosModules.sops
      ];
      mkUpdateCommand =
        pkgs:
        pkgs.writeShellScriptBin "update" ''
          set -e
          nix flake update
          git commit -am "chore: Update flake.lock"
          git push
        '';
      # Sweeps the probes in ./upstream-checks and reports which upstream
      # workarounds can now be dropped. Scripts stay editable in-repo (not baked
      # into the store) so they are located relative to the git work tree.
      mkUpstreamCheck =
        pkgs:
        pkgs.writeShellApplication {
          name = "upstream-check";
          runtimeInputs = with pkgs; [
            jq
            git
          ];
          text = ''
            root="$(git rev-parse --show-toplevel)"
            dir="$root/upstream-checks"
            shopt -s nullglob
            scripts=( "$dir"/*.sh )
            if [ ''${#scripts[@]} -eq 0 ]; then
              echo "No upstream checks found in $dir"
              exit 0
            fi
            echo "Sweeping ''${#scripts[@]} upstream check(s)..."
            echo
            clear_list=()
            for s in "''${scripts[@]}"; do
              rc=0
              bash "$s" || rc=$?
              case "$rc" in
                1) clear_list+=( "$(basename "$s" .sh)" ) ;;
                2) echo "   (probe error in $(basename "$s"))" ;;
              esac
              echo
            done
            echo "================ summary ================"
            if [ ''${#clear_list[@]} -eq 0 ]; then
              echo "All workarounds still required; no upstream path cleared yet."
            else
              echo "Upstream path CLEAR for: ''${clear_list[*]}"
              echo "  -> remove the matching workaround and its check script."
            fi
          '';
        };
    in
    {
      devShells.x86_64-linux.default =
        let
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
          update-command = mkUpdateCommand pkgs;
          upstream-check-command = mkUpstreamCheck pkgs;
        in
        pkgs.mkShell {
          packages = [
            update-command
            upstream-check-command
          ];
          shellHook = ''
            echo "NixOS config shell loaded."
            echo "  update          - update flake.lock and push"
            echo "  upstream-check  - probe upstream fixes for carried workarounds"
          '';
        };

      # Main desktop with pure i3
      nixosConfigurations.Kaidong-Main-Desktop = nixpkgs.lib.nixosSystem {
        specialArgs = {
          inherit inputs;
          desktopEnvironment = "i3";
        };
        modules = commonNixModules ++ [
          ./home/nixos-home.nix
          ./hosts/kaidong-main-desktop/configuration.nix
          ./modules/all.nix
        ];
      };

      # Main desktop with Plasma 6
      nixosConfigurations.Kaidong-Main-Desktop-Plasma = nixpkgs.lib.nixosSystem {
        specialArgs = {
          inherit inputs;
          desktopEnvironment = "plasma6";
        };
        modules = commonNixModules ++ [
          ./home/nixos-home.nix
          ./hosts/kaidong-main-desktop/configuration.nix
          ./modules/all.nix
        ];
      };

      nixosConfigurations.Kaidong-MBP14 = nixpkgs.lib.nixosSystem {
        specialArgs = {
          inherit inputs;
        };
        modules = commonNixModules ++ [
          nix-index-database.nixosModules.nix-index

          ./home/nixos-home.nix
          ./hosts/kaidong-mbp14/configuration.nix
          ./modules/all.nix
        ];
      };

      homeConfigurations.Kaidong-Mac-Studio =
        let
          system = "aarch64-darwin";
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
            overlays = extraPkgsOverlay.nixpkgs.overlays;
          };
          pkgs-unstable = import inputs.nixpkgs-unstable {
            inherit system;
            config.allowUnfree = true;
          };
        in
        inputs.home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          extraSpecialArgs = {
            inherit pkgs-unstable;
            inherit (inputs) plover-flake;
            homePath = "/Users";
          };
          modules = [
            (import ./home/home.nix { standalone = true; })
            inputs.plover-flake.homeManagerModules.plover
            inputs.sops-nix.homeManagerModules.sops
            inputs.nix-index-database.homeModules.default
          ];
        };

      # VM-based module tests
      checks.x86_64-linux =
        let
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
          inherit (pkgs) lib;
        in
        {
          virtualisation-test = pkgs.testers.nixosTest (
            import ./tests/modules/virtualisation-test.nix { inherit pkgs lib; }
          );
          virt-manager-test = pkgs.testers.nixosTest (
            import ./tests/modules/virt-manager-test.nix { inherit pkgs lib; }
          );
        };
    };
}
