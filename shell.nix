# Development shell (`nix develop`, or direnv's `use flake`), one per platform
# this flake manages, so it works on the NixOS machines and the Mac Studio.
{ nixpkgs, ... }:
nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-darwin" ] (
  system:
  let
    pkgs = nixpkgs.legacyPackages.${system};
  in
  {
    default = pkgs.mkShell {
      packages = [
        # Refreshes flake.lock and checks that every machine still evaluates
        # before committing and pushing it.
        (pkgs.writeShellScriptBin "update" ''
          set -e
          nix flake update
          nix flake check --no-build --all-systems
          git commit -am "chore: Update flake.lock"
          git push
        '')

        # Sweeps the probes in ./upstream-checks and reports which upstream
        # workarounds can now be dropped. Scripts stay editable in-repo (not
        # baked into the store) so they are located relative to the git work
        # tree.
        (pkgs.writeShellApplication {
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
        })
      ];
      shellHook = ''
        echo "nix-config shell loaded."
        echo "  update          - update flake.lock, check every machine, push"
        echo "  upstream-check  - probe upstream fixes for carried workarounds"
      '';
    };
  }
)
