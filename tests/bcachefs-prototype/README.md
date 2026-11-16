# Bcachefs disposable prototype
This is an isolated QEMU-only prototype for the Bcachefs plan's Gate 2. It is not imported by the production flake and must never be pointed at host disks.

`storage.nix` uses two disposable 512 MiB virtual block devices to test mirror creation, subvolume snapshots, root reset while preserving a separate `/nix` subvolume, and offline/online degraded recovery. `root-boot.nix` boots a NixOS specialisation with Bcachefs as `/`, resets the root subvolume in the initrd, injects a one-shot reboot during reset, and verifies recovery plus missing-replica boot and reattachment. `nvme-root-boot.nix` attaches two disposable QEMU NVMe devices, formats them as a Bcachefs mirror, boots a NixOS specialisation with that mirror as `/`, and checks persistent `/nix`, ephemeral-root reset, and recovery from an interrupted reset. `usb-boot.nix` builds two independent GPT/FAT ESP images with systemd-boot fallback loaders and distinct UKIs, boots a fresh-variables OVMF guest from each, then tests sequential UKI installation and ESP synchronization. `integrated-boot.nix` prepares a mirrored NVMe filesystem in one disposable VM, then boots one guest from USB A with both NVMe members and another from USB B with one NVMe member absent. Both verify the selected USB, Bcachefs `/`, volatile-root reset, and persistent `/nix`; the latter exercises degraded root boot/reset. This exercises the combined boot/root path but does not prove production update integration, real-firmware compatibility, or physical USB transport.
The tests select Nixpkgs revision `d4f25a3e562008648d45bcf2d70bcc7422cad84e` through the locked `nixpkgs-multiverse` input. Build and run all QEMU checks with:

```sh
nix build --no-link --no-write-lock-file --max-jobs 2 \\
  path:./tests/bcachefs-prototype#checks.x86_64-linux.bcachefs-storage \\
  path:./tests/bcachefs-prototype#checks.x86_64-linux.bcachefs-root-boot \\
  path:./tests/bcachefs-prototype#checks.x86_64-linux.bcachefs-usb-boot \\
  path:./tests/bcachefs-prototype#checks.x86_64-linux.bcachefs-nvme-root-boot \\
  path:./tests/bcachefs-prototype#checks.x86_64-linux.bcachefs-integrated-usb-nvme-root \\
  path:./tests/bcachefs-prototype#checks.x86_64-linux.bcachefs-swapfile-rejection
```
The `swapfile.nix` probe verifies that a fully written 64 MiB Bcachefs file still cannot be activated as swap on this locked kernel (`swapon` reports “swapfile has holes” / `EINVAL`). Separate exploratory QEMU trials found that sparse `fallocate` allocation is likewise rejected, and `chattr +C` is unsupported, so the mirrored-Bcachefs swapfile path is not currently viable. This probe only establishes swapfile rejection; it does not test swap under degraded operation. The current design decision is no swap for now; swap implementation and degraded-operation swap gates are deferred unless this decision is revisited.


Gate 2 remains incomplete. Swap is deferred under the current no-swap decision. Remaining QEMU gates are generation switch/rollback and recovery after missing media is reattached and resynchronized. Real-firmware compatibility and production update integration also remain unverified; no physical rollout is authorized.
