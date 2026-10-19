# nix-config

NixOS system configuration flake for personal infrastructure.

## Repository Structure

```
nix-config/
├── flake.nix          # Main flake with inputs and outputs
├── flake.lock         # Pinned dependency versions
├── devenv.nix         # Devenv development environment
├── devenv.yaml        # Devenv input configuration
├── devshells/         # Per-repo devenv shell definitions
├── lib/               # Extended nix library functions
├── hosts/             # Host-specific configurations
│   ├── features/      # Opt-in/opt-out feature modules
│   ├── iso/           # ISO image configuration
│   ├── nanoserver-01/ # Server configuration
│   ├── miniserver-01/ # HP EliteDesk node
│   ├── miniserver-02/ # HP EliteDesk node
│   ├── miniserver-03/ # HP EliteDesk node
│   └── miniserver-common/ # Shared miniserver modules
├── users/             # User (Home Manager) configurations
├── modules/           # Reusable NixOS and HM modules
│   ├── nixos/         # NixOS modules
│   └── home-manager/  # Home Manager modules
├── overlays/          # Nixpkgs overlays
├── pkgs/              # Custom packages
├── scripts/           # Helper scripts
├── docs/              # Documentation
├── checks.nix         # Flake checks
└── shell.nix          # Development shell
```

## Key Inputs

- **nixpkgs**: NixOS unstable (pinned via lock)
- **home-manager**: release-25.11
- **sops-nix**: Secret management
- **impermanence**: Ephemeral root support (home-manager-v1)
- **disko**: Declarative disk partitioning
- **comin**: Continuous machine integration
- **devenv**: Development environment
- **git-hooks**: Pre-commit hooks
- **nix-secrets**: SOPS-encrypted secrets repository
- **llm-agents**: LLM agent integration
- **plasma-manager**: KDE Plasma configuration
- **autofirma-nix**: Digital signature tool
- **nixgl**: GPU wrapper for non-NixOS
- **nix-vscode-extensions**: VS Code extensions

## Hosts

| Host | Purpose | Features |
|------|---------|----------|
| `nanoserver-01` | Main server (appliance) | A/B store, systemd-sysupdate, tmpfs root |
| `miniserver-01` | HP EliteDesk rescue node | Appliance profile, Disko layout |
| `miniserver-02` | HP EliteDesk rescue node | Appliance profile, Disko layout |
| `miniserver-03` | HP EliteDesk rescue node | Appliance profile, Disko layout |
| `iso` | Rescue/installer ISO | WiFi, secrets, Tailscale |

### Appliance features (opt-in)

- `appliance` — Image-based appliance profile (systemd-sysupdate, tmpfs root, immutable users)
- `appliance-disko` — Disko layout for dual-USB A/B store with NVMe /persist
- `passwordless-sudo` — Passwordless sudo for wheel group
- `wifi/NaCo` — iwd Wi-Fi profiles (NaCo network)

## Development

```bash
# Workspace-wide shared tools are activated by direnv from ~/Repositories
nix develop              # Project-specific NixOS and Home Manager commands
```

## Build Commands

```bash
# Build ISO
nix build .#nixosConfigurations.iso.config.system.build.isoImage

# Build nanoserver-01
nix build .#nixosConfigurations.nanoserver-01.config.system.build.toplevel

# Build miniserver-01
nix build .#nixosConfigurations.miniserver-01.config.system.build.toplevel

# Check flake
nix flake check
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
