# Bcachefs ephemeral-root plan for Nanoserver and Miniserver

Status: **Planning baseline approved; implementation and physical rollout are not authorized by this document.** This is the current source of truth for the storage/root-reset direction for Nanoserver-01 and Miniserver-01/02/03. It reconciles, but does not erase, older Btrfs/appliance and ZFS plans; those retain historical implementation and operational evidence.

## Goal

Plan a conventional NixOS system for Nanoserver-01 and Miniserver-01/02/03 using mirrored Bcachefs NVMe storage, independently bootable redundant USB ESPs, and a clean root recreated at every boot. Follow Misterio77/Foundry's persistence model, adapted from Btrfs to Bcachefs.

## Approved decisions

- **Nixpkgs selection:** Use `github:fzakaria/nixpkgs-multiverse` as the mechanism for selecting the Nixpkgs revision for these hosts, rather than accumulating a separate direct flake input for each desired snapshot. Select and lock a specific compatible Nixpkgs snapshot after checking the multiverse interface and NixOS/Bcachefs support; do not assume this changes unrelated repository inputs.
- **Hosts:** Nanoserver-01 and Miniserver-01/02/03. Treat the three Miniserver hosts as identical for initial sizing, based on Miniserver-01 inventory; verify each device identity immediately before any future destructive operation. Nanoserver is a separate host class.
- **Sizing only:** Nanoserver-01 inventory reported two ~1.00 TB NVMe devices and two ~64.2 GB USB devices. Each Miniserver has two ~465.8 GiB NVMe devices and two ~59.8 GiB USB devices. Existing Btrfs/F2FS layouts are explicitly disregarded as design constraints; this is not permission to overwrite them.
- **NVMe:** Use both NVMe drives as a Bcachefs mirror for root and persistent storage. Put swap on NVMe. No hibernation. Exact swap size and whether swap is mirrored or independently enabled remain open.
- **USB boot:** Use both USB drives for redundant boot/ESP. Each USB must be independently bootable without depending on a single EFI NVRAM entry; keep both ESPs synchronized. Leave remaining USB capacity unused/reserved for boot/ESP growth. Prove single-drive boot and synchronization in tests before a physical pilot.
- **Root/persistence:** Recreate a clean root filesystem at every boot. Keep `/nix` persistent. Follow Foundry as the persistence-pattern baseline, not its Btrfs disk layout. Feature state is volatile by default; each feature that needs state across resets must declare its persistence locally in that feature's own configuration file. Persist only explicit paths.
- **Backups:** Backup-system design is deferred. Document clearly that a mirrored pool is not a backup and persistent data currently has no planned off-host recovery path.
- **Rollout order:** Disposable VM/QEMU prototype first, then Nanoserver-01 as the first physical pilot, then Miniserver hosts one at a time. This records sequencing only; no physical operation is authorized.

## Reconciliation with prior plans

- `docs/plans/zfs-root-pivot.md` records an earlier ZFS preference and leaves the filesystem choice open. Its ZFS direction is superseded by the approved Bcachefs decision in this plan. Preserve it as decision history; do not treat its proposed ZFS layout as current.
- `docs/plans/nanoserver-01-store-ab-ephemeral-multihost.md` and `docs/plans/nanoserver-miniserver-platform.md` describe Btrfs appliance/A-B/store-image behavior. Their inventory, service intent, and operational evidence may remain useful, but their Btrfs disk layouts, USB A/B store-slot design, versioned-store boot model, and appliance update procedure are not the approved target architecture.
- `docs/plans/miniserver-install-readiness.md` is operational history and safety evidence, not authorization to install. Miniserver-01 remains failed/unverified in rescue per its latest recorded status. Do not reboot it, write to it, or otherwise operate it without separate explicit authorization.
- Existing implementation, tests, artifacts, and recovery documentation remain in place as fallback. Do not delete or rewrite them as part of planning.

## Constraints and safety

- The nix-config worktree has extensive pre-existing staged/unstaged/untracked work. Preserve it. Before any future commit, inspect status and staged diff; commit only task-owned changes.
- Do not install, repartition, format, import, destroy, or roll back pools; do not run Disko or `nixos-anywhere` on physical targets; do not change live systems, encrypted secrets, or keys.
- Never assume `/dev/nvme*` numbering or reuse existing Btrfs UUIDs/PARTUUIDs. Re-identify each device by stable paths and current live evidence immediately before any separately authorized destructive operation.
- Keep Miniserver-01's unresolved rescue/boot state as a hard safety constraint. Do not operate it without explicit authorization.
- Bcachefs support and boot/initrd behavior in the locked NixOS/nixpkgs versions are unverified. Validate actual options, kernel/module support, initrd availability, and recovery behavior before relying on them.

## Required prototype gates

1. **Configuration feasibility:** Inspect the locked NixOS/Bcachefs integration and Foundry's relevant persistence pattern. Confirm how Bcachefs is available in the kernel/initrd, how root and `/nix` mount, and how feature-local persistence is expressed. Verify with evaluation/builds; do not rely on remembered option names.
2. **Storage and boot in disposable VMs:** Model two NVMe and two USB devices. Test Bcachefs mirror creation/import, degraded operation and recovery; boot each USB independently with the peer absent; verify ESP synchronization and firmware fallback behavior; exercise swap on NVMe.
3. **Reset/persistence semantics:** Reboot repeatedly and prove root-only state is discarded, `/nix` remains usable, and explicitly declared feature state survives. Prove undeclared feature state is reset. Interrupt reset at relevant points and demonstrate recoverability.
4. **NixOS lifecycle and recovery:** Test generation switch/rollback, failed boot, degraded NVMe boot, and recovery from missing or failed USB/NVMe media. No test may target physical host disks.
5. **Review and rollout readiness:** Identify host-specific persistence declarations from configuration and service inventory. Keep backup system marked deferred. Revalidate device mapping, boot firmware behavior, recovery access, and per-host authorization before any physical migration.

## Open decisions — do not guess

- Exact Bcachefs device/replica configuration, formatting and mount options, subvolume/snapshot/reset mechanism, and initrd implementation.
- Exact partition sizes and USB partition table; exact NVMe swap size and activation policy.
- Bootloader choice and concrete EFI fallback/synchronization mechanism, subject to single-USB tests.
- Feature-by-feature persistent paths and any shared core identity/secrets requirements, determined by inspection of host feature configs.
- Backup design, destination, retention, and restore testing (explicitly deferred).
- Whether and when to authorize a physical pilot after all disposable-system gates pass.

### For Executor

Read order: this plan; `docs/plans/zfs-root-pivot.md`; `docs/plans/nanoserver-01-store-ab-ephemeral-multihost.md`; `docs/plans/nanoserver-miniserver-platform.md`; `docs/plans/miniserver-install-readiness.md`; current host profiles/features, `flake.nix`, `checks.nix`, and tests.

Assumed working state: the nix-config worktree contains extensive unrelated user changes. Preserve every pre-existing change. Miniserver-01 is not safe to operate based on current evidence. The size inventory is for planning, not destructive target authorization.

Owned files: this plan only unless the user separately approves implementation scope.

Verification commands for this planning artifact: `git diff --check -- docs/plans/bcachefs-ephemeral-root-multihost.md`; compare decisions and safety constraints with the cited plans. No system or disk commands are authorized by this plan.
