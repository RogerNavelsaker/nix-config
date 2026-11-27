# checks.nix
{
  pkgs,
  lib,
  self,
  herdr,
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

  resourceTreeCheck =
    let
      expectedHosts = [
        "alex"
        "avery"
        "ester-desktop"
        "jules"
        "mara"
        "mira"
        "rowan"
      ];
      expectedHomes = [
        "admin@ester-desktop"
        "admin@miniserver-01"
        "admin@miniserver-02"
        "admin@miniserver-03"
        "admin@nanoserver-01"
        "alex@agent-alex"
        "avery@agent-avery"
        "jules@agent-jules"
        "mara@agent-mara"
        "mira@agent-mira"
        "rowan@agent-rowan"
      ];
      lxcAgents = [
        "avery"
        "jules"
        "mira"
        "rowan"
      ];
      lxcAgentMatches =
        name:
        let
          config = self.nixosConfigurations.${name}.config;
        in
        config.networking.hostName == "agent-${name}"
        && config.hostSpec.users == [ name ]
        && config.users.users.${name}.isNormalUser
        && !config.services.openssh.enable;
    in
    assert builtins.all (name: builtins.hasAttr name self.nixosConfigurations) expectedHosts;
    assert builtins.all (name: builtins.hasAttr name self.homeConfigurations) expectedHomes;
    assert builtins.all (name: !(builtins.hasAttr name self.nixosConfigurations)) [
      "nanoserver-01"
      "miniserver-01"
      "miniserver-02"
      "miniserver-03"
    ];
    assert builtins.all
      (name: !(builtins.hasAttr name self.packages.${pkgs.stdenv.hostPlatform.system}))
      [
        "nanoserver-01-update-bundle"
        "nanoserver-01-update-v4-bundle"
      ];
    assert self.nixosConfigurations.iso.config.system.stateVersion == "25.11";
    assert !(builtins.hasAttr "roger-aio" self.nixosConfigurations);
    assert !(builtins.hasAttr "rona@aio" self.homeConfigurations);
    assert !(builtins.hasAttr "rona@roger-aio" self.homeConfigurations);
    assert !(builtins.hasAttr "rona@nanoserver-01" self.homeConfigurations);
    assert self.nixosConfigurations.ester-desktop.config.virtualisation.podman.enable;
    assert self.nixosConfigurations.ester-desktop.config.networking.firewall.enable;
    assert builtins.all lxcAgentMatches lxcAgents;
    assert self.nixosConfigurations.ester-desktop.config.networking.hostName == "services";
    assert self.nixosConfigurations.ester-desktop.config.wsl.defaultUser == "admin";
    assert self.nixosConfigurations.mara.config.networking.hostName == "agent-mara";
    assert self.nixosConfigurations.mara.config.wsl.enable;
    assert self.nixosConfigurations.mara.config.wsl.defaultUser == "mara";
    assert !self.nixosConfigurations.mara.config.wsl.wslConf.automount.enabled;
    assert !self.nixosConfigurations.mara.config.wsl.wslConf.interop.enabled;
    pkgs.runCommand "resource-tree-output-check" { } "touch $out";

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

  nanoserverWorkloadNixCheck = import ./tests/nanoserver-workload-nix.nix { inherit pkgs; };
  nanoserverWorkloadPodmanCheck = import ./tests/nanoserver-workload-podman.nix { inherit pkgs; };
  herdrServerCheck = import ./tests/herdr-server.nix { inherit pkgs herdr; };
  graftSecretRenderCheck = import ./tests/graft-secret-render.nix { inherit pkgs; };

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

  nanoserver-workload-nix = nanoserverWorkloadNixCheck;
  nanoserver-workload-podman = nanoserverWorkloadPodmanCheck;
  workflow-lint = actionlintCheck;
  herdr-server = herdrServerCheck;
  graft-secret-render = graftSecretRenderCheck;

  resource-tree = resourceTreeCheck;
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
          resourceTreeCheck
          nanoserverWorkloadNixCheck
          nanoserverWorkloadPodmanCheck
          herdrServerCheck
          graftSecretRenderCheck
          actionlintCheck
        ];
      }
      ''
        echo "All checks passed!"
        touch $out
      '';
}
