---
title: Active Context - nix-config
type: note
permalink: nix-config-active-context
tags:
  - active
  - context
---

# Active Context - nix-config

## Current Focus
Layered devshell architecture complete across all repos.

## Recent Events
1. [2025-12-30] Applied layered devshell to nix-repos sub-repos (nix-config, nix-keys, nix-secrets, nix-lib)
2. [2025-12-30] Removed duplicate packages from local shell.nix files (git, jq, nixfmt, etc.)
3. [2025-12-30] Central devshell provides: git, fd, rg, bat, eza, jq, nixfmt, deadnix, statix, nix-tree, nixd
4. [2025-12-17] Added home-manager config for rona@aio (Arch Linux host)
5. [2025-12-17] Switched from Determinate Nix to standard Nix 2.33.0
6. [2025-12-17] Updated nix-secrets to use deploy key URL (github-nix-secrets)
7. [2025-12-17] Refactored GPG/Yubikey boot-time key unlock architecture
8. [2025-12-17] Split injection archive creation to nix-keys, Ventoy disk to nix-repos
9. [2025-12-15] Migrated CachyOS host from standard Nix to Determinate Nix 3.14.0
10. [2025-12-13] Simplified ISO to Ventoy-only boot (removed QEMU SquashFS support)

## Active Decisions

- Using NixOS 25.11 stable branch
- Feature opt-in/opt-out pattern for host customization
- Pre-commit hooks via git-hooks.nix
- Shared library in nix-lib (accessed via lib.nix-lib.*)

## Next Steps
- Push layered devshell changes to all sub-repos
- Test layered .envrc in nix-config, nix-keys, nix-secrets, nix-lib
- Document central devshell packages in nix-config README

## Relations

- part_of [[nix-config]]
- uses_lib_from [[nix-lib]]
