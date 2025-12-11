{ writeShellScriptBin }:

writeShellScriptBin "load-keys-init" ''
  echo "=== Stage 1: Loading SSH keys ==="

  # Method 1: Check for Ventoy-injected keys (injected directly into initramfs)
  if [ -d /etc/ssh ] || [ -d /root/.ssh ] || [ -d /home ]; then
    echo "Found Ventoy-injected keys, copying to target..."
    load-keys / $targetRoot
  fi

  # Method 2: Check for QEMU SquashFS disk attachment
  echo "Scanning for SquashFS keys disk..."
  KEYS_DEV=""

  for dev in /dev/vd[b-z] /dev/sd[b-z] /dev/hd[b-z]; do
    if [ -b "$dev" ] && blkid -t TYPE=squashfs "$dev" >/dev/null 2>&1; then
      echo "Found SquashFS device: $dev"
      KEYS_DEV="$dev"
      break
    fi
  done

  if [ -n "$KEYS_DEV" ]; then
    echo "Attempting to load keys from $KEYS_DEV..."
    mkdir -p /mnt-keys

    if mount -t squashfs -o ro "$KEYS_DEV" /mnt-keys 2>/dev/null; then
      echo "✓ Mounted SquashFS keys disk"
      load-keys /mnt-keys $targetRoot
      umount /mnt-keys
      rmdir /mnt-keys
    else
      echo "⚠ Warning: Found SquashFS device but failed to mount"
    fi
  else
    echo "No SquashFS keys disk found (checked /dev/vd[b-z], /dev/sd[b-z], /dev/hd[b-z])"
  fi

  echo "=== Stage 1: Key loading complete ==="
''
