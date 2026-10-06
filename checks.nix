# checks.nix
{
  pkgs,
  lib,
  self,
  diskoLib,
  diskoModule,
}:
let
  # Use nixpkgs lib for standard functions
  inherit (pkgs.lib) mapAttrs' nameValuePair;
  # Path to repository root
  pathFromRoot = lib.path.append ./.;

  # Check that all NixOS configurations build
  nixosChecks = mapAttrs' (
    name: config: nameValuePair "nixos-${name}" config.config.system.build.toplevel
  ) self.nixosConfigurations;

  # Check that all home-manager configurations build
  homeChecks = mapAttrs' (
    name: config: nameValuePair "home-${name}" config.activationPackage
  ) self.homeConfigurations;

  nanoserverProfiles = [
    "nanoserver-01"
    "nanoserver-01-slot-b"
    "nanoserver-01-update-v2-a"
    "nanoserver-01-update-v2-b"
  ];
  passwordlessSudoCheck =
    assert builtins.all (
      profile: !self.nixosConfigurations.${profile}.config.security.sudo.wheelNeedsPassword
    ) nanoserverProfiles;
    assert self.nixosConfigurations.miniserver-01.config.security.sudo.wheelNeedsPassword;
    pkgs.runCommand "passwordless-sudo-opt-in-check" { } "touch $out";

  # Check formatting (--no-require-git needed since store path has no .git)
  formatCheck = pkgs.runCommand "format-check" { } ''
    cd ${pathFromRoot "."}
    ${pkgs.fd}/bin/fd --no-require-git -e nix -x ${pkgs.nixfmt-rfc-style}/bin/nixfmt --check
    touch $out
  '';

  # Check for dead code / unused imports
  deadnixCheck = pkgs.runCommand "deadnix-check" { } ''
    cd ${pathFromRoot "."}
    ${pkgs.fd}/bin/fd --no-require-git -e nix -0 | xargs -0 ${pkgs.deadnix}/bin/deadnix --fail
    touch $out
  '';

  # Check for anti-patterns and improvements with statix
  statixCheck = pkgs.runCommand "statix-check" { } ''
    cd ${pathFromRoot "."}
    ${pkgs.statix}/bin/statix check .
    touch $out
  '';

  # Check nix file syntax
  nixSyntaxCheck = pkgs.runCommand "nix-syntax-check" { } ''
    cd ${pathFromRoot "."}
    # Wrapper to distinguish syntax errors from harmless profile warnings
    check_syntax() {
      output=$(${pkgs.nix}/bin/nix-instantiate --parse "$1" 2>&1)
      status=$?
      # Exit 0 = success, non-zero with "error: syntax error" = real error
      # Profile permission warnings return non-zero but aren't syntax errors
      if [ $status -ne 0 ] && echo "$output" | grep -q "error: syntax error"; then
        echo "Syntax error in $1:"
        echo "$output"
        return 1
      fi
      return 0
    }
    export -f check_syntax
    ${pkgs.fd}/bin/fd --no-require-git -e nix -x bash -c 'check_syntax "$0"'
    touch $out
  '';

  nanoserverSlotUkiCheck = import ./tests/nanoserver-slot-uki.nix { inherit lib pkgs self; };
  hostPlatformCheck = import ./tests/host-platform.nix { inherit lib pkgs self; };
  fluxBaselineCheck =
    pkgs.runCommand "flux-gitops-manifests-check"
      {
        nativeBuildInputs = [ pkgs.kustomize ];
      }
      ''
        kustomize build ${pathFromRoot "clusters/nanoserver-miniservers"} > "$out"
        grep -q 'kind: Namespace' "$out"
        grep -q 'name: platform-system' "$out"
      '';
  actionlintCheck =
    pkgs.runCommand "github-actions-workflows-check"
      {
        nativeBuildInputs = [ pkgs.actionlint ];
      }
      ''
        cd ${pathFromRoot ".github/workflows"}
        actionlint *.yml
        touch "$out"
      '';
  nanoserverV4AssetSizeCheck =
    let
      bundle = self.packages.${pkgs.stdenv.hostPlatform.system}.nanoserver-01-update-v4-bundle;
    in
    pkgs.runCommand "nanoserver-v4-release-asset-size-check" { } ''
      size=$(stat -c '%s' ${bundle}/nanoserver-store_4.tar.xz)
      if (( size > 1900000000 )); then
        echo "Nanoserver v4 store archive exceeds the 1.9 GB GitHub Release budget: $size bytes" >&2
        exit 1
      fi
      touch "$out"
    '';
  nanoserverDiskoTests = lib.optionalAttrs pkgs.stdenv.hostPlatform.isx86_64 {
    nanoserver-01-disko-layout = import ./tests/nanoserver-disko-layout.nix {
      inherit
        diskoLib
        diskoModule
        lib
        pkgs
        self
        ;
    };
  };
  miniserverDiskoTests = lib.optionalAttrs pkgs.stdenv.hostPlatform.isx86_64 (
    builtins.listToAttrs (
      map
        (hostname: {
          name = "${hostname}-disko-layout";
          value = import ./tests/miniserver-disko-layout.nix {
            inherit
              diskoLib
              diskoModule
              lib
              pkgs
              self
              hostname
              ;
          };
        })
        [
          "miniserver-01"
          "miniserver-02"
          "miniserver-03"
        ]
    )
  );

  # Validate feature structure
  featureStructureCheck =
    pkgs.runCommand "feature-structure-check"
      {
        buildInputs = [ pkgs.nix ];
      }
      ''
        # Check that feature directories exist
        test -d ${pathFromRoot "hosts/features"} || (echo "hosts/features not found" && exit 1)
        test -d ${pathFromRoot "users/features"} || (echo "users/features not found" && exit 1)

        # Check that default/opt-in/opt-out subdirectories exist
        test -d ${pathFromRoot "hosts/features/default"} || (echo "hosts/features/default not found" && exit 1)
        test -d ${pathFromRoot "hosts/features/opt-in"} || (echo "hosts/features/opt-in not found" && exit 1)
        test -d ${pathFromRoot "hosts/features/opt-out"} || (echo "hosts/features/opt-out not found" && exit 1)

        touch $out
      '';

in
nixosChecks
// homeChecks
// nanoserverDiskoTests
// miniserverDiskoTests
// {
  inherit
    formatCheck
    deadnixCheck
    statixCheck
    nixSyntaxCheck
    featureStructureCheck
    passwordlessSudoCheck
    ;

  nanoserver-01-slot-uki = nanoserverSlotUkiCheck;
  workflow-lint = actionlintCheck;
  host-platform = hostPlatformCheck;
  flux-manifests = fluxBaselineCheck;
  nanoserver-v4-asset-size = nanoserverV4AssetSizeCheck;

  # All checks combined
  all =
    pkgs.runCommand "all-checks"
      {
        buildInputs =
          builtins.attrValues (nixosChecks // homeChecks)
          ++ [
            formatCheck
            deadnixCheck
            statixCheck
            nixSyntaxCheck
            featureStructureCheck
            passwordlessSudoCheck
            nanoserverSlotUkiCheck
            hostPlatformCheck
            actionlintCheck
            fluxBaselineCheck
            nanoserverV4AssetSizeCheck
          ]
          ++ builtins.attrValues nanoserverDiskoTests
          ++ builtins.attrValues miniserverDiskoTests;
      }
      ''
        echo "All checks passed!"
        touch $out
      '';
}
