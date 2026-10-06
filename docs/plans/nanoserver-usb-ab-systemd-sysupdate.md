# Nanoserver USB A/B OS and NVMe storage installation

> **Superseded:** This records the earlier whole-root A/B design for hostname `nanoserver`. The current store-A/B/ephemeral-root direction and `nanoserver-01` identity are tracked in [nanoserver-01-store-ab-ephemeral-multihost.md](nanoserver-01-store-ab-ephemeral-multihost.md); do not execute this historical plan.

## Goal
Install the `nanoserver` NixOS appliance with nixos-anywhere/Disko/nixos-facter, mirror its Btrfs root across the two 64 GB USBs, keep A/B OS versions as versioned root subvolumes managed by systemd-sysupdate, and keep persistent service data on a separate two-device NVMe Btrfs RAID1.

## User decisions and safety constraints
- Historical canonical installed host name was `nanoserver`; the current host profile is `nanoserver-01`.
- The two 64 GB USB devices and two 1 TB NVMe devices were used for a Proxmox install; the user explicitly authorized destroying that old installation/data.
- The separate 4 TB Ventoy drive is installer/recovery media and is never a target.
- User approved a Btrfs RAID1 root filesystem spanning both USB root partitions. Each USB retains its own ESP and can boot the shared root in degraded mode if the other USB is absent; the USBs are mirror members, not independent OS copies. A/B refers to versioned root subvolumes, not one operating system per USB. No RAID0.
- User chose no LUKS and no Secure Boot; do not add either. TPM auto-unlock is not in the design; normal reboot should be unattended.
- The host, user, and deploy SSH keys are already stored in `nix-keys` and accessed with `pass` plus a YubiKey. Use `PASSWORD_STORE_DIR=/home/rona/Repositories/RogerNavelsaker/nix-keys/private pass show hosts/nanoserver/ssh_host_ed25519_key` only with stdout redirected to a RAM-backed mode-0600 staging file; never display the result. Do not duplicate keys in `nix-secrets`. Keep the host key at `/etc/ssh/ssh_host_ed25519_key` in every root subvolume, never in the Nix store or root tar/UKI. For initial install, pass the RAM-backed tree to nixos-anywhere `--extra-files`; do not use `--copy-host-keys`, which copies the rescue identity. The updater copies the active key into each new root subvolume.
- No commits or pushes. Preserve unrelated dirty worktree changes and encrypted nix-secrets contents.
- Do not start physical formatting until QEMU tests pass and the four target devices have been re-identified by stable IDs immediately before the command. Abort if Ventoy or any unexpected disk appears.

## Read-only inventory already completed
- Target `rescue-4f8e903d48` is reachable over Tailscale SSH and runs RAM-backed NixOS `26.05.20260318.b40629e`, systemd 259, Linux 6.18.18. Hardware: Win Element M6, Intel N200 (4 cores), Intel iwlwifi WLAN, Intel igc Ethernet.
- `nixos-facter` 0.4.3 report was generated as root-only `/run/nanoserver-facter.json` (0600, RAM). Raw disk records include serials; never check in or evaluate the raw report. For final install, regenerate with nixos-facter to a RAM-only file, sanitize before using it in the flake/Nix store, and retain only the sanitized report.
- Ventoy is a separate 4 TB, three-partition USB, mounted at `/iso` during rescue.
- The two OS USBs are Samsung Flash Drive FIT 59.8 GB devices, each with a single unmounted F2FS partition from the old Proxmox installation.
- The two CT1000P3PSSD8 1 TB NVMe devices currently form one unmounted Btrfs filesystem. Both partitions share UUID `f6ffa8ca-91c6-4e6b-9b95-a0339abd79a5`; DATA, METADATA, and SYSTEM chunks are RAID1; about 3.8 GiB is currently used. This old filesystem may be destroyed per user authorization and recreated as a clean RAID1.
- `nix-config/flake.nix` already defines `nanoserver` and includes disko. `hosts/nanoserver/default.nix` is a placeholder (label-based ext4 and `initialPassword = "changeme"`); replace it rather than deploy it.
- Nix-lib's `mkSystems` imports `hosts/<hostname>/default.nix`; target config can be kept modular there.

## Intended design
- Each USB has its own EFI system partition and one Btrfs root-member partition. Disko creates a single Btrfs filesystem across both USB root members with DATA, METADATA, and SYSTEM profiles all RAID1. Mount by the stable Btrfs filesystem UUID with `degraded` enabled so either USB can boot alone.
- Root A/B versions are versioned Btrfs subvolumes in that shared filesystem (for example `nanoserver-root_1`, `nanoserver-root_2`). Both ESPs carry the same versioned UKIs; each UKI selects its matching root subvolume via `rootflags=subvol=...` and the shared Btrfs filesystem UUID.
- systemd-sysupdate uses a local `.tar.xz` source to create a Btrfs subvolume target and regular-file UKI transfers to both ESPs. Keep at least two versions so a failed new boot can fall back to the previous root subvolume/UKI. QEMU has validated the real NixOS root tar, v2 UKI transfer to both ESPs, stable-key copy, UEFI one-shot selection, Nanoserver v2 root boot, and systemd-bless-boot success with both root members present.
- Initial install uses nixos-anywhere and Disko. Generate hardware facts with nixos-facter into RAM and sanitize before Nix evaluation. Retrieve `hosts/nanoserver/ssh_host_ed25519_key` from `nix-keys` with pass/YubiKey only when preparing installation; redirect it directly into a RAM-backed mode-0600 `--extra-files` tree, outside the Nix store. The updater copies that same key into the newly created root subvolume before staging its UKI.
- Keep the separate NVMe Btrfs RAID1 for persistent service data, with `data=raid1`, `metadata=raid1`, and `system=raid1`. Use distinct stable filesystem UUIDs for USB root and NVMe data; both pools should mount degraded when one member is absent.
- Use the standard NixOS kernel initially; no LUKS or Secure Boot. Make updates operator-triggered from locally built, integrity-checked artifacts; do not enable an automatic update timer in the first release.
- This design reduces root fault isolation: Btrfs filesystem metadata is shared across both USBs. Versioned subvolumes protect against a bad OS update, not filesystem-wide corruption. Document degraded boot and USB replacement/resync procedures.

## Scope / owned files
- `flake.nix` — keep existing inputs/outputs and register the `nanoserver` modules without overwriting unrelated dirty edits.
- `hosts/nanoserver/default.nix` plus focused modules for hardware/facter, Btrfs data, boot/update, and disk layout.
- `docs/` — document one-time install, update, A/B rollback, and the physical disk mapping.
- Do not modify `nix-secrets` or the rescue ISO unless new host secrets are explicitly required and user-managed.

## Steps
1. **Confirm implementation interfaces.** Inspect pinned Disko multi-device Btrfs/subvolume behavior, systemd-sysupdate tar-to-subvolume and UKI transfers, NixOS UKI/root-fstab generation, and systemd-boot boot counting. Use Disko for installation partitions; sysupdate does not repartition the mirrored root.
2. **Create modular NixOS host config.** Replace the placeholder `nanoserver` config; remove `changeme`; use the sanitized Facter report as appropriate; define the NVMe Btrfs RAID1; declare the two USB slots by stable `/dev/disk/by-id` paths; add secure access and a data mountpoint.
3. **Build the update artifacts.** Build a complete root tarball from the NixOS toplevel closure with a writable `/etc`, plus a matching versioned UKI whose initrd fstab selects the same root subvolume. Package both with SHA256SUMS and systemd-sysupdate tar-to-subvolume/UKI transfers. Keep automatic timers disabled.
4. **QEMU proof before physical writes.** A Disko VM test passes the mirrored USB-root layout and boots a generic NixOS system from its Btrfs root subvolume. A UEFI VM test passes the actual Nanoserver v2 root tar/UKI through production sysupdate definitions, copies a test host key into the new subvolume, updates both ESPs, sets the one-shot UKI, boots the Nanoserver v2 root, and observes systemd-bless-boot mark it good. After removing an identified virtual root member, the remaining pool mounts degraded and the updater refuses further updates. Still test a fresh initrd boot with one root member absent, booting from both USB ESPs, and fallback from a failed candidate.
5. **Build and review.** Run Nix parse/eval/build with `--no-write-lock-file`; inspect the root tar, checksum manifest, and UKI command line plus initrd fstab for matching root UUID/subvolume; run Disko/systemd tools only against QEMU files; inspect `git diff` and `git diff --check`; confirm unrelated dirty files and lockfiles remain unchanged.
6. **Physical install.** Immediately before nixos-anywhere/Disko, re-identify exactly the two Samsung USBs and two NVMe devices by stable IDs and sizes; do not include the 4 TB Ventoy disk. Regenerate hardware facts with nixos-facter into RAM, sanitize before evaluation, and use nixos-anywhere over Tailscale SSH with the Disko layout. Inject the user's stable SSH key using `--extra-files` from RAM-backed 0600 staging; do not use `--copy-host-keys`. Install the initial root subvolume and verify both USB ESPs and the NVMe data mirror without overwriting the installer.
7. **Physical verification.** Test booting from each USB ESP alone with degraded Btrfs root, update/rollback between subvolumes, NVMe mirror mount, SSH identity stability, and documented member replacement/resync. Record actual results; no unattended updates until this passes.

## Verification gates
- Static evaluation: `nanoserver` includes two USB Btrfs RAID1 members, versioned root subvolumes, two ESP mounts, and the NVMe data mirror; stable UUIDs are used for both Btrfs pools; no `/dev/sdX` paths or insecure initial password.
- Build: host toplevel, root tarball, versioned UKIs, update bundle/checksums, Disko script, and sysupdate transfer definitions build without lockfile changes or embedded SSH private key.
- Virtual: Disko mirrored-root VM test, actual Nanoserver tar/UKI update, stable-key copy, both ESPs, EFI one-shot entry, single-member degraded mount/update refusal, then actual UKI boot from each USB and failed-boot fallback—all using QEMU files.
- Physical: all four by-id paths and sizes are rechecked before formatting; the 4 TB Ventoy disk must not appear in any destructive target list.

## Rollback
- Keep the 4 TB Ventoy rescue installer untouched and bootable.
- Never delete the currently running root subvolume until the new root has booted and passed its health gate; systemd-sysupdate must retain at least the active and candidate versions.
- If an update fails while Btrfs metadata remains healthy, boot the previous versioned subvolume from either USB ESP or the Ventoy rescue ISO. If a USB member fails, boot degraded from the remaining member and follow the documented Btrfs replacement/resync procedure.

## Remaining design decisions
- Root-storage semantics are approved: a single Btrfs RAID1 filesystem across both USB root members; A/B versions are subvolumes. Remaining work is to produce a complete NixOS root tar, prove degraded initrd boot from either member, verify boot-count fallback, and define replacement/resync recovery. No physical install until these QEMU gates pass.
- Initial host-key provisioning is assigned to nixos-anywhere `--extra-files` from RAM-backed staging; test and retain the updater's copy of that same key into each new root subvolume. The user accepts no LUKS/Secure Boot; the key is plaintext on both mirror members and can unlock host SOPS secrets if the media is read.
- Choose persistent data mountpoint and Btrfs subvolume names (suggested `/srv` with service-specific subvolumes).
- Decide whether each slot has its own independently installed systemd-boot entry in UEFI NVRAM or relies on firmware removable-media fallback; test this on the actual Win Element M6 firmware.
- Determine sysupdate artifact source and how per-slot UKIs are signed/verified.

## Execution plan for approved mirrored-root/subvolume design

### Goal
Boot the same Btrfs RAID1 root from either USB member in degraded mode; update and roll back NixOS versions using versioned Btrfs root subvolumes and matching UKIs.

### Non-goals
- Do not keep two independent OS roots, or convert USBs to RAID0.
- Do not touch the physical target devices before the full QEMU gate.
- Do not add LUKS, Secure Boot, a nonstandard kernel, or external Btrfs modules.
- Do not place the SSH host key or other plaintext secrets in a Nix store path, root tarball, or UKI.
- Do not modify encrypted `nix-secrets` or unrelated dirty files.

### Context and blast radius
- `systemd-sysupdate` partition targets need at least two matching partition slots; this is why the previous single-root-partition-per-USB design failed.
- A generic QEMU prototype already passed Btrfs RAID1 Data/Metadata/System profiles, systemd-sysupdate tar-to-subvolume updates for two versions, and degraded mount after removing one virtual member.
- The actual NixOS root tar, initrd degraded mount, UKI root-subvolume arguments, systemd-boot success/rollback, and nixos-anywhere/Disko layout remain unproven.
- Changes affect `hosts/nanoserver/{devices,disk-layout,image,boot,persistence,sysupdate}.nix`, `flake.nix`, QEMU tests, `checks.nix`, and this plan. The two physical USBs become members of one root filesystem; filesystem-wide corruption can affect both.

### Steps and tests
1. **Declare mirrored filesystems** — `devices.nix`, `disk-layout.nix`, and `persistence.nix`: give the USB-root and NVMe-data Btrfs pools stable filesystem UUIDs; create one ESP plus one root-member partition on each USB; create root Btrfs with data/metadata/system RAID1 and a version-1 root subvolume; mount the top-level root pool for sysupdate; mount both Btrfs pools by filesystem UUID with `degraded`. Verify evaluated Disko devices and mount options, then run a Disko QEMU test that checks both device profiles and missing-member mount.
2. **Build a real NixOS root tar** — `image.nix` (or a focused `rootfs.nix`): use the NixOS system tarball builder with the full toplevel closure; create writable runtime directories (especially `/etc`) and exclude all host secrets. Add a versioned subvolume mount/root command line and a UKI with `root=UUID=<root-pool>` plus `rootflags=degraded,subvol=nanoserver-root_<version>`. Build and inspect the tar and UKI; confirm the SSH host key is absent.
3. **Configure boot** — `boot.nix` and `hardware.nix`: mount both independent ESPs, install removable-media systemd-boot fallback on each, include USB/Btrfs initrd modules, and ensure root UUID/subvolume parameters reach each UKI. Add QEMU checks for kernel command line and degraded initrd discovery.
4. **Configure operator updates** — `sysupdate.nix`: use a `Type=tar` source to `Type=subvolume` target rooted at the Btrfs top-level mount, `InstancesMax=2`, and `ProtectVersion=%A`; add matching UKI regular-file transfers to both ESPs with boot-attempt suffixes. Keep automatic timers disabled. The updater validates bundle hashes, refuses the active version and a degraded/missing-member pool, invokes sysupdate without repartitioning the shared root, copies the stable SSH key from the running root into the new subvolume, syncs, then sets the one-shot UKI. Test successful v1→v2 update, active-version refusal, incomplete/mismatched bundle refusal, key persistence, and interrupted update behavior.
5. **Generate update bundle** — `flake.nix`: build the root tar and matching UKI for a new version and a SHA256 manifest. Avoid duplicated slot-specific root artifacts: each version has one root subvolume tar and one UKI copied to both ESPs. Verify every listed hash.
6. **Boot and rollback QEMU proof** — add a NixOS VM test using the actual Nanoserver system, two file-backed USB members, and two NVMe members. Exercise initial installation, boot from either ESP with the peer USB absent, successful boot marking, failed candidate fallback, and rollback to the preserved root subvolume. Run `nixos-anywhere --vm-test` against a QEMU-specific device override so the real Disko layout is tested without physical devices.
7. **Document and verify** — update the operator guide with install, update, degraded boot, rollback, and Btrfs replacement/resync commands. Run host/tar/UKI/update builds, both QEMU tests, `nix eval` checks, and `git diff --check`; inspect the diff and confirm no unrelated files or lockfiles changed.

### Rollback
If the mirrored-root integration or degraded boot fails in QEMU, keep the current modular host changes uninstalled and revert only the new root-storage/update edits. The rescue ISO and all physical disks remain untouched. Do not fall back silently to the obsolete single-partition sysupdate design.

### Open questions
- Root-pool UUID and exact subvolume naming convention; use deterministic values and keep version in the subvolume name.
- Tailscale auth-key provisioning is still absent from `nix-secrets`; keep tailnet auto-auth disabled until the user provides it.
- Test the target firmware's removable-media boot order and `bootctl set-oneshot` behavior with two ESPs.

### For Executor
Read order: this plan; `nix-config/AGENTS.md`; `flake.nix`; Nix-lib `mkSystems` builder; current Nanoserver modules; NixOS `make-system-tarball.nix`, UKI, and systemd-sysupdate modules; pinned Disko `lib/types/btrfs.nix` and test library; systemd `sysupdate.d` and boot-counting manuals.
Assumed working state: the user approved mirrored Btrfs USB root with A/B subvolumes; preserve all unrelated dirty changes and encrypted secrets; no physical writes.
Owned files: Nanoserver host modules, Nanoserver flake outputs, relevant VM tests/checks, and this plan only.
Verification commands: `nix build --no-write-lock-file .#nixosConfigurations.nanoserver.config.system.build.toplevel`; build root tar/UKI/update bundle; run the new QEMU Btrfs/sysupdate/Disko tests and `nixos-anywhere --vm-test`; inspect UKI root arguments and `git diff --check`. Physical install remains blocked until these gates pass.

Assumed working state: user authorized wiping the two Samsung 64 GB USBs and two 1 TB NVMe devices; preserve the separate 4 TB Ventoy drive and unrelated worktree edits. New device identities must be rechecked just before destructive commands.

Verification commands: Nix parse/eval/build with `--no-write-lock-file`; inspect generated `image.repart` outputs; run `systemd-repart --dry-run` and sysupdate on disposable QEMU images; no physical install before the virtual A/B/rollback gates pass.