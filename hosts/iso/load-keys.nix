# hosts/iso/load-keys.nix
# Ventoy key injection support - keys are injected into initramfs by Ventoy bootloader
# SSH host keys for sops-nix + FlakeHub token for private flake access
# Both are host-unique, locally stored, and persisted permanently
{
  lib,
  pkgs,
  ...
}:
{
  environment.systemPackages = [ pkgs.load-keys ];

  boot = {
    initrd = {
      # Virtio support for QEMU testing with Ventoy disk
      kernelModules = [
        "virtio_blk"
        "virtio_pci"
      ];
      availableKernelModules = [
        "virtio_blk"
        "virtio_pci"
      ];

      # Make load-keys utility available in initrd
      extraUtilsCommands = ''
        copy_bin_and_libs ${pkgs.load-keys}/bin/load-keys
      '';

      # Load Ventoy-injected keys during initramfs (stage 1) - BEFORE sops-nix runs
      # Ventoy extracts keys.tar.gz into initramfs root before boot
      postMountCommands = ''
        echo "=== Stage 1: Loading host keys (Ventoy) ==="

        # SSH host key (required for sops-nix)
        if [ -f /etc/ssh/ssh_host_ed25519_key ]; then
          echo "Found Ventoy-injected SSH host key, copying to target..."
          ${pkgs.load-keys}/bin/load-keys / $targetRoot
        else
          echo "No Ventoy-injected SSH host key found"
        fi

        # FlakeHub token (required for private flake access)
        if [ -f /nix/var/determinate/flakehub-token ]; then
          echo "Found Ventoy-injected FlakeHub token, copying to target..."
          mkdir -p "$targetRoot/nix/var/determinate"
          cp /nix/var/determinate/flakehub-token "$targetRoot/nix/var/determinate/flakehub-token"
          chmod 600 "$targetRoot/nix/var/determinate/flakehub-token"
        else
          echo "No Ventoy-injected FlakeHub token found"
        fi

        echo "=== Stage 1: Host key loading complete ==="
      '';
    };

    # Override installation-cd-minimal.nix defaults
    postBootCommands = lib.mkForce "";
  };

  # FlakeHub authentication using host-unique token (same model as SSH host keys)
  # Token is persisted locally, not managed by sops-nix (avoids race condition)
  systemd.services.flakehub-auth = {
    description = "Authenticate to FlakeHub using host token";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      TOKEN_FILE="/nix/var/determinate/flakehub-token"
      if [ -f "$TOKEN_FILE" ]; then
        echo "Authenticating with FlakeHub token..."
        ${pkgs.determinate-nixd}/bin/determinate-nixd login token --token-file "$TOKEN_FILE"
        echo "FlakeHub authentication complete"
      else
        echo "No FlakeHub token found at $TOKEN_FILE"
        echo "Private flakes will not be accessible"
      fi
    '';
  };
}
