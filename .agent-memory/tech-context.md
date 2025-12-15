---
title: Tech Context - nix-config
type: note
permalink: nix-config-tech-context
tags:
  - tech
  - stack
---

# Tech Context - nix-config

## Technology Stack

### Core

- **NixOS**: 25.11 (stable)
- **Nix**: Determinate Nix 3.14.0 (Nix 2.32.4) - flakes enabled by default
- **Home Manager**: release-25.11

### Flake Inputs

| Input | Purpose |
|-------|---------|
| nixpkgs | NixOS 25.11 packages |
| nixpkgs-unstable | Bleeding edge packages |
| home-manager | User environment management |
| sops-nix | Secret management |
| impermanence | Ephemeral root support |
| disko | Declarative partitioning |
| comin | Continuous deployment |
| devshell | Development environments |
| git-hooks | Pre-commit hooks |
| nix-secrets | Private secrets (flake=false) |
| nix-lib | Shared library for builders |

## Observations

- [constraint] Secrets repo accessed via SSH (git+ssh)
- [constraint] nix-keys is local-only, never pushed
- [setup] direnv for automatic shell activation
- [setup] Pre-commit hooks enforce nixfmt-rfc-style

## Development Setup

```bash
# Enter development shell
nix develop

# Or use direnv
direnv allow
```

## Build Commands

```bash
# Check flake
nix flake check

# Build ISO
nix build .#nixosConfigurations.iso.config.system.build.isoImage

# Build host
nixos-rebuild build --flake .#nanoserver
```

## Relations

- uses [[NixOS Flakes]]
- uses [[Home Manager]]
- uses [[sops-nix]]
