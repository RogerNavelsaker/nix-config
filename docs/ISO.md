# NixOS ISO Configuration

Minimal NixOS installation ISO with Ventoy boot and SSH key injection.

## Features

- **Pure Nix build** - No `--impure` flag required
- **UEFI bootable** - Works with modern UEFI systems
- **Ventoy boot** - Encrypted nix-keys material is unlocked at boot with the YubiKey
- **Ephemeral rescue access** - The SOPS decryption SSH key is held under `/run` and removed after secret activation; Tailscale state is memory-only
- **Key-only SSH** - Root and password SSH are disabled; the operator public key is loaded from Ventoy media

## Quick Start

```bash
# Enter development shell
nix develop

# Build ISO + Ventoy disk with the operator public key (YubiKey required at boot)
iso build -U rona

# Run in QEMU
iso run

# SSH into guest
iso ssh

# Stop QEMU
iso stop
```

## Commands

| Command | Description |
|---------|-------------|
| `iso build` | Build ISO + Ventoy disk with key injection |
| `iso rebuild` | Force rebuild (ignore cache) |
| `iso run` | Boot Ventoy disk in QEMU |
| `iso stop` | Stop QEMU |
| `iso restart` | Restart QEMU |
| `iso status` | Check if QEMU is running |
| `iso ssh` | SSH into running guest |
| `iso log` | View serial output |
| `iso path` | Print ISO path in nix store |
| `iso copy` | Copy ISO out of nix store |

## Key Injection

Keys are managed through the **nix-keys** repository and injected via Ventoy's injection feature.

### Ventoy Disk Structure

```
Ventoy partition:
├── nixos.iso           # NixOS installation ISO
├── keys.tar.gz         # Key injection archive
└── ventoy/
    └── ventoy.json     # Injection configuration
```

### Injected Key Structure

The Ventoy archive contains encrypted private material and explicitly selected public keys:

```
private/
├── .gpg-id
└── hosts/iso/*.gpg           # Encrypted host key material
public/
├── hosts/iso/*.pub
└── users/rona/id_ed25519.pub # Public operator key, when selected
```

At boot, only the host key needed for SOPS decryption is decrypted into `/run/rescue`. The operator public key is copied to `/home/rona/.ssh/authorized_keys`; deploy and user private keys are not installed on the rescue system.

### Build Options

```bash
# Host key only; remote SSH stays unavailable without an operator key
iso build

# Include the operator key needed for remote SSH
iso build -U rona

# Use different host's keys
iso build -H nanoserver

# Custom nix-keys location
iso build --keys-repo /path/to/nix-keys
```

## Boot Process

1. QEMU boots from Ventoy disk
2. Ventoy bootloader loads `nixos.iso`
3. Ventoy injects `keys.tar.gz` contents into initramfs
4. NixOS initramfs (stage 1) runs `postMountCommands`
5. The host SSH key is decrypted only into `/run/rescue` for SOPS age decryption
6. sops-nix activates secrets and removes the temporary decryption key
7. SSH starts only after SOPS activation; inbound access is limited to the operator public key from Ventoy
8. Tailscale starts after networking and SOPS, uses a hashed runtime hostname and `tag:rescue`, then removes its auth-key file

### Why Stage 1?

- Only the temporary SOPS decryption key is made available before stage 2
- Missing YubiKey/decryption prevents SOPS activation and therefore prevents SSH/Tailscale startup
- No deploy or user private SSH keys are copied into the rescue root
- QEMU/hardware boot behavior still needs verification; this documentation describes the intended current flow

## Configuration Files

| File | Purpose |
|------|---------|
| `default.nix` | Main ISO configuration |
| `load-keys.nix` | Initrd YubiKey unlock and ephemeral key handling |
| `ssh.nix` | SSH service configuration |
| `boot.nix` | Boot configuration |
| `network.nix` | Network configuration |
| `users.nix` | User accounts |
| `programs.nix` | Additional programs |
| `tailscale.nix` | Tailscale VPN setup |

## Rescue access safety

- Missing Ventoy key material or failed YubiKey decryption must leave SOPS activation unsuccessful; SSH and Tailscale are ordered after that activation.
- SOPS age decryption uses `/run/rescue/ssh_host_ed25519_key`; the key is removed after secret activation.
- SSH allows only the operator public key copied from the Ventoy `public/users/` tree. Root login, password login, and keyboard-interactive login are disabled.
- Tailscale requests `tag:rescue`, uses memory-backed state and a per-boot runtime hostname, and removes the auth-key file after a successful join. The key must be separately provisioned with permission to use that tag; single-use/expiry policy is still to be verified.
- Validate these guarantees in QEMU before using the ISO on a physical machine.

## Troubleshooting

### No Keys Found

Check serial log during boot:
```bash
iso log
```

Expected output with keys:
```
=== Stage 1: Loading SSH keys (Ventoy) ===
Found Ventoy-injected keys, copying to target...
=== Stage 1: Key loading complete ===
```

Without keys:
```
=== Stage 1: Loading SSH keys (Ventoy) ===
No Ventoy-injected keys found (expected: /etc/ssh/ssh_host_ed25519_key)
=== Stage 1: Key loading complete ===
```

### Verify Ventoy Disk

```bash
# Check disk was created
ls -la /tmp/*-ventoy.img

# Rebuild if needed
iso rebuild
```

### SSH Connection Issues

```bash
# Check QEMU is running
iso status

# View logs for errors
iso log

# Try with verbose SSH
ssh -v -p 2222 rona@localhost
```
