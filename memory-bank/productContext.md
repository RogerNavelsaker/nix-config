---
title: Product Context - nix-config
type: note
permalink: nix-config-product-context
tags:
  - context
  - nixos
---

# Product Context - nix-config

## Why This Project Exists

- [problem] Traditional Linux configurations are fragile and hard to reproduce
- [problem] System drift between machines causes maintenance burden
- [problem] Secret management often insecure or manual

## Observations

- [solution] NixOS provides declarative, reproducible system configuration
- [solution] Flakes enable pinned dependencies and hermetic builds
- [solution] SOPS integration provides secure, git-friendly secrets
- [solution] Feature modules enable flexible host customization

## User Experience Goals

- [ux] Single command to build/deploy any host configuration
- [ux] Development shell with all necessary tools
- [ux] Pre-commit hooks catch issues before commit
- [ux] ISO enables fresh machine bootstrapping

## How It Works

1. Define host in `flake.nix` with features and settings
2. Configure host-specific options in `hosts/<hostname>/`
3. Secrets stored encrypted in nix-secrets repo
4. Build with `nixos-rebuild` or create ISO
5. Deploy via comin or manual rebuild

## Relations

- implements [[Infrastructure as Code]]
- follows [[NixOS Best Practices]]
