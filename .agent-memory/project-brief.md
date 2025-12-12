---
title: Project Brief - nix-config
type: note
permalink: nix-config-project-brief
tags:
  - project
  - nixos
  - infrastructure
---

# Project Brief - nix-config

## Overview

NixOS system configuration flake managing personal infrastructure with declarative, reproducible builds.

## Observations

- [scope] Manages NixOS and Home Manager configurations for multiple hosts
- [architecture] Flake-based with modular structure (hosts, modules, overlays, pkgs)
- [stack] NixOS 25.11, Home Manager, sops-nix, impermanence, disko
- [deployment] Uses comin for continuous machine integration
- [security] Secrets via sops-nix, SSH keys from nix-keys
- [library] Uses nix-lib for shared builders and helpers

## Core Requirements

1. Declarative system configuration
2. Reproducible builds across hosts
3. Secret management with age encryption
4. Feature opt-in/opt-out pattern
5. Pre-commit hooks for code quality

## Current Hosts

- **nanoserver**: Main server configuration
- **iso**: Installation ISO with WiFi and secrets

## Relations

- imports [[nix-secrets]] (git+ssh flake input)
- depends_on [[nix-keys]] (local key generation)
- uses_lib_from [[nix-lib]] (shared builders)
- uses [[sops-nix]] for secrets
- uses [[home-manager]] for user config
