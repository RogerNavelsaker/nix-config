---
title: System Patterns - nix-config
type: note
permalink: nix-config-system-patterns
tags:
  - patterns
  - architecture
---

# System Patterns - nix-config

## Architecture Overview

```
flake.nix (entry point)
    │
    ├── nix-lib (external flake input for builders)
    │
    ├── hosts/<hostname>/
    │   └── default.nix (host config)
    │
    ├── hosts/features/
    │   └── <feature>/default.nix (opt-in modules)
    │
    ├── modules/
    │   ├── nixos/ (NixOS modules)
    │   └── home-manager/ (HM modules)
    │
    └── overlays/ (nixpkgs modifications)
```

## Observations

- [pattern] Feature opt-in/opt-out via `features.opt-in` and `features.opt-out` lists
- [pattern] Shared lib via nix-lib flake (mkSystems, mkHomes, forEachSystem)
- [pattern] Secrets path follows host structure: `hosts/<hostname>/secrets.yaml`
- [pattern] Home configurations can be standalone or integrated with NixOS

## Key Patterns

### Host Definition Pattern

```nix
nixosConfigurations = lib.mkSystems {
  hostname = {
    hostname = "name";
    users = [ "user" ];
    system = "x86_64-linux";
    stateVersion = "25.11";
    secrets = inputs.nix-secrets;
    features = {
      opt-in = [ "feature1" ];
      opt-out = [ "feature2" ];
    };
  };
};
```

### Feature Module Pattern

Features in `hosts/features/` are loaded based on opt-in list.
Each feature is a standalone NixOS module.

### Development Shell Pattern

`shell.nix` provides devshell with:
- Git hooks via git-hooks.nix
- Nix formatting tools
- SOPS utilities

## Relations

- defines [[Host Configuration Pattern]]
- defines [[Feature Module Pattern]]
- extracted_to [[patterns/git-history-sanitization-pattern]]
- extracted_to [[patterns/nix-os-host-definition-pattern]]
- extracted_to [[patterns/nix-os-feature-module-pattern]]
- extracted_to [[patterns/nix-development-shell-pattern]]


### GPG/Yubikey Boot-time Key Unlock Pattern

Cross-repo architecture for secure key injection:

```
nix-config (ISO build)
    │
    └── hosts/iso/load-keys.nix
        ├── postDeviceCommands: Mount Ventoy, start pcscd/gpg-agent
        └── postMountCommands: GPG decrypt from pass store → /etc/ssh/

nix-keys (injection archive)
    │
    └── scripts/create.nix
        ├── archive: Decrypted keys (requires Yubikey)
        └── injection: Encrypted pass store for Ventoy

nix-repos (orchestration + QEMU)
    │
    ├── scripts/ventoy.nix: Create Ventoy disk (ISO + injection)
    └── scripts/iso.nix: QEMU testing (build, run, ssh, log)
```

Key principles:
- Keys encrypted on disk, decrypted at boot with Yubikey
- Injection archive structure: `{private,public}/{hosts,users}/{hostname,username,common}/`
- No Yubikey needed to create Ventoy disk (only at boot)
- Hostname from `config.hostSpec.hostname`, not hardcoded
- GNUPGHOME via `mktemp -d` for clean environment

