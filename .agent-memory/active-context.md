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

Repository renaming and nix-lib integration.

## Recent Events

1. [2025-12-15] Migrated CachyOS host from standard Nix to Determinate Nix 3.14.0
2. [2025-12-13] Simplified ISO to Ventoy-only boot (removed QEMU SquashFS support)
3. [2025-12-12] Added `iso ventoy` action for QEMU testing with Ventoy + key injection
4. [2025-12-12] Renamed memory-bank/ to .agent-memory/ with kebab-case files
5. [2025-12-12] Made nix-config repo public on GitHub
6. [2025-12-12] Extracted 4 patterns to global ~/.agent-memory/patterns/
7. [2025-12-11] Git history fully sanitized - squashed to single commit
8. [2025-12-11] Fixed remote URL (was nix-secrets.git → now nix-config.git)


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
