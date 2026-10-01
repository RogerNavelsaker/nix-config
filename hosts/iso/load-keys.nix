# hosts/iso/load-keys.nix
# GPG/Yubikey boot-time key extraction from pass store on Ventoy partition
# Keys are decrypted at boot using Yubikey, not at build time
#
# Ventoy partition structure (mirrors nix-keys repo):
#   /mnt/ventoy/
#   ├── nixos.iso
#   ├── private/           # Encrypted pass store
#   │   ├── .gpg-id
#   │   ├── .gpg-pubkey.asc
#   │   ├── hosts/<hostname>/*.gpg
#   │   └── users/<username>/*.gpg
#   └── public/            # Public keys
#       ├── hosts/<hostname>/*.pub
#       └── users/<username>/*.pub
{
  lib,
  config,
  ...
}:
let
  hostname = config.hostSpec.hostname or "iso";
  username = builtins.head config.hostSpec.users;
in
{
  boot = {
    initrd = {
      # Virtio support for QEMU testing
      kernelModules = [
        "virtio_blk"
        "virtio_pci"
      ];
      availableKernelModules = [
        "virtio_blk"
        "virtio_pci"
      ];

      # Mount Ventoy partition and start smartcard services
      postDeviceCommands = ''
        echo "=== Stage 1: GPG/Yubikey Key Extraction ==="

        # Mount Ventoy data partition (contains encrypted pass store)
        echo "Mounting Ventoy partition..."
        mkdir -p /mnt/ventoy
        if mount -t vfat /dev/disk/by-label/Ventoy /mnt/ventoy 2>/dev/null; then
          echo "Ventoy partition mounted"
        else
          echo "Warning: Ventoy partition not found, trying alternative labels..."
          mount -t vfat /dev/disk/by-label/VENTOY /mnt/ventoy 2>/dev/null || \
          mount -t vfat /dev/disk/by-label/ventoy /mnt/ventoy 2>/dev/null || \
          { echo "ERROR: Cannot mount Ventoy partition"; }
        fi

        # Check for pass store (private/ directory)
        if [ ! -d /mnt/ventoy/private ]; then
          echo "ERROR: Pass store not found on Ventoy partition"
          echo "Expected: /mnt/ventoy/private/"
          ls -la /mnt/ventoy/ 2>/dev/null || true
        fi

        # Start pcscd for smartcard communication
        echo "Starting pcscd..."
        mkdir -p /run/pcscd
        pcscd --foreground --auto-exit &
        PCSCD_PID=$!
        export PCSCD_PID
        sleep 2

        # Configure GPG for initrd environment using mktemp
        GNUPGHOME=$(mktemp -d)
        export GNUPGHOME
        chmod 700 "$GNUPGHOME"

        # Configure pinentry for console
        cat > "$GNUPGHOME/gpg-agent.conf" << 'GPGCONF'
        pinentry-program /bin/pinentry-curses
        allow-loopback-pinentry
        GPGCONF

        # Configure scdaemon to avoid pcscd conflicts
        cat > "$GNUPGHOME/scdaemon.conf" << 'SCDCONF'
        disable-ccid
        SCDCONF

        # Start gpg-agent with scdaemon
        echo "Starting gpg-agent..."
        gpg-agent --daemon --scdaemon-program /bin/scdaemon 2>/dev/null || true
        sleep 1

        # Import GPG public key for key ID resolution
        if [ -f /mnt/ventoy/private/.gpg-pubkey.asc ]; then
          echo "Importing GPG public key..."
          gpg --import /mnt/ventoy/private/.gpg-pubkey.asc 2>/dev/null || true
        fi

        echo "GPG/smartcard services started"
        echo "GNUPGHOME=$GNUPGHOME"
      '';

      # Extract keys using GPG/Yubikey after target root is mounted
      postMountCommands = ''
        echo ""
        echo "=========================================="
        echo "  INSERT YUBIKEY AND TOUCH WHEN PROMPTED"
        echo "=========================================="
        echo ""

        # Use GNUPGHOME from postDeviceCommands or create new one
        if [ -z "$GNUPGHOME" ] || [ ! -d "$GNUPGHOME" ]; then
          GNUPGHOME=$(mktemp -d)
          export GNUPGHOME
          chmod 700 "$GNUPGHOME"
        fi

        # Password store is in private/ directory (matches nix-keys repo structure)
        export PASSWORD_STORE_DIR=/mnt/ventoy/private

        # Use hostname from NixOS config
        HOST="${hostname}"
        echo "Extracting keys for host: $HOST"

        KEYS_EXTRACTED=0

        # Extract SSH host key (required for sops-nix)
        echo "Decrypting SSH host key..."
        TEMP_KEY=$(mktemp)
        if pass show "hosts/$HOST/ssh_host_ed25519_key" > "$TEMP_KEY" 2>/dev/null; then
          mkdir -p "$targetRoot/run/rescue"
          mv "$TEMP_KEY" "$targetRoot/run/rescue/ssh_host_ed25519_key"
          chmod 600 "$targetRoot/run/rescue/ssh_host_ed25519_key"
          echo "[OK] Temporary SOPS decryption key extracted to /run"
          KEYS_EXTRACTED=$((KEYS_EXTRACTED + 1))

        else
          rm -f "$TEMP_KEY"
          echo "[FAIL] Could not decrypt SSH host key"
          echo "Yubikey may not be inserted or touch was not confirmed"
        fi

        # Install only the public operator key for inbound SSH. Never copy
        # deploy private keys or user private keys into rescue media.
        AUTHORIZED_KEY="/mnt/ventoy/public/users/${username}/id_ed25519.pub"
        if [ -f "$AUTHORIZED_KEY" ]; then
          install -D -m 0600 "$AUTHORIZED_KEY" \
            "$targetRoot/home/${username}/.ssh/authorized_keys"
          echo "[OK] Operator public key installed for ${username}"
        else
          echo "[WARN] No operator public key found; remote SSH access will be unavailable"
        fi

        # Cleanup
        echo ""
        echo "Cleaning up..."
        kill "$PCSCD_PID" 2>/dev/null || true
        gpgconf --kill gpg-agent 2>/dev/null || true
        umount /mnt/ventoy 2>/dev/null || true
        rm -rf "$GNUPGHOME"

        echo ""
        echo "=========================================="
        echo "  Key extraction complete: $KEYS_EXTRACTED keys"
        echo "=========================================="
        echo ""
      '';
    };

    # Override installation-cd-minimal.nix defaults
    postBootCommands = lib.mkForce "";
  };
}
