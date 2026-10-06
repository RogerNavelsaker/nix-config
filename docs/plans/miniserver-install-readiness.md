# Miniserver install readiness

Status: miniserver profiles and one-pass disposable-QEMU Disko layout checks are complete. Pinned nix-lib reproducibility and disposable-QEMU `nixos-anywhere --extra-files` key-transfer validation remain blocked. No physical Disko or `nixos-anywhere` operation has been run.

## Evidence

- The rescue ISO is RAM-based. The user reports all four nodes booted and are online over Tailscale; read-only SSH diagnostics (`nix`, `lsblk`, `nixos-facter`) succeeded.
- Each miniserver reports 64 GiB RAM and an Intel i5-8600T. Each has two approximately 465.8 GiB NVMe devices and two approximately 59.8 GiB USB devices. Existing NVMe devices have vfat/btrfs partitions.
- Read-only live by-path inventory (2026-10-04; do not treat as pre-install authorization): miniserver-01 NVMe PCI `01:00.0` → `nvme0n1`, `02:00.0` → `nvme1n1`; miniserver-02 same mapping; miniserver-03 PCI `01:00.0` → `nvme1n1`, `02:00.0` → `nvme0n1`. Across all three, USB port 9 resolves to the first 59.8 GiB Flash Drive FIT (`/dev/sdb` in this rescue boot), and port 10 to the second (`/dev/sdc`). Stable path forms observed: `/dev/disk/by-path/pci-0000:01:00.0-nvme-1`, `/dev/disk/by-path/pci-0000:02:00.0-nvme-1`, and USB `pci-0000:00:14.0-usbv3-0:9:1.0-scsi-0:0:0:0` / `...-0:10:1.0-scsi-0:0:0:0`. Enumeration differs, so never substitute `/dev/nvme*` or `/dev/sd*` in profiles.
- Limited Facter hardware probes (`cpu,memory,pci,block`; serial probe excluded) were run for each miniserver and written mode `0600` under `/run`. The allow-listed summary confirmed x86_64, six-core Intel i5-8600T, 64 GiB RAM, two CT500P3SSD8 NVMe devices each, and two Samsung Flash Drive FIT USB devices each. Reports were removed from `/run` after summary; none was copied into the repo.
- Additional read-only `lsblk` inspection confirmed existing partitions on the target devices: the USB devices currently have F2FS partitions; NVMe devices have existing small EFI and large Btrfs partitions. Current PARTUUID/UUID values are existing-layout identifiers and are intentionally not captured here or reused. This corroborates that every future Disko profile must explicitly replace existing layouts and receive newly generated, unique IDs.
- The existing multihost plan assigns the two USBs to appliance A/B store slots and the NVMe pair to mirrored `/persist` plus 8 GiB swap on each. It explicitly excludes the separate 4 TB Ventoy disk from every Disko target. Confirm this role mapping and exact target identity live immediately before any future destructive command.
- Nanoserver-01 has different hardware and has user-reported appliance QEMU success. That does not validate miniserver layouts or the install transfer path.
- The user authorizes replacing old Proxmox data on miniserver hosts. This is not authorization to act on an ambiguous target.

## Profile authoring notes

- The current shared intent in `docs/plans/nanoserver-01-store-ab-ephemeral-multihost.md` assigns miniserver USB A/B to appliance A/B store slots and the NVMe pair to mirrored `/persist` plus two 8 GiB swap partitions. The separate 4 TB Ventoy device is excluded. Validate this against the intended miniserver role before implementing.
- Existing `hosts/nanoserver-01/devices.nix` and `appliance-disko/disk-layout.nix` are a shape/template only; do not reuse Nanoserver device paths or any of its UUID/PARTUUID values.
- Each miniserver needs its own sanitized Facter report and unique partition/filesystem UUIDs. Do not commit serials, copy reports containing identifying serial data, or derive a host-to-device assignment from `/dev/nvme*` enumeration.

## Gates before physical installation

1. Generate/retain sanitized per-host Facter facts, map stable by-path paths, and author explicit per-host miniserver profiles with unique filesystem identifiers. Evaluate configurations without touching disks.
2. Exercise each applicable Disko layout and the full `nixos-anywhere` install on disposable QEMU disks.
3. Verify stable host-key transfer end-to-end with a disposable test key. Use `nixos-anywhere --extra-files <root-shaped-tree>` with the intended key at `etc/ssh/ssh_host_ed25519_key`, mode `0600`. Keep staging under `/run`, outside `/nix/store` and logs. Do not use `--copy-host-keys`, which can copy the temporary rescue identity. After install, compare the installed key fingerprint with the corresponding public key; remove staging material.
4. Complete and document the operator workflow and applicable QEMU gates.
5. Immediately before each destructive physical install, reconfirm the host identity, device paths, device sizes, and Ventoy exclusion. Install one host at a time; verify boot and recovery before proceeding.

## Profile and test status (2026-10-04)

- Added `hosts/miniserver-01`, `-02`, and `-03` profiles with sanitized per-host Facter reports, shared wired appliance modules, stable by-path device paths, and distinct newly generated PARTUUID/filesystem UUIDs. Reports were recursively stripped of fields whose keys match serial, WWN, MAC, or UUID; the stripped reports were verified before copying, and rescue `/run` copies were removed.
- Each configuration has slot-A and slot-B variants so the initial slot-A closure includes the peer UKI and the slot-B system closure.
- Added one disposable NixOS VM Disko format/mount test per miniserver. All three tests pass with 16 GiB virtual disks and verify the two-member Btrfs root and persistence RAID1 filesystems. The test deliberately runs one format+mount cycle; the upstream `makeDiskoTest` repeat-destroy cycle currently fails because its `umount -R /mnt` does not detach nested target mounts when `/mnt` is not itself mounted. Do not interpret that repeatability failure as a physical-media failure; track/fix the harness behavior separately before claiming repeated destroy/mount idempotence.
- All six host/slot system derivations evaluate when overriding nix-lib to the local worktree. Without the override, evaluation fails because the pinned nix-lib revision does not provide `nix-lib.impermanence`, which the existing dirty nix-config appliance modules call. Do not update the nix-config lock until the owning nix-lib change is published through the cross-repo sync chain.
- Git flake source excludes ordinary untracked files. Intent-to-add was used on relevant Nanoserver/appliance and miniserver source/test paths; contents remain unstaged. Generated `.devenv/` files and `devenv.lock` remain untouched.

The QEMU tests format only disposable VM disks. They do not run Disko on the physical miniserver targets and do not test `nixos-anywhere --extra-files` or stable-key fingerprint installation. Upstream `nixos-anywhere` currently rejects `--vm-test` combined with `--extra-files` (`runVmTest` explicitly exits), so this key-transfer acceptance gate requires a separate disposable target VM and an actual `nixos-anywhere` install-phase run; the layout VM check alone cannot prove it.

## Current stop condition

The miniserver profile and Disko QEMU gates are now complete, but pinned nix-lib reproducibility and end-to-end disposable-QEMU validation of `nixos-anywhere --extra-files` with a disposable key remain outstanding. Do not run Disko or `nixos-anywhere` against physical hosts until those gates pass and an operator immediately reidentifies each target. Earlier executable `EIO` observations may have resulted from detached rescue media and are not, by themselves, evidence of hardware failure.

## Earlier Nanoserver baseline evaluation

The first `nanoserver-01-disko-layout` flake evaluation was blocked because Nix omits untracked files from the Git flake source. Resolved without staging file contents: `git add -N` (intent-to-add) was applied only to the relevant Nanoserver/appliance source and test files. A cached check initially appeared to pass; when rerun, the upstream repeat-destroy harness failed because nested `/mnt` mounts remained active. The Nanoserver test now uses the same focused one-pass VM format/mount test and passes. Nanoserver device-option evaluation returned its configured by-path paths. This remains a virtual layout test, not physical-install validation. Intent-to-add entries remain in the index; file contents are not staged.
