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
Home-manager standalone setup for non-NixOS hosts complete.


## Recent Events
1. [2025-12-17] Added home-manager config for rona@aio (Arch Linux host)
2. [2025-12-17] Switched from Determinate Nix to standard Nix 2.33.0
3. [2025-12-17] Updated nix-secrets to use deploy key URL (github-nix-secrets)
4. [2025-12-17] Removed determinate input from flake
5. [2025-12-17] Refactored GPG/Yubikey boot-time key unlock architecture
6. [2025-12-17] Split injection archive creation to nix-keys, Ventoy disk to nix-repos
7. [2025-12-17] Updated load-keys.nix: mktemp for GNUPGHOME, hostname from config
8. [2025-12-15] Migrated CachyOS host from standard Nix to Determinate Nix 3.14.0
9. [2025-12-13] Simplified ISO to Ventoy-only boot (removed QEMU SquashFS support)
10. [2025-12-12] Added `iso ventoy` action for QEMU testing with Ventoy + key injection


## Active Decisions

- Using NixOS 25.11 stable branch
- Feature opt-in/opt-out pattern for host customization
- Pre-commit hooks via git-hooks.nix
- Shared library in nix-lib (accessed via lib.nix-lib.*)

## Next Steps

- Verify flake builds correctly with renamed repos
- Update any remaining nixos-config references
- Test nix-lib integration

## Relations

- part_of [[nix-config]]
- uses_lib_from [[nix-lib]]
