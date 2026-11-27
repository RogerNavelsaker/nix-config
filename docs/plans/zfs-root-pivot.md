# ZFS root pivot for Nanoserver-01 and Miniserver-01/02/03

## Goal

Replace the appliance-style, A/B, ephemeral-root direction for Nanoserver-01 and Miniserver-01/02/03 with a conventional NixOS system using ZFS datasets, postponing appliance-style boot/update work until a later stage. Use ZFS for straightforward filesystem and state management, drawing on Graham Christensen's “Erase Your Darlings” approach where it is useful.

Reference: <https://grahamc.com/blog/erase-your-darlings/>

## User decision

- ZFS is the preferred storage direction because its ergonomics are better for this use than tmpfs, Bcachefs, or Btrfs.
- The appliance-style work is deferred, not declared permanently abandoned.
- Scope is Nanoserver-01 and Miniserver-01, -02, and -03.

## Context and constraints

- The existing implementation and plans assume an image-based appliance, A/B UKIs/store payloads, ephemeral roots, Btrfs, and a custom update path. See `docs/plans/nanoserver-01-store-ab-ephemeral-multihost.md`, `docs/plans/nanoserver-miniserver-platform.md`, and `docs/plans/miniserver-install-readiness.md`.
- Current miniserver profiles opt into `appliance` and `appliance-disko` through `hosts/miniserver-configurations.nix`; the Nanoserver profiles and versioned appliance configurations are under `hosts/nanoserver-01/`.
- The repository worktree already has extensive unrelated staged/unstaged/untracked changes. Preserve all of it; do not reset, stage, commit, or push it as part of this pivot without explicit approval.
- Miniserver-01's live boot outcome is unknown after a kexec attempt; its display went black and SSH timed out. Do not reboot it, send keys, format disks, or otherwise operate it without explicit authorization. This plan is not an authorization for physical changes.
- Existing device paths, IDs, and destructive-install assumptions must be revalidated. Do not reuse Btrfs UUIDs as ZFS pool identity or assume `/dev/nvme*` numbering.

## Proposed storage model (to validate before implementation)

- Use ordinary NixOS boot and switching; no appliance profile, immutable users, custom A/B slot selection, versioned store bundle, or appliance updater in the initial ZFS system.
- Use a ZFS pool and datasets with clearly separated disposable OS state and deliberately persistent state. A possible layout is a blank-snapshot root dataset rolled back during initrd device setup, plus datasets for `/nix` and selected persistent data. Do not finalize dataset names, mountpoints, pool topology, or rollback command placement until the boot ordering and host-specific hardware are verified.
- Keep `/boot` on an EFI-compatible filesystem separate from the ZFS pool.
- Apply the Erase Your Darlings principle selectively: identify exactly which root state is disposable and which paths (identity, secrets, service data, user data) must persist. Prefer datasets/mounts with explicit ownership over broad symlink conventions where practical.
- Choose pool redundancy per host based on verified device inventory and resilience requirements; do not assume the four hosts share the same storage layout.
- Address ZFS-on-NixOS requirements explicitly: supported kernel/module combination, initrd availability and import ordering, pool cache/configuration, bootloader/EFI arrangement, and any required `boot.zfs` settings. Test actual locked nixpkgs behavior before relying on remembered option names.

## Non-goals

- Do not physically install, repartition, format, import, destroy, or roll back pools on any host in this planning task.
- Do not change live systems, reboot Miniserver-01, or access its console.
- Do not implement Kubernetes, new workloads, host virtualization, or the deferred appliance update pipeline.
- Do not delete existing appliance code, tests, release artifacts, or rollback documentation during the first ZFS migration. Retire or archive them only after the conventional systems are validated and the user approves cleanup.
- Do not modify encrypted secrets or keys.

## Scope and blast radius

Likely future changes include host configuration wiring, storage feature modules and Disko layouts, Nanoserver/miniserver profiles, initrd and boot configuration, tests, installation/runbook docs, and the existing appliance plans. The current plan only records the architectural pivot; it does not yet alter those configurations.

## Steps

1. **Inventory and freeze existing state.** Record repo status, staged diff, host definitions, device topology, current boot/deployment state, existing tests and deployment gates. Do not alter the dirty worktree or operate hosts. Verification: `git status --short`, `git diff --cached --stat`, and review `git diff --stat`.
2. **Resolve architecture questions.** Decide per host which devices form the pool and redundancy, boot/EFI arrangement, dataset layout, what is erased on boot, what persists, swap policy, and whether `/nix` is a separate dataset. Resolve Nanoserver's current deployment status and Miniserver-01's safe recovery status before any rollout. Verification: document the decisions and review against live read-only inventory; no destructive commands.
3. **Prototype ZFS on disposable systems.** Implement a narrowly scoped ZFS profile and Disko definition without replacing the production profiles. Test pool creation/import, NixOS boot, generation switching/rollback, blank-root rollback if chosen, persistent state, and recovery in disposable QEMU. Verification: dedicated evaluation and QEMU checks, including reboot and failed-boot recovery.
4. **Migrate profiles incrementally.** After the prototype gates pass, wire Nanoserver-01 first, then miniserver profiles one at a time, retaining existing appliance configurations/artifacts until each conventional profile has passed its gates. Re-check each host's stable device identities and backup/recovery readiness immediately before any authorized destructive install. Verification: per-host config evaluation/build and disposable-layout tests.
5. **Update operational documentation and defer appliance work.** Mark old appliance plans as deferred/superseded only after the new implementation is validated; keep their design history and recovery information. Verification: docs link/reference checks and `git diff --check`.

## Verification gates

- Nix evaluation/build for each host with ZFS enabled and no appliance/A-B feature accidentally active.
- Disposable Disko/QEMU tests for pool topology, boot, initrd import, root rollback (if selected), persistence, generation switching, and recovery.
- Confirm secrets, SSH host identity, machine identity, and service/user data survive as intended; confirm disposable OS state is actually reset if using Erase Your Darlings.
- Run the repository's local check gate and `git diff --check` after implementation. Exact check names/commands must be selected after inspecting the current flake and test harness; do not treat historical Btrfs/appliance checks as validation of ZFS.
- Physical deployment remains a separate explicitly authorized operation with a live target inventory and tested recovery path.

## Rollback

Keep existing appliance configurations, code, tests, and artifacts intact during the transition. If the ZFS prototype fails, stop before physical installation and retain the existing configuration for later review; do not attempt an in-place pool conversion. Recover by restoring the prior boot media/configuration only through a separately planned and authorized procedure.

## Open decisions — do not guess

- Does the user want the Erase Your Darlings blank-root rollback on every host, or conventional persistent ZFS root with snapshots and selective persistence?
- Per-host pool topology: mirror, single-disk pool, or another layout, including the exact device allocation and boot-device arrangement.
- Which paths/data are persistent, their backup/replication policy, and whether `/nix` is separate.
- Swap and hibernation policy.
- Nanoserver-01 current physical and deployment state; Miniserver-01 current state and whether/when recovery is authorized.
- Whether the current uncommitted appliance work is to remain as a fallback during migration (recommended) or be retired after successful validation.

### For Executor

Read order: this plan; `docs/plans/nanoserver-01-store-ab-ephemeral-multihost.md`; `docs/plans/nanoserver-miniserver-platform.md`; `docs/plans/miniserver-install-readiness.md`; host configurations and storage modules; current `flake.nix`, `checks.nix`, and relevant tests.

Assumed working state: the nix-config worktree contains extensive pre-existing user changes. Preserve them; inspect staged and unstaged diffs before any edit or commit. No physical operations are authorized by this plan.

Owned files: initially this plan only. Future implementation ownership must be agreed after architecture decisions.

Verification commands: planning-only; no code gate applies. For implementation, first identify the current repository gate from `flake.nix`/`checks.nix`, then run per-host evaluations, ZFS QEMU tests, full local gate, and `git diff --check`.
