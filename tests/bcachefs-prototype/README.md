# Bcachefs disposable prototype
This is an isolated QEMU-only prototype for the Bcachefs plan's Gate 2. It is not imported by the production flake and must never be pointed at host disks.

`storage.nix` uses two disposable 512 MiB virtual block devices to test mirror creation, subvolume snapshots, root reset while preserving a separate `/nix` subvolume, and offline/online degraded recovery. `root-boot.nix` boots a NixOS specialisation with Bcachefs as `/`, resets the root subvolume in the initrd, and injects a one-shot reboot after deleting the old root but before restoring its snapshot. It checks recovery, then verifies that `/var/lib` resets while `/nix` persists. These tests do not model physical NVMe/USB transport, independent ESP fallback, or missing-disk boot.
The test selects Nixpkgs revision `d4f25a3e562008648d45bcf2d70bcc7422cad84e` through the locked `nixpkgs-multiverse` input. Run it with:

```sh
nix flake check --no-write-lock-file path:./tests/bcachefs-prototype
```

Further QEMU tests for independent USB ESP boot, firmware fallback, additional reset-interruption points, boot with a missing replica and subsequent recovery, and NVMe swap remain required before Gate 2 can pass. No physical operation is authorized.
