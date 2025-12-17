---
title: Progress - nix-config
type: note
permalink: nix-config-progress
tags:
  - progress
  - status
---

# Progress - nix-config

## Current Status
GPG/Yubikey boot-time key unlock refactored. ISO uses load-keys.nix with mktemp for GNUPGHOME and hostname from config.hostSpec.hostname. Injection archive created by nix-keys, Ventoy disk assembled by nix-repos, QEMU testing in nix-repos.


## What Works
- [x] Flake with all inputs configured
- [x] Host definitions (nanoserver, iso)
- [x] Home Manager integration
- [x] Development shell with git hooks
- [x] Pre-commit formatting checks
- [x] Secrets input from nix-secrets
- [x] Shared library from nix-lib
- [x] Repository renamed (nixos-* → nix-*)
- [x] Repository made public
- [x] Memory structure (.agent-memory/ with kebab-case)
- [x] Patterns extracted to global memory
- [x] GPG/Yubikey boot-time key unlock (load-keys.nix)
- [x] Cross-repo architecture: nix-config (ISO) + nix-keys (injection) + nix-repos (Ventoy/QEMU)


## What's Left

- [ ] Complete host-specific configurations
- [ ] Add more feature modules
- [ ] Document all modules
- [ ] Set up comin deployment
- [ ] Verify builds after rename

## Known Issues

- Secrets currently commented out for nanoserver (see flake.nix:96,123)

## Blockers

None currently.

## Relations

- tracks [[nix-config]]
