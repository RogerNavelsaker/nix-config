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
Desktop environment opt-in features for Arch Linux (rona@aio).

## Recent Events
1. [2026-01-03] Added GTK/Qt theming module with Catppuccin Mocha theme
2. [2026-01-03] Fixed plasma-manager import: homeManagerModules → homeModules
3. [2026-01-03] Added desktop opt-in features: plasma, firefox, yubikey, autofirma, bitwarden, tailscale
4. [2026-01-03] Firefox: declarative config with PKCS#11, privacy settings, custom search engines (@np, @no, @hm)
5. [2026-01-03] Yubikey: GPG agent with SSH support, scdaemonSettings, yubioath-flutter GUI
6. [2026-01-03] Autofirma: Spanish e-signing with Firefox profile integration
7. [2026-01-03] Added nixGL feature for non-NixOS hosts with GPU driver options
8. [2026-01-03] Wrapped GL apps: alacritty, kitty, vscode, beeper, bitwarden, yubioath-flutter
9. [2026-01-03] nixgl.driver (OpenGL) + nixgl.vulkan (Vulkan) options with chained wrapper
10. [2026-01-03] Desktop file patching for absolute paths in wrapped packages
## Active Decisions

- Using NixOS 25.11 stable branch
- Feature opt-in/opt-out pattern for host customization
- Pre-commit hooks via git-hooks.nix
- Shared library in nix-lib (accessed via lib.nix-lib.*)
- nixGL wrapping for Electron/GPU apps on non-NixOS
- plasma-manager.homeModules (not homeManagerModules)
- Firefox profile path must match autofirma firefoxIntegration

## Next Steps
- Test home-manager switch on aio with all new features
- Verify autofirma Firefox integration works with YubiKey certs
- Document nixGL driver options in README

## Relations

- part_of [[nix-config]]
- uses_lib_from [[nix-lib]]

## 2026-01-03: ACE Weekly Curation Timer

Added systemd user timer for weekly ACE curation in `users/features/opt-in/claude-code/default.nix`:
- `ace-weekly-curation.service`: Oneshot service executing `~/.claude/hooks/weekly-curation.fish`
- `ace-weekly-curation.timer`: Fires every Sunday at 09:00, persistent to catch up on missed runs
- Depends on `graphical-session.target` for desktop notifications via `notify-send`
