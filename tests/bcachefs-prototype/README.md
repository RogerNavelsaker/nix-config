# Bcachefs disposable prototype
This is an isolated QEMU-only prototype for the Bcachefs plan's Gate 2. It is not imported by the production flake and must never be pointed at host disks.

`storage.nix` uses two disposable 512 MiB virtual block devices to test mirror creation, subvolume snapshots, root reset while preserving a separate `/nix` subvolume, and offline/online degraded recovery. `root-boot.nix` boots a NixOS specialisation with Bcachefs as `/`, resets the root subvolume in the initrd, injects a one-shot reboot during reset, and verifies recovery plus missing-replica boot and reattachment. `nvme-root-boot.nix` attaches two disposable QEMU NVMe devices, formats them as a Bcachefs mirror, and boots a NixOS specialisation with that mirror as `/`. `usb-boot.nix` builds two independent GPT/FAT ESP images with systemd-boot fallback loaders and distinct UKIs, boots a fresh-variables OVMF guest from each, then tests sequential UKI installation and ESP synchronization. These are separate component checks: they do not yet prove an integrated NixOS deployment workflow, real-firmware compatibility, or physical USB transport.
The tests select Nixpkgs revision `d4f25a3e562008648d45bcf2d70bcc7422cad84e` through the locked `nixpkgs-multiverse` input. Build and run all QEMU checks with:

```sh
nix build --no-link --no-write-lock-file --max-jobs 2 \\
  path:./tests/bcachefs-prototype#checks.x86_64-linux.bcachefs-storage \\
  path:./tests/bcachefs-prototype#checks.x86_64-linux.bcachefs-root-boot \\
  path:./tests/bcachefs-prototype#checks.x86_64-linux.bcachefs-usb-boot \\
  path:./tests/bcachefs-prototype#checks.x86_64-linux.bcachefs-nvme-root-boot \\
  path:./tests/bcachefs-prototype#checks.x86_64-linux.bcachefs-swapfile-rejection
```
The `swapfile.nix` probe verifies that a fully written 64 MiB Bcachefs file still cannot be activated as swap on this locked kernel (`swapon` reports “swapfile has holes” / `EINVAL`). Separate exploratory QEMU trials found that sparse `fallocate` allocation is likewise rejected, and `chattr +C` is unsupported, so the mirrored-Bcachefs swapfile path is not currently viable. This probe only establishes swapfile rejection; it does not test swap under degraded operation. The next candidate is dedicated RAID1 swap, including initrd assembly and one-member-loss read/write tests.


Gate 2 is still incomplete. Remaining QEMU work includes resolving the planned NVMe swap size/topology and testing it, exercising generation switch/rollback and failed-media recovery, and combining the mirrored-NVMe root with the independently bootable USB ESP workflow. These checks do not authorize physical rollout.
