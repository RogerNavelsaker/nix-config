# checks.nix
{
  pkgs,
  lib,
  self,
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
// {
  inherit
    formatCheck
    deadnixCheck
    statixCheck
    nixSyntaxCheck
    featureStructureCheck
    ;

  # All checks combined
  all =
    pkgs.runCommand "all-checks"
      {
        buildInputs = builtins.attrValues (nixosChecks // homeChecks) ++ [
          formatCheck
          deadnixCheck
          statixCheck
          nixSyntaxCheck
          featureStructureCheck
        ];
      }
      ''
        echo "All checks passed!"
        touch $out
      '';
}
