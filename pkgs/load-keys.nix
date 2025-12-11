{ pog }:

pog.pog {
  name = "load-keys";
  version = "1.0.0";
  description = "Load SSH keys from source directory to target filesystem";

  # Positional arguments for documentation (pog expects attribute sets with 'name' field)
  arguments = [
    { name = "source_dir"; }
    { name = "target_root"; }
  ];

  script = _: ''
    # Unified SSH key loading logic for NixOS ISO
    # Works for both Ventoy injection and QEMU disk mounting
    #
    # Usage (initramfs/Ventoy): load-keys <source_dir> <target_root>
    # Usage (post-boot/QEMU):   load-keys <source_dir> /
    #
    # Copies keys from flat structure:
    #   <source>/etc/ssh/* → <target>/etc/ssh/
    #   <source>/root/.ssh/* → <target>/root/.ssh/
    #   <source>/home/*/.ssh/* → <target>/home/*/.ssh/

    SOURCE_DIR="$1"
    TARGET_ROOT="''${2:-/}"
    LOADED=false

    if [ -z "$SOURCE_DIR" ]; then
      die "Usage: load-keys <source_dir> [target_root]" 1
    fi

    # Load SSH host keys
    if [ -d "$SOURCE_DIR/etc/ssh" ] && ls "$SOURCE_DIR/etc/ssh"/ssh_host_* >/dev/null 2>&1; then
      green "Loading SSH host keys..."
      mkdir -p "$TARGET_ROOT/etc/ssh"
      cp -a "$SOURCE_DIR/etc/ssh"/ssh_host_* "$TARGET_ROOT/etc/ssh/" 2>/dev/null || true
      chmod 600 "$TARGET_ROOT/etc/ssh"/ssh_host_*_key 2>/dev/null || true
      chmod 644 "$TARGET_ROOT/etc/ssh"/ssh_host_*_key.pub 2>/dev/null || true
      LOADED=true
    fi

    # Load deploy keys
    if [ -d "$SOURCE_DIR/root/.ssh" ] && ls "$SOURCE_DIR/root/.ssh"/deploy_key_* >/dev/null 2>&1; then
      green "Loading deploy keys..."
      mkdir -p "$TARGET_ROOT/root/.ssh"
      cp -a "$SOURCE_DIR/root/.ssh"/deploy_key_* "$TARGET_ROOT/root/.ssh/" 2>/dev/null || true
      chmod 600 "$TARGET_ROOT/root/.ssh"/deploy_key_* 2>/dev/null || true
      chown root:root "$TARGET_ROOT/root/.ssh"/deploy_key_* 2>/dev/null || true
      LOADED=true
    fi

    # Load user keys
    if [ -d "$SOURCE_DIR/home" ]; then
      for user_dir in "$SOURCE_DIR/home"/*; do
        if [ -d "$user_dir/.ssh" ]; then
          username=$(basename "$user_dir")
          # Check if user exists (skip in initramfs where 'id' may not work)
          if [ "$TARGET_ROOT" = "/" ] && ! id "$username" >/dev/null 2>&1; then
            continue
          fi
          green "Loading SSH keys for user $username..."
          mkdir -p "$TARGET_ROOT/home/$username/.ssh"
          cp -a "$user_dir/.ssh"/* "$TARGET_ROOT/home/$username/.ssh/" 2>/dev/null || true
          chmod 600 "$TARGET_ROOT/home/$username/.ssh"/id_* 2>/dev/null || true
          chmod 644 "$TARGET_ROOT/home/$username/.ssh"/*.pub 2>/dev/null || true
          # Only chown in post-boot scenario where users exist
          if [ "$TARGET_ROOT" = "/" ]; then
            chown -R "$username:users" "$TARGET_ROOT/home/$username/.ssh" 2>/dev/null || true
          fi
          LOADED=true
        fi
      done
    fi

    if $LOADED; then
      green "✓ Keys loaded successfully"
    else
      yellow "No keys found in $SOURCE_DIR"
    fi
  '';
}
