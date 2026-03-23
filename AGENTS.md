# nix-config

NixOS system configuration flake for personal infrastructure.

## Repository Structure

```
nix-config/
├── flake.nix          # Main flake with inputs and outputs
├── flake.lock         # Pinned dependency versions
├── lib/               # Extended nix library functions
├── hosts/             # Host-specific configurations
│   ├── features/      # Opt-in/opt-out feature modules
│   ├── iso/           # ISO image configuration
│   └── nanoserver/    # Server configuration
├── users/             # User (Home Manager) configurations
├── modules/           # Reusable NixOS and HM modules
│   ├── nixos/         # NixOS modules
│   └── home-manager/  # Home Manager modules
├── overlays/          # Nixpkgs overlays
├── pkgs/              # Custom packages
├── scripts/           # Helper scripts
├── docs/              # Documentation
├── checks.nix         # Flake checks
├── shell.nix          # Development shell
└── githooks.nix       # Git hooks configuration
```

## Key Inputs

- **nixpkgs**: NixOS 25.11 (stable)
- **home-manager**: release-25.11
- **sops-nix**: Secret management
- **impermanence**: Ephemeral root support
- **disko**: Declarative disk partitioning
- **comin**: Continuous machine integration
- **devshell**: Development environment
- **git-hooks**: Pre-commit hooks
- **nixos-secrets**: SOPS-encrypted secrets repository

## Hosts

| Host | Purpose | Features |
|------|---------|----------|
| `nanoserver` | Main server | Base configuration |
| `iso` | Installation ISO | WiFi, secrets |

## Development

```bash
direnv allow             # Preferred: Flox + direnv
nix develop              # Fallback: flake devshell
```

## Build Commands

```bash
# Build ISO
nix build .#nixosConfigurations.iso.config.system.build.isoImage

# Build system
nixos-rebuild build --flake .#nanoserver

# Check flake
nix flake check --option eval-cache false
```

## Repository Policy

The repository may be updated directly when appropriate.

## Related Repositories

- `nix-lib`: Shared library for NixOS/Home Manager builders
- `nix-secrets`: SOPS-encrypted secrets
- `nix-keys`: Yubikey-backed encrypted key material

## Conventions

- Nix code follows nixfmt-rfc-style
- Pre-commit hooks enforce formatting
- Features use opt-in/opt-out pattern
- Secrets managed via sops-nix

## Recommended MCP Servers

This is a Nix repository. For AI assistants with MCP support:

**Project-specific** (configure in `.mcp.json`):
- `nixos` - NixOS/Home Manager/nix-darwin option lookups via `uvx mcp-nixos`

**Global** (user's global config):
- `basic-memory` - Knowledge management
- `modern-cli` - Modern CLI tools, fetch, github
- `sequentialthinking` - Complex reasoning

`.mcp.json` is gitignored - each user configures their own.
