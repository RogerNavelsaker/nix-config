# flake.nix
{
  description = "System config flake";

  nixConfig = {
    extra-substituters = [
      "https://cachix.cachix.org"
      "https://nix-community.cachix.org"
      "https://numtide.cachix.org"
    ];

    extra-trusted-public-keys = [
      "cachix.cachix.org-1:eWNHQldwUO7G2VkjpnjDbWwy4KQ/HNxht7H4SSoMckM="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "numtide.cachix.org-1:2ps1kLBUWjxIneOy1Ik6cQjb41X0iXVXeHigGmycPPE="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-master.url = "github:NixOS/nixpkgs/master";
    nixpkgs-mara.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-packages = {
      url = "github:RogerNavelsaker/nixpkgs";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Headroom requires ast-grep-cli from unstable rather than the agent channel.
    headroom = {
      url = "github:RogerNavelsaker/nixpkg-headroom/cd05717263cff0bbf20cb0c259831e2827d4c4a9";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    systems.url = "github:nix-systems/default-linux";

    nix-lib = {
      url = "github:RogerNavelsaker/nix-lib/4e135f1340f0c5159cec94ad680fa301ef9acc43";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.systems.follows = "systems";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager-stable = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs-stable";
    };

    home-manager-mara = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs-mara";
    };

    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/72c92b11bb8289e6651c7fef29cc0a885fd6a255";
      inputs.nixpkgs.follows = "nixpkgs-mara";
    };

    devenv.url = "github:cachix/devenv/v2.4.0";

    sops-nix = {
      url = "github:mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    impermanence.url = "github:nix-community/impermanence/home-manager-v1";
    herdr.url = "github:herdrdev/herdr/v0.9.3";
    hardware.url = "github:NixOS/nixos-hardware";

    comin = {
      url = "github:nlewo/comin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pog = {
      url = "github:jpetrucciani/pog";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      # Don't follow nixpkgs - use their pinned version for compatibility
    };

    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    autofirma-nix = {
      url = "github:nix-community/autofirma-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixgl = {
      url = "github:nix-community/nixGL";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-vscode-extensions = {
      url = "github:nix-community/nix-vscode-extensions";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-secrets = {
      url = "github:RogerNavelsaker/nix-secrets";
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
        (import ./pkgs {
          inherit pkgs;
          inherit (nixpkgs) lib;
        })
        // {
          # Package-only example for the separate Nanoserver workload runtime prototype.
          nanoserver-workload-test = pkgs.hello;
        }
      );
      formatter = lib.forEachSystem (pkgs: pkgs.nixfmt-rfc-style);
      devShells = lib.forEachSystem (pkgs: import ./devshells { inherit inputs pkgs; });
      checks = lib.forEachSystem (
        pkgs:
        import ./checks.nix {
          inherit pkgs self;
          herdr = inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default;
          inherit (nixpkgs) lib;
        }
      );

      # NixOS configurations
      nixosConfigurations =
        let
          hostSpecs = {
            iso = {
              hostname = "iso";
              users = [ "rona" ];
              system = "x86_64-linux";
              stateVersion = "25.11";
              # Keep the rescue/installer image independent of the full Home Manager environment.
              standaloneHM = true;
              extraModules = [
                (
                  { lib, ... }:
                  {
                    rescueIso.yubikeyUnlockTimeoutSeconds = 180;
                    system.stateVersion = lib.mkForce "25.11";
                  }
                )
              ];
              secrets = inputs.nix-secrets;
              features.opt-in = [ "wifi/NaCo" ];
              userFeatures.opt-out = [
                "git"
                "direnv"
                "ssh"
              ];
            };
            ester-desktop = {
              system = "x86_64-linux";
              stateVersion = "25.11";
              users = [ "admin" ];
            };
          };
          resourceHosts = lib.mkHosts {
            resources = [
              "iso"
              "ester-desktop"
            ];
            specs = hostSpecs;
          };
        in
        resourceHosts
        // lib.mkVessels {
          defaults = {
            system = "x86_64-linux";
            stateVersion = "25.11";
            nixpkgs = inputs.nixpkgs-stable;
            home-manager = inputs.home-manager-stable;
            extraModules = [ ./hosts/features/opt-in/openbao-client/openbao-client.nix ];
          };
          specs.mara = {
            stateVersion = "26.05";
            users = [ "mara" ];
            nixpkgs = inputs.nixpkgs-mara;
            home-manager = inputs.home-manager-mara;
            features.opt-out = [ "impermanence" ];
          };
          specs.alex = {
            stateVersion = "26.05";
            users = [ "alex" ];
            nixpkgs = inputs.nixpkgs-mara;
            features.opt-out = [
              "impermanence"
              "nh"
            ];
          };
        };
      # Home Manager configurations
      homeConfigurations =
        let
          adminHosts = [
            "nanoserver-01"
            "miniserver-01"
            "miniserver-02"
            "miniserver-03"
            "ester-desktop"
          ];
          adminHomes = builtins.listToAttrs (
            map (hostname: {
              name = "admin@${hostname}";
              value = {
                username = "admin";
                inherit hostname;
                system = "x86_64-linux";
                stateVersion = "25.11";
              };
            }) adminHosts
          );
          # Managed nodes use the admin identity; the legacy Rona profile remains ungenerated.
          humanHomes = adminHomes;
        in
        lib.mkUsers humanHomes
        // lib.mkClankers {
          defaults = {
            system = "x86_64-linux";
            stateVersion = "25.11";
            nixpkgs = inputs.nixpkgs-stable;
            home-manager = inputs.home-manager-stable;
            features.opt-out = [
              "git"
              "ssh"
            ];
          };
          specs.mara = {
            stateVersion = "26.05";
            nixpkgs = inputs.nixpkgs-mara;
            home-manager = inputs.home-manager-mara;
          };
          specs.alex = {
            stateVersion = "26.05";
            nixpkgs = inputs.nixpkgs-mara;
            home-manager = inputs.home-manager-mara;
          };
        };

      /*
        # Temporarily disabled while the AIO desktop/dev closure is out of scope.
        # Arch Linux standalone Home Manager
        "rona@aio" = {
          username = "rona";
          hostname = "aio";
          system = "x86_64-linux";
          stateVersion = "25.11";
          features = {
            opt-in = [
              # Deferred until the full Roger AIO Firefox/AutoFirma integration is ready.
              # "autofirma"
              "beeper"
              "bitwarden"
              "claude-code"
              "firefox"
              "goose"
              "nixgl" # GPU wrapper for non-NixOS
              "plasma"
              "tailscale"
              "terminals"
              "theming" # GTK/Qt theme management
              "vscode"
              "yazi"
              "yubikey"
            ];
          };
        };
      */
      # Per-profile apps remain available; there is no default alias while AIO is disabled.
      apps = lib.forEachSystem (_: lib.mkHomeApps { inherit self; });
    };
}
