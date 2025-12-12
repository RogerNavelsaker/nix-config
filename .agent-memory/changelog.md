---
title: Changelog - nix-config
type: note
permalink: nix-config-changelog
tags:
  - changelog
  - history
---

# Changelog - nix-config

## [Unreleased]

### Changed
- Renamed repository: nixos-config → nix-config
- Renamed related repos: nixos-secrets → nix-secrets, nixos-keys → nix-keys
- Updated all memory bank references to new names
- Using lib.nix-lib.* instead of lib.nixos-config.*

### Added
- nix-lib flake input for shared builders
- nix-lib project documentation in global memory

## [0.1.0] - 2025-12-08

### Added
- CLAUDE.md project documentation
- memory-bank directory with project context files
- Basic Memory project registration

## [Initial] - 2025-12

### Added
- Flake-based configuration structure
- Host definitions: nanoserver, iso
- Home Manager integration
- sops-nix secrets integration
- Feature opt-in/opt-out pattern
- Development shell with git hooks
- Pre-commit formatting checks
