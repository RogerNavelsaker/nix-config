# NixOS ISO Configuration

This is a minimal NixOS installation ISO with SSH support and persistent SSH host keys.

## Features

- **Pure Nix build** - No `--impure` flag required
- **UEFI bootable** - Works with modern UEFI systems
- **USB bootable** - Compatible with Ventoy and direct USB boot
- **Persistent SSH keys** - Load SSH host keys from external disk

## Building

```bash
# Build the ISO
build-iso

# ISO will be available at result/iso/iso.iso
```

## SSH Host Keys and Deploy Keys

The ISO supports loading SSH host keys and deploy keys from external sources, enabling persistent SSH access and automated deployments.

### Two Loading Methods

1. **QEMU**: Keys stored in separate disk image (`.img` file)
2. **Ventoy**: Keys injected via Ventoy's injection feature (`.tar.gz` archive)

Both methods are managed through the **nixos-keys** repository.

### Quick Start

```bash
# Navigate to nixos-keys repository
cd ../nixos-keys

# Enter development environment
nix develop

# For QEMU testing (per-host, optional users)
create disk <hostname> [output.img] [users...]

# For Ventoy USB boot (per-host, optional users)
create archive <hostname> [output.tar.gz] [users...]

# Examples:
#   create disk iso                    # Host keys only
#   create disk iso iso-keys.img rona  # Host + rona user
#   create disk iso iso-keys.img '*'   # Host + all users

# View all commands
menu
```

### QEMU Testing Workflow

```bash
# In nixos-keys repo
cd ../nixos-keys
nix develop

# Create disk with specific users (or omit for host-only)
create disk iso iso-keys.img rona

# In nixos-config repo
cd ../nixos-config
build-iso

# Run with keys disk attached (auto-detects KVM)
run-iso ../nixos-keys/iso-keys.img
# SSH available at localhost:2222

# Run without keys disk (host keys auto-generated)
run-iso
```

### Ventoy USB Boot Workflow

```bash
# In nixos-keys repo
cd ../nixos-keys
nix develop

# Create archive with specific users (or omit for host-only)
create archive iso ssh-keys.tar.gz rona

# In nixos-config repo
cd ../nixos-config
build-iso

# Copy to Ventoy USB
cp result/iso/*.iso /path/to/ventoy/
cp ../nixos-keys/ssh-keys.tar.gz /path/to/ventoy/

# Create ventoy/ventoy.json (see nixos-keys README)
```

### Key Management

All key generation and management is handled by the **nixos-keys** repository:
- SSH host keys (ed25519 only)
- Deploy keys (ed25519 only) for private repo access
- User SSH keys (ed25519 only)
- QEMU disk images
- Ventoy injection archives

See: `../nixos-keys/README.md` for complete documentation.

## Testing Commands

### run-iso

Boot the ISO in QEMU with automatic KVM detection and optional SSH keys disk:

```bash
# Boot without SSH keys (host keys auto-generated)
run-iso

# Boot with SSH keys disk (enables SSH port forwarding)
run-iso /path/to/keys-disk.img
# SSH available at: ssh -p 2222 root@localhost
```

**Features:**
- Automatically detects and enables KVM acceleration if available
- Falls back gracefully to non-KVM mode if not supported
- Optional SSH keys disk support (disk must have `nixos-keys` label)
- SSH port forwarding to localhost:2222 when keys disk is provided

## Boot Process

Both Ventoy and QEMU use a **unified flat structure** for key loading:

```
etc/ssh/ssh_host_*           → /etc/ssh/
root/.ssh/deploy_key_*       → /root/.ssh/
home/<username>/.ssh/id_*    → /home/<username>/.ssh/
```

### Unified Stage 1 (Initramfs) Loading

**Both Ventoy and QEMU load keys during initramfs (stage 1)** - before the system starts and before sops-nix runs. This ensures SSH host keys are available for secret decryption.

**Ventoy Method:**
1. Ventoy injects files directly into initramfs during boot (flat structure)
2. `boot.initrd.postMountCommands` detects injected keys in `/etc/ssh/`, `/root/.ssh/`, `/home/`
3. Copies keys to target filesystem using `load-keys` utility

**QEMU Method:**
1. ISO boots in initramfs (stage 1)
2. `boot.initrd.postMountCommands` scans for SquashFS disks (`/dev/vd[b-z]`, `/dev/sd[b-z]`, `/dev/hd[b-z]`)
3. Mounts first SquashFS disk found to `/mnt-keys`
4. Copies keys to target filesystem using `load-keys` utility
5. Unmounts SquashFS disk

**Why Stage 1?**
- ✅ Keys available before system services start
- ✅ Works with sops-nix (needs host keys for decryption)
- ✅ SSH service starts with proper keys immediately
- ✅ No timing issues or race conditions

## Requirements

### Unified File Structure

**Both Ventoy and QEMU use identical flat structure:**

```
etc/
  ssh/
    ssh_host_ed25519_key
    ssh_host_ed25519_key.pub
root/
  .ssh/
    deploy_key_ed25519
    deploy_key_ed25519.pub
home/
  <username>/
    .ssh/
      id_ed25519
      id_ed25519.pub
```

This unified structure means:
- ✅ Same layout for both Ventoy and QEMU
- ✅ Single unified key loading logic
- ✅ Easier to understand and maintain
- ✅ Consistent behavior across boot methods

### QEMU Disk Format

The ISO automatically detects and mounts SquashFS disks for SSH keys in QEMU.

**How it works:**
- Scans block devices (`/dev/vd[b-z]`, `/dev/sd[b-z]`, `/dev/hd[b-z]`)
- Mounts the first SquashFS filesystem found (read-only)
- No filesystem labels or UUIDs required
- Uses unified flat structure (same as Ventoy)

The nixos-keys repository's `create disk` command creates compressed SquashFS images with the flat structure.

**Benefits:**
- No manual labeling required
- Compressed format (smaller disk images)
- Read-only by design (safer)
- Works with any SquashFS disk attached to QEMU
- Identical to Ventoy archive structure

### Ventoy Requirements

Ventoy injection uses the same flat structure as QEMU. Keys are injected directly into the initramfs during boot via Ventoy's injection feature.

The nixos-keys repository's `create archive` command creates tar.gz archives with the flat structure.

## Troubleshooting

### Verify Disk Format

If SSH keys aren't loading in QEMU, verify the disk is SquashFS:

```bash
# Check disk filesystem type
blkid /path/to/disk.img

# Expected output:
# /path/to/disk.img: BLOCK_SIZE="131072" TYPE="squashfs"

# Or use file command
file /path/to/disk.img

# Expected output:
# disk.img: Squashfs filesystem, ...
```

### QEMU Boot Messages

When booting with a SquashFS keys disk, you should see:
```
Scanning for nixos-keys disk...
Found SquashFS device: /dev/vdb
Attempting to load keys from /dev/vdb...
Loading SSH host keys for iso...
✓ Keys loaded from nixos-keys disk
```

Without a SquashFS disk:
```
Scanning for nixos-keys disk...
No SquashFS keys disk found (checked /dev/vd[b-z], /dev/sd[b-z], /dev/hd[b-z])
```

### Ventoy Boot Messages

When Ventoy successfully injects keys, you should see:
```
Found Ventoy-injected SSH keys, copying to target...
```

## Configuration Files

- `default.nix` - Main ISO configuration
- `load-keys.nix` - **Unified SSH keys loading** for both Ventoy and QEMU
  - Includes `load-keys` utility in initrd and system
  - Includes `blkid` utility in initrd for SquashFS detection
  - Handles `boot.initrd.postMountCommands` for stage 1 loading
  - Uses `load-keys-init` package for init script
- `ssh.nix` - SSH service configuration only
- `boot.nix` - Boot configuration (kernel params, bootloader)
- `network.nix` - Network configuration
- `users.nix` - User accounts
- `programs.nix` - Additional programs
- `tailscale.nix` - Tailscale VPN setup

## load-keys Utility

The ISO includes a `load-keys` utility (defined in `pkgs/load-keys.nix`) that handles SSH key loading for both Ventoy and QEMU scenarios. This utility is available in:
- **Initramfs**: For Ventoy key injection during early boot
- **Running system**: For QEMU disk mounting and manual key loading

**Usage:**
```bash
load-keys <source_dir> [target_root]

# Examples:
load-keys /run/nixos-keys /              # QEMU post-boot
load-keys / $targetRoot                  # Ventoy initramfs
```

The utility automatically detects and loads:
- SSH host keys from `<source>/etc/ssh/`
- Deploy keys from `<source>/root/.ssh/`
- User keys from `<source>/home/*/.ssh/`
