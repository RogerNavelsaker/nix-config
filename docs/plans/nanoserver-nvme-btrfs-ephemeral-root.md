# Nanoserver NVMe-backed ephemeral Btrfs root

## Status

Approved for v4-only local implementation and QEMU validation. Existing tmpfs behavior for v2/v3 remains unchanged. No physical Disko operation, deployment, or reboot is authorized.

## Local implementation status

- `appliance.rootStorage` defaults to `tmpfs`; only the unpublished v4 A/B profiles select `nvme-btrfs`. V2/v3 retain tmpfs-root behavior.
- The v4 Disko layout declares `@root` and `@root-blank` beside `@persist`; its post-create hook marks the blank template read-only. Initrd scans USB/NVMe members and makes the root-reset service required before `sysroot.mount`.
- The reset validates the read-only template before deleting only `@root`; it recreates a missing `@root` after an interrupted reset. It never targets `@persist` or the USB store pool.
- The v3/v4 slot evaluation check and file-backed Disko QEMU test pass. The latter covers reset, persistence retention, read-only template, missing-root recovery, and missing-template fail-closed behavior. Both v4 toplevels build.
- This is not a full v4-root boot test. Safe first-use provisioning on an existing NVMe filesystem and physical hardware validation remain open; no physical operation, deployment, reboot, or publication occurred.

## Goal

Evaluate replacing Nanoserver's 2 GiB tmpfs `/` with a per-boot-reset Btrfs subvolume on the existing mirrored NVMe filesystem. Keep `/persist` as its own NVMe Btrfs subvolume and keep the versioned, read-only `/nix/store` plus normal sysupdate writes on the mirrored USB pool.

## Constraints

- No deployment, reboot, physical disk operation, formatting, workload creation, signing, or publication without separate explicit authorization.
- Preserve USB software A/B, manual reboot, and the read-only normal-boot store mounts.
- Keep `/persist` independent from root reset. A root reset must never recurse over the Btrfs top level, delete `@persist`, or touch the USB update pool.
- Keep the current USB `appliance.update.rootPoolPath` exclusively for USB store staging. A separate, clearly named NVMe top-level mount path is required if the reset helper needs one.
- A one-member NVMe mirror may boot degraded if tests prove it. With neither NVMe member available, boot failure is expected unless a separately designed recovery path is approved.
- Btrfs subvolume deletion is not secure erasure; ephemeral means reset on boot, not confidentiality or power-loss rollback.
- QEMU/file-backed tests do not prove physical NVMe/USB transport, firmware, or performance behavior.
- Preserve published Nanoserver v2/v3 artifacts and their configuration behavior; select NVMe Btrfs root only for the unpublished v4 profiles.

## Non-goals

- Do not alter the published v2/v3 bundles or their tmpfs-root configuration.
- Do not change USB A/B, sysupdate behavior, `/persist` contents, workloads, secrets, or deployment policy.
- Do not perform physical Disko operations or treat Btrfs deletion as secure erasure.

## Current baseline

- `hosts/features/opt-in/appliance/rootfs.nix` mounts `/` as 2 GiB tmpfs, mounts the selected USB member's versioned store read-only at `/nix/store`, and mounts the USB Btrfs top level at `appliance.update.rootPoolPath` for update staging.
- Its initrd scan/readiness handling covers the USB store members. A Btrfs root also needs the NVMe mirror scanned and its PARTUUID readiness handled before root mounting.
- `hosts/features/opt-in/appliance-disko/disk-layout.nix` creates the NVMe Btrfs filesystem with `@persist`; `hosts/features/opt-in/appliance/persistence.nix` mounts that subvolume at `/persist` with `neededForBoot = true`.
- `tests/nanoserver-slot-uki.nix` evaluates `nanoserver-01-update-v3-a/b` and asserts tmpfs `/`; it does not cover v4. `tests/nanoserver-disko-layout.nix` delegates to the miniserver Disko-layout test. The active plan, `docs/plans/nanoserver-01-store-ab-ephemeral-multihost.md`, also specifies tmpfs `/`; this proposal changes only the root-storage decision if adopted.
- Foundry's blank-root snapshot is a useful reference for reset semantics, not a drop-in module or layout.

## Investigation findings

- Evaluating both v4 slot configurations confirms `root=fstab`; `/` is currently tmpfs, `/persist` is `@persist` on the NVMe filesystem UUID, and `/nix/store` uses the slot's USB PARTUUID. The slot-UKI test currently evaluates v3 only.
- The pinned Disko Btrfs implementation creates declared subvolumes and provides generic create hooks. It does not provide a read-only blank snapshot automatically; a guarded hook and repeat-create test are needed.
- Foundry orders reset after its root device and before `sysroot.mount`, but only wants the service from `initrd.target`; it does not establish that root mounting is blocked on reset failure. Nanoserver must test explicit failure propagation. Foundry's delete-then-snapshot script also does not demonstrate interruption-safe recovery.

## Candidate design

1. Add an explicit root mode that defaults to current tmpfs behavior; select NVMe Btrfs only in the unpublished v4 profiles so v2/v3 configurations and published bundles remain unchanged.
2. Add writable NVMe `@root` and read-only `@root-blank` alongside `@persist`. The pinned Disko Btrfs content creates declared subvolumes and exposes a generic `postCreateHook`; use a guarded hook only if repeat-create tests prove it never replaces existing template/state.
3. In systemd initrd, scan NVMe members, mount the NVMe top level at a dedicated path, and reset `@root` before generated `sysroot.mount`. Make `sysroot.mount` require the reset service so failure cannot boot stale root. Foundry demonstrates device/mount ordering, but verify exact dependencies and failure propagation on pinned NixOS.
4. Mount `/` from NVMe `@root` as Btrfs with degraded and explicit mount options. Keep `/persist` separately mounted from `@persist` and preserve current persistence choices.
5. Preserve USB selection by slot: each UKI still selects its local USB member for the versioned `/nix/store`; that store remains read-only in normal operation. Keep sysupdate's USB top-level target and inactive-version writes unchanged.
6. Keep required mountpoint directories in the blank root. Confirm `/etc`, `/var`, `/run`, `/nix/var`, `/persist`, and `/nix/store` mount/creation order and image-appliance behavior rather than assuming tmpfs-root semantics carry over.

## Scope if approved

- Appliance root/initrd and option modules under `hosts/features/opt-in/appliance/`; select the new mode only in v4 profile wiring in `hosts/nanoserver-01/configurations.nix`.
- NVMe subvolume layout under `hosts/features/opt-in/appliance-disko/` and Nanoserver host profile values only where needed.
- Keep `tests/nanoserver-slot-uki.nix` as v3 tmpfs coverage; add v4 evaluation assertions and a focused QEMU boot/reset test. Extend `tests/nanoserver-disko-layout.nix` or the shared miniserver fixture to verify `@root`, read-only `@root-blank`, and `@persist` without physical disks.
- `checks.nix` if a new test derivation is added.
- `docs/APPLIANCE-UPDATES.md`, `docs/IMPERMANENCE.md`, and the active store/A-B plan to document the final mount and reset boundaries.

Do not change user Home Manager persistence, host selection, workloads, update publication, signing, or physical Disko execution as part of this work.

## Steps and gates

1. **Resolve systemd-initrd ordering.** Prove that the NVMe scan and reset service run after devices are available but before the root mount. Verify the exact pinned NixOS/systemd/Disko APIs; do not copy Foundry's newer impermanence syntax.
2. **Make the layout evaluable.** Add the root/template subvolumes and a distinct NVMe top-level mount option. Assert that `@root`, `@root-blank`, and `@persist` share the NVMe filesystem while the USB root pool remains the sysupdate target.
3. Implement a bounded, idempotent reset using explicit `@root` and `@root-blank` paths; fail closed if reset fails. Test interruption after each subvolume operation and retry on the next boot. Use a temporary-name protocol only if a simpler delete/snapshot sequence fails those tests.
4. **Test real boot semantics in QEMU.** Boot with file-backed NVMe mirror and USB store members; verify fresh `/` after reboot, stable `/persist` data and host identity, read-only `/nix/store`, correct slot selection, and a degraded boot with one NVMe member missing. Verify sysupdate staging still writes only to the USB pool. Keep this evidence separate from physical-hardware claims.
5. **Review resources and recovery.** Measure root Btrfs writes/space and boot time against the current tmpfs baseline; document recovery when both NVMe members are unavailable. Do not infer that NVMe backing reduces total writes or provides secure deletion.
6. **Update documentation and active architecture plan** only after the gates pass and the user chooses to adopt the design. Then run formatting, targeted checks, full flake checks, `git diff --check`, and review the complete diff. No deployment or disk operation is included.

## Verification commands

After local implementation, run from the repository root:

```bash
nix build .#checks.x86_64-linux.nanoserver-01-slot-uki \
  .#checks.x86_64-linux.nanoserver-01-disko-layout --no-link
nix build \
  .#nixosConfigurations.nanoserver-01-update-v4-a.config.system.build.toplevel \
  .#nixosConfigurations.nanoserver-01-update-v4-b.config.system.build.toplevel \
  --no-link
nix flake check --option eval-cache false -L
git diff --check
```

The existing `nanoserver-01-disko-layout` QEMU test exercises Btrfs reset behavior; it does not boot the full v4 root configuration.

## Rollback

Revert only the root-subvolume/initrd changes and restore the existing tmpfs `/` configuration. Leave `/persist`, the USB store A/B layout, update bundles, and unrelated dirty worktree changes untouched. Do not use Disko to undo or apply anything on physical media.

## Open questions

- The reset unit is ordered after `initrd-root-device.target`, before `sysroot.mount`, and required by `sysroot.mount`; evaluation asserts these declarations and both v4 toplevels build. A full v4-root QEMU boot is still needed to verify runtime ordering and failure propagation.
- The v4 Disko layout declares `@root` and `@root-blank`; its post-create hook marks the blank template read-only. The file-backed QEMU test verifies the template and reset behavior.
- The reset recovers from a missing `@root` and validates `@root-blank` before deleting anything. Missing-root retry and missing-template fail-closed behavior pass in QEMU; an actual power interruption during delete/snapshot remains untested.
- Safe first-use provisioning into an existing NVMe filesystem is unresolved. Disko remains destructive; a future, separately authorized procedure must create only `@root` and `@root-blank` without touching `@persist`.
- One-member degraded boot, no-member recovery, NVMe free-space reserve, write volume, and boot-time/performance remain unverified.


### For executor

Read order: this plan; `AGENTS.md`; `hosts/features/opt-in/appliance/{options,rootfs,persistence}.nix`; `hosts/features/opt-in/appliance-disko/disk-layout.nix`; `hosts/nanoserver-01/configurations.nix`; `tests/nanoserver-slot-uki.nix`; `tests/nanoserver-disko-layout.nix`; pinned NixOS systemd-initrd and Disko Btrfs sources.

Assumed working state: preserve every existing dirty path; v2/v3 artifacts and tmpfs behavior remain unchanged; do not deploy, publish, reboot, or run Disko against physical devices.

Verification commands: the exact commands are listed under **Verification commands** above. QEMU results do not establish hardware behavior.
