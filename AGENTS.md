# nix-config

## Project

This repository is a Nix flake for personal NixOS and Home Manager configuration. It defines two NixOS systems (`nanoserver` and an installation `iso`) plus Home Manager configurations for `rona`. Inputs include nixpkgs, Home Manager, sops-nix, impermanence, disko, and related tooling. There is currently no `README.md`; the `docs/` directory contains focused guides such as `ISO.md` and `IMPERMANENCE.md`.

## Layout

- `flake.nix`, `flake.lock`: flake inputs and outputs, systems, homes, packages, checks, and formatter.
- `hosts/`: host modules; `iso/` builds the installer image and `nanoserver/` configures the server.
- `users/`: per-user Home Manager configurations and default/opt-in/opt-out features.
- `modules/`: reusable NixOS and Home Manager module entry points.
- `devshells/`: development shells and commands; `shell.nix` is the shell entry point.
- `overlays/`, `pkgs/`, `scripts/`: overlays, custom Nix packages, and helper scripts.
- `docs/`: operational documentation; `checks.nix` defines flake checks and `githooks.nix` defines formatting/lint hooks.

## Development

Enter the project environment with `nix develop` (or `direnv allow` where the surrounding workspace environment is available). The dev shell provides commands including `check`, `fmt`, `lint-deadcode`, and `lint-patterns`.

Run the quality gate before submitting changes:

```bash
nix flake check --option eval-cache false
```

Useful targeted commands:

```bash
nix build .#nixosConfigurations.iso.config.system.build.isoImage
nixos-rebuild build --flake .#nanoserver
nix fmt -- --check
nix flake show
```

The flake checks cover NixOS and Home Manager evaluations, formatting, dead-code and pattern linting, syntax, and feature structure. Avoid committing generated files or secrets; keep changes focused and run the gate again after the final edit.
