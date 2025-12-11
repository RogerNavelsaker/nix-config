# scripts/iso.nix
{
  pkgs,
  pog,
}:

pog.pog {
  name = "iso";
  version = "4.0.0";
  description = "Build and manage NixOS ISO in QEMU";

  arguments = [
    {
      name = "action";
      description = "action: build, rebuild, run, stop, restart, status, ssh, log, copy, path";
    }
  ];

  flags = [
    # Force rebuild (invalidate cache)
    {
      name = "force";
      short = "F";
      bool = true;
      description = "force rebuild, ignore cache";
    }
    # Keys disk for run/restart
    {
      name = "keys";
      short = "k";
      description = "path to SSH keys disk image";
      argument = "FILE";
      default = "";
    }
    # Foreground mode for run
    {
      name = "foreground";
      short = "f";
      bool = true;
      description = "run QEMU in foreground (default: background)";
    }
    # Serial log file
    {
      name = "serial-log";
      short = "";
      description = "serial output log file";
      argument = "FILE";
      default = "/tmp/qemu-serial.log";
    }
    # SSH user
    {
      name = "user";
      short = "u";
      description = "SSH username (default: rona)";
      argument = "USER";
      default = "rona";
    }
    # Output path for copy action
    {
      name = "output";
      short = "o";
      description = "output path for copy action (default: ./nixos.iso)";
      argument = "FILE";
      default = "./nixos.iso";
    }
  ];

  runtimeInputs = with pkgs; [
    qemu
    OVMF
    nix
    openssh
    coreutils
  ];

  script = helpers: ''
    ACTION="$1"
    PID_FILE="/tmp/qemu-iso.pid"
    QEMU_LOG="/tmp/qemu-iso.log"
    ISO_PATH_FILE="/tmp/qemu-iso-path"

    # Helper: check if QEMU is running
    is_running() {
      if ${helpers.file.exists "PID_FILE"}; then
        PID=$(cat "$PID_FILE")
        if kill -0 "$PID" 2>/dev/null; then
          return 0
        else
          rm -f "$PID_FILE"
          return 1
        fi
      fi
      return 1
    }

    # Helper: get PID if running
    get_pid() {
      if ${helpers.file.exists "PID_FILE"}; then
        cat "$PID_FILE"
      fi
    }

    # Helper: get ISO path from nix store (builds if needed)
    get_iso_path() {
      # Check if we have a cached path that still exists (unless --force)
      if ! ${helpers.flag "force"}; then
        if ${helpers.file.exists "ISO_PATH_FILE"}; then
          CACHED_PATH=$(cat "$ISO_PATH_FILE")
          if [ -d "$CACHED_PATH" ]; then
            echo "$CACHED_PATH"
            return 0
          fi
        fi
      fi
      # Build and cache the path
      green "Building ISO..."
      rm -f "$ISO_PATH_FILE"
      STORE_PATH=$(nix build .#nixosConfigurations.iso.config.system.build.isoImage --no-link --print-out-paths)
      echo "$STORE_PATH" > "$ISO_PATH_FILE"
      echo "$STORE_PATH"
    }

    # Helper: get the actual .iso file path
    get_iso_file() {
      STORE_PATH=$(get_iso_path)
      # Find the .iso file in the store path
      find "$STORE_PATH" -name "*.iso" -type f | head -1
    }

    # Action: build
    do_build() {
      STORE_PATH=$(get_iso_path)
      ISO_FILE=$(find "$STORE_PATH" -name "*.iso" -type f | head -1)
      green "✓ ISO built: $ISO_FILE"
    }

    # Action: path (print store path)
    do_path() {
      ISO_FILE=$(get_iso_file)
      echo "$ISO_FILE"
    }

    # Action: copy (copy ISO out of nix store)
    do_copy() {
      ISO_FILE=$(get_iso_file)
      cyan "Copying ISO to: $output"
      cp "$ISO_FILE" "$output"
      chmod 644 "$output"
      green "✓ ISO copied: $output ($(du -h "$output" | cut -f1))"
    }

    # Action: run
    do_run() {
      if is_running; then
        die "Error: QEMU is already running (PID: $(get_pid))\nRun 'iso stop' first or use 'iso restart'"
      fi

      # Get ISO path (builds if needed)
      ISO_FILE=$(get_iso_file)
      green "✓ Using ISO: $ISO_FILE"

      # Detect KVM availability
      if [ -c /dev/kvm ] && [ -r /dev/kvm ]; then
        KVM_FLAG="-enable-kvm"
        green "KVM acceleration: enabled"
      else
        KVM_FLAG=""
        yellow "KVM acceleration: not available (fallback mode)"
      fi

      # Optional SSH keys disk
      KEYS_DISK_ARG=""
      PORT_FORWARD=""
      if ${helpers.var.notEmpty "keys"}; then
        if ${helpers.file.notExists "keys"}; then
          die "Error: Keys disk not found: $keys"
        fi
        KEYS_DISK_ARG="-drive if=virtio,format=raw,file=$keys"
        PORT_FORWARD=",hostfwd=tcp::2222-:22"
        cyan "SSH keys disk: $keys"
        cyan "SSH port forwarding: localhost:2222 → guest:22"
      else
        cyan "No SSH keys disk (host keys will be auto-generated)"
      fi

      # Serial logging
      cyan "Serial logging to: $serial_log"

      # Build QEMU command
      # shellcheck disable=SC2206
      QEMU_ARGS=(
        $KVM_FLAG
        -m 4096
        -smp 2
        -drive "if=pflash,format=raw,readonly=on,file=${pkgs.OVMF.fd}/FV/OVMF.fd"
        -cdrom "$ISO_FILE"
        $KEYS_DISK_ARG
        -boot d
        -net nic "-net" "user$PORT_FORWARD"
        -serial "file:$serial_log"
      )

      # Launch QEMU
      if ${helpers.flag "foreground"}; then
        echo ""
        green "Starting QEMU in foreground mode (graphical)..."
        if ${helpers.var.notEmpty "PORT_FORWARD"}; then
          cyan "SSH: ssh -p 2222 root@localhost"
        fi
        echo ""
        qemu-system-x86_64 "''${QEMU_ARGS[@]}"
      else
        echo ""
        green "Starting QEMU in background mode (graphical window)..."

        nohup qemu-system-x86_64 "''${QEMU_ARGS[@]}" > "$QEMU_LOG" 2>&1 &
        QEMU_PID=$!
        echo "$QEMU_PID" > "$PID_FILE"

        sleep 1
        if kill -0 "$QEMU_PID" 2>/dev/null; then
          echo ""
          green "✓ QEMU started (PID: $QEMU_PID)"
          if ${helpers.var.notEmpty "PORT_FORWARD"}; then
            cyan "  iso ssh      - SSH into guest (as $user)"
          fi
          cyan "  iso log      - View serial output"
          cyan "  iso status   - Check status"
          cyan "  iso stop     - Stop QEMU"
        else
          die "Error: QEMU failed to start\nCheck: cat $QEMU_LOG"
        fi
      fi
    }

    # Action: stop
    do_stop() {
      if is_running; then
        PID=$(get_pid)
        echo "Stopping QEMU (PID: $PID)..."
        kill "$PID"
        rm -f "$PID_FILE"
        green "✓ QEMU stopped"
      else
        yellow "QEMU is not running"
      fi
    }

    # Action: restart
    do_restart() {
      do_stop
      sleep 1
      do_run
    }

    # Action: status
    do_status() {
      if is_running; then
        PID=$(get_pid)
        green "QEMU is running (PID: $PID)"
        cyan "  iso ssh      - SSH into guest (as $user)"
        cyan "  iso log      - View serial output"
        cyan "  iso stop     - Stop QEMU"
      else
        yellow "QEMU is not running"
        cyan "  iso run   - Start QEMU"
      fi
    }

    # Action: ssh
    do_ssh() {
      if ! is_running; then
        die "QEMU is not running. Start with: iso run -k <keys-disk>"
      fi
      cyan "Connecting to guest as $user..."
      ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 "$user@localhost"
    }

    # Action: log
    do_log() {
      if ${helpers.file.exists "serial_log"}; then
        cyan "Serial log: $serial_log (Ctrl+C to exit)"
        tail -f "$serial_log"
      else
        die "No serial log found: $serial_log\nQEMU may not have started yet"
      fi
    }

    # Action: rebuild (force)
    do_rebuild() {
      rm -f "$ISO_PATH_FILE"
      force=true  # Set force flag for get_iso_path
      STORE_PATH=$(get_iso_path)
      ISO_FILE=$(find "$STORE_PATH" -name "*.iso" -type f | head -1)
      green "✓ ISO rebuilt: $ISO_FILE"
    }

    # Main dispatch
    case "$ACTION" in
      build)
        do_build
        ;;
      rebuild)
        do_rebuild
        ;;
      run)
        do_run
        ;;
      stop)
        do_stop
        ;;
      restart)
        do_restart
        ;;
      status)
        do_status
        ;;
      ssh)
        do_ssh
        ;;
      log|logs)
        do_log
        ;;
      path)
        do_path
        ;;
      copy|cp)
        do_copy
        ;;
      "")
        die "Error: Action required\n\nActions:\n  build    - Build ISO image (cached)\n  rebuild  - Force rebuild ISO (ignore cache)\n  run      - Build (if needed) and run in QEMU\n  stop     - Stop QEMU\n  restart  - Stop and restart QEMU\n  status   - Check if QEMU is running\n  ssh      - SSH into running guest\n  log      - View serial output\n  path     - Print ISO path in nix store\n  copy     - Copy ISO out of nix store (-o <path>)\n\nFlags:\n  -F, --force  - Force rebuild, ignore cache\n\nExamples:\n  iso build\n  iso build -F            # force rebuild\n  iso rebuild             # same as build -F\n  iso run -k keys.img\n  iso run -f              # foreground\n  iso ssh\n  iso log\n  iso stop\n  iso path                # print store path\n  iso copy -o ~/nixos.iso # copy for USB"
        ;;
      *)
        die "Unknown action: $ACTION\nValid actions: build, rebuild, run, stop, restart, status, ssh, log, path, copy"
        ;;
    esac
  '';
}
