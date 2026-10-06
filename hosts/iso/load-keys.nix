# Decrypt the SOPS identity from Ventoy-injected material during initrd boot.
# Ventoy expands the configured archive into the initramfs root.
{
  lib,
  config,
  ...
}:
let
  hostname = config.hostSpec.hostname or "iso";
  unlockTimeout = config.rescueIso.yubikeyUnlockTimeoutSeconds;
in
{
  options.rescueIso.yubikeyUnlockTimeoutSeconds = lib.mkOption {
    type = lib.types.ints.between 15 600;
    default = 120;
    description = "Maximum time to wait for YubiKey-backed SOPS identity unlock during rescue boot.";
  };

  config = {
    boot.initrd = {
      kernelModules = [
        "virtio_blk"
        "virtio_pci"
      ];
      availableKernelModules = [
        "virtio_blk"
        "virtio_pci"
      ];

      postDeviceCommands = ''
        echo "=== Stage 1: GPG/YubiKey setup ==="
        if [ ! -f /private/.gpg-id ]; then
          echo "No Ventoy-injected key archive; powering off."
          busybox poweroff -f
          exit 1
        fi

        PCSC_BIN=$(dirname "$(command -v pcscd)")
        export PCSCLITE_HP_DROPDIR="$PCSC_BIN/../var/lib/pcsc/drivers"
        export PCSCLITE_CSOCK_NAME=/run/pcscd/pcscd.comm
        PCSC_LIB="$PCSC_BIN/libpcsclite_real.so.1"
        mkdir -p /run/pcscd
        pcscd --foreground &
        PCSCD_PID=$!
        export PCSCD_PID
        sleep 2

        GNUPGHOME=/run/rescue-gnupg
        export GNUPGHOME
        GPG_TTY="/dev/$console"
        export GPG_TTY
        TERM=linux
        export TERM

        GPG_BIN=$(command -v gpg)
        GPG_AGENT_BIN=$(command -v gpg-agent)
        GPG_SHELL=$(command -v bash)
        PINENTRY=$(command -v pinentry-tty)
        SCDAEMON=$(command -v scdaemon)
        if [ -z "$GPG_BIN" ] || [ -z "$GPG_AGENT_BIN" ] || [ -z "$GPG_SHELL" ] || [ -z "$PINENTRY" ] || [ -z "$SCDAEMON" ]; then
          echo "ERROR: GPG smartcard tools missing from initrd PATH"
        else
          PATH="$GNUPGHOME/bin:$PATH"
          export PATH

          # Keep private GPG files restrictive without changing permissions
          # on stage-1 mount points created by the rest of this init script.
          (
            umask 077
            mkdir -p "$GNUPGHOME/bin"
            chmod 700 "$GNUPGHOME" "$GNUPGHOME/bin"

            cat > "$GNUPGHOME/bin/gpg" << GPGWRAPPER
        #!$GPG_SHELL
        exec "$GPG_BIN" --agent-program="$GPG_AGENT_BIN" "\$@"
        GPGWRAPPER
            chmod 700 "$GNUPGHOME/bin/gpg"

            cat > "$GNUPGHOME/gpg-agent.conf" << GPGCONF
        pinentry-program $PINENTRY
        scdaemon-program $SCDAEMON
        allow-loopback-pinentry
        GPGCONF

            cat > "$GNUPGHOME/scdaemon.conf" << SCDCONF
        pcsc-driver $PCSC_LIB
        disable-ccid
        SCDCONF

            if [ -f /private/.gpg-pubkey.asc ]; then
              gpg --import /private/.gpg-pubkey.asc 2>/dev/null || true
            fi
          )
        fi
      '';

      postMountCommands = ''
        echo "=== Stage 1: Rescue credential setup ==="
        if [ ! -f /private/.gpg-id ]; then
          echo "No encrypted rescue identity; powering off."
          busybox poweroff -f
          exit 1
        elif [ ! -x "$GNUPGHOME/bin/gpg" ]; then
          echo "GPG setup unavailable; powering off."
          busybox poweroff -f
          exit 1
        else
          export GPG_TTY="/dev/$console"
          export TERM=linux
          export PASSWORD_STORE_DIR=/private
          gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1 || true
          TEMP_KEY=$(mktemp)
          unlock_deadline=$(( $(date +%s) + ${toString unlockTimeout} ))
          printf 'YubiKey unlock waiting up to ${toString unlockTimeout}s. Use only the masked pinentry prompt; touch the key if it blinks.\n' > "/dev/$console"
          UNLOCKED=no
          CARD_READY=no
          CARD_STATUS_ERROR_SHOWN=no
          CARD_STATUS_ERR=/run/rescue-card-status.err
          while [ "$(date +%s)" -lt "$unlock_deadline" ]; do
            remaining=$(( unlock_deadline - $(date +%s) ))
            [ "$remaining" -gt 0 ] || break

            # Populate GPG's card-backed secret-key stubs before decrypting.
            # card-status reads public card metadata and does not verify the PIN.
            if [ "$CARD_READY" = no ]; then
              if timeout 5s gpg --card-status >/dev/null 2>"$CARD_STATUS_ERR"; then
                CARD_READY=yes
                rm -f "$CARD_STATUS_ERR"
                printf 'OpenPGP card detected; requesting host identity unlock.\n' > "/dev/$console"
              elif [ "$CARD_STATUS_ERROR_SHOWN" = no ]; then
                printf 'OpenPGP card status unavailable: ' > "/dev/$console"
                cat "$CARD_STATUS_ERR" > "/dev/$console"
                CARD_STATUS_ERROR_SHOWN=yes
              fi
            fi
            if [ "$CARD_READY" = yes ]; then
              remaining=$(( unlock_deadline - $(date +%s) ))
              if [ "$remaining" -gt 0 ] && timeout "''${remaining}s" pass show "hosts/${hostname}/ssh_host_ed25519_key" > "$TEMP_KEY" && [ -s "$TEMP_KEY" ]; then
                UNLOCKED=yes
              else
                rm -f "$TEMP_KEY"
              fi
              # Never prompt repeatedly or consume additional PIN retries.
              break
            fi
            sleep 1
          done

          if [ "$UNLOCKED" = yes ]; then
            mkdir -p /run/rescue
            mv "$TEMP_KEY" /run/rescue/ssh_host_ed25519_key
            chmod 600 /run/rescue/ssh_host_ed25519_key
            rm -f "$CARD_STATUS_ERR"
            printf 'Temporary SOPS identity unlocked into RAM.\n' > "/dev/$console"
          else
            rm -f "$TEMP_KEY"
            printf 'YubiKey unlock timed out; powering off without starting stage 2.\n' > "/dev/$console"
            kill "$PCSCD_PID" 2>/dev/null || true
            gpgconf --kill gpg-agent 2>/dev/null || true
            rm -rf "$GNUPGHOME"
            rm -f "$CARD_STATUS_ERR"
            busybox poweroff -f
            exit 1
          fi

          kill "$PCSCD_PID" 2>/dev/null || true
          gpgconf --kill gpg-agent 2>/dev/null || true
          rm -rf "$GNUPGHOME"
        fi
      '';
    };

    boot.postBootCommands = lib.mkForce "";
  };
}
