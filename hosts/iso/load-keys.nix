{
  lib,
  pkgs,
  ...
}:
{
  environment.systemPackages = [ pkgs.load-keys ];

  boot = {
    initrd = {
      # Enable SquashFS and virtio support in initramfs for mounting keys disk
      kernelModules = [
        "squashfs"
        "virtio_blk"
        "virtio_pci"
      ];
      availableKernelModules = [
        "squashfs"
        "virtio_blk"
        "virtio_pci"
      ];

      # Make load-keys utility and blkid available in initrd
      extraUtilsCommands = ''
        copy_bin_and_libs ${pkgs.load-keys}/bin/load-keys
        copy_bin_and_libs ${pkgs.util-linux}/bin/blkid
      '';

      # Load SSH keys during initramfs (stage 1) - BEFORE sops-nix runs
      # This works for both Ventoy injection and QEMU disk attachment
      postMountCommands = ''
        echo "=== Stage 1: Loading SSH keys ==="

        # Method 1: Check for Ventoy-injected keys (injected directly into initramfs)
        if [ -d /etc/ssh ] || [ -d /root/.ssh ] || [ -d /home ]; then
          echo "Found Ventoy-injected keys, copying to target..."
          ${pkgs.load-keys}/bin/load-keys / $targetRoot
        fi

        # Method 2: Check for QEMU SquashFS disk attachment
        echo "Scanning for SquashFS keys disk..."
        KEYS_DEV=""

        # Check all block devices (virtio, SCSI/SATA, IDE)
        for dev in /dev/vd[a-z] /dev/sd[a-z] /dev/hd[a-z]; do
          if [ -b "$dev" ]; then
            # Use blkid to check filesystem type
            FS_TYPE=$(blkid -s TYPE -o value "$dev" 2>/dev/null || echo "")
            if [ "$FS_TYPE" = "squashfs" ]; then
              echo "Found SquashFS device: $dev"
              KEYS_DEV="$dev"
              break
            fi
          fi
        done

        if [ -n "$KEYS_DEV" ]; then
          echo "Attempting to load keys from $KEYS_DEV..."
          mkdir -p /mnt-keys

          if mount -t squashfs -o ro "$KEYS_DEV" /mnt-keys 2>/dev/null; then
            echo "✓ Mounted SquashFS keys disk"
            ${pkgs.load-keys}/bin/load-keys /mnt-keys $targetRoot
            umount /mnt-keys
            rmdir /mnt-keys
          else
            echo "⚠ Warning: Found SquashFS device but failed to mount"
          fi
        else
          echo "No SquashFS keys disk found (checked /dev/vd[b-z], /dev/sd[a-z], /dev/hd[a-z])"
        fi

        echo "=== Stage 1: Key loading complete ==="
      '';
    };

    # Override installation-cd-minimal.nix defaults for postBootCommands
    # We don't need this for key loading anymore (moved to initramfs)
    postBootCommands = lib.mkForce "";
  };
}
