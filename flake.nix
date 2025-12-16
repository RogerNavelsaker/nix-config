# flake.nix
{
  description = "System config flake";

  nixConfig = {
    extra-substituters = [
      "https://cachix.cachix.org"
      "https://nix-community.cachix.org"
    ];

    extra-trusted-public-keys = [
      "cachix.cachix.org-1:eWNHQldwUO7G2VkjpnjDbWwy4KQ/HNxht7H4SSoMckM="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-24.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-master.url = "github:NixOS/nixpkgs/master";

    systems.url = "github:nix-systems/default-linux";

    nix-lib = {
      url = "github:RogerNavelsaker/nix-lib";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.systems.follows = "systems";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    impermanence.url = "github:nix-community/impermanence";
    hardware.url = "github:NixOS/nixos-hardware";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    comin = {
      url = "github:nlewo/comin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    devshell = {
      url = "github:numtide/devshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    determinate.url = "github:DeterminateSystems/determinate";

    pog = {
      url = "github:jpetrucciani/pog";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Private repo - use git+file for local dev
    nix-secrets = {
      url = "git+file:../nix-secrets";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nix-lib,
      ...
    }@inputs:
    let
      # Create the lib using nix-lib
      lib = nix-lib.lib.mkLib {
        inherit inputs;
        root = ./.;
        # Use default paths (hosts, home, modules, overlays, pkgs, hosts/features, home/features)
      };
    in
    {
      inherit lib;
      nixosModules.default = import ./modules/nixos;
      homeManagerModules.default = import ./modules/home-manager;
      overlays = import ./overlays {
        inherit inputs;
        inherit (nixpkgs) lib;
      };
      packages = lib.forEachSystem (
        pkgs:
        import ./pkgs {
          inherit pkgs;
          inherit (nixpkgs) lib;
        }
      );
      formatter = lib.forEachSystem (pkgs: pkgs.nixfmt-rfc-style);
      devShells = lib.forEachSystem (pkgs: import ./shell.nix { inherit inputs pkgs; });
      checks = lib.forEachSystem (
        pkgs:
        import ./checks.nix {
          inherit pkgs self;
          inherit (nixpkgs) lib;
        }
      );

      # NixOS configurations
      nixosConfigurations = lib.mkSystems {
        nanoserver = {
          hostname = "nanoserver";
          users = [ "rona" ];
          system = "x86_64-linux";
          stateVersion = "25.11";
          #secrets = inputs.nix-secrets;
          features = {
            # opt-in = [ "tailscale" "docker" ];
            # opt-out = [ "impermanence" ];
          };
        };

        iso = {
          hostname = "iso";
          users = [ "rona" ];
          system = "x86_64-linux";
          stateVersion = "25.11";
          standaloneHM = false;
          secrets = inputs.nix-secrets;
          features = {
            opt-in = [ "wifi/NaCo" ];
          };
        };
      };

      # Home Manager configurations
      homeConfigurations = lib.mkHomes {
        "rona@nanoserver" = {
          username = "rona";
          hostname = "nanoserver";
          system = "x86_64-linux";
          stateVersion = "25.11";
          #secrets = inputs.nix-secrets;
          features = {
            # opt-in = [ "desktop" "development" ];
          };
        };
      };
    };
}
