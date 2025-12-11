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

1. [2025-12-11] Git history fully sanitized - squashed to single commit
2. [2025-12-11] Fixed remote URL (was nix-secrets.git → now nix-config.git)
3. [2025-12-11] Removed SSH private key from history via squash
4. [2025-12-11] Force-pushed clean history to GitHub
5. [2025-12-10] Renamed nixos-config → nix-config
6. [2025-12-10] Renamed nixos-secrets → nix-secrets
7. [2025-12-10] Renamed nixos-keys → nix-keys
8. [2025-12-10] Using nix-lib for shared builders

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
