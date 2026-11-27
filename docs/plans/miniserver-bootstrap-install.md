# Miniserver temporary bootstrap installation

## Goal

Use a temporary, switch-enabled NixOS bootstrap configuration for the NixOS Anywhere install phase, then stage and boot the final image-based appliance on the same disposable target. The final appliance remains non-switchable and has no runtime Nix; `/persist` must contain the staged host key before any SOPS activation that needs it.

## Non-goals

- No physical Disko, NixOS Anywhere, activation, or reboot operations on hardware; disposable-QEMU install, activation, and reboot operations are in scope.
- No commits or pushes; preserve all existing staged, unstaged, intent-to-add, and untracked work.
- Do not alter Nanoserver, the Ventoy disk, `nix-secrets`, or `nix-keys`.
- Do not enable switching or runtime Nix in the final appliance.
- Do not put real host private keys in the Nix store, image archive, UKI, logs, or repository.

## Context and evidence

- `scripts/install-rescue-host.fish` currently validates the staged Miniserver identity and live Disko targets, then invokes NixOS Anywhere against `.#$host` with `--extra-files`.
- The final appliance profile disables `system.switch`; the installed final closure therefore lacks `bin/switch-to-configuration`, while NixOS Anywhere's install phase expects it to install the bootloader.
- `hosts/features/opt-in/appliance/image.nix` builds a store tarball and closure-registration metadata. `hosts/features/opt-in/appliance/boot.nix` configures two ESPs and a peer UKI. The Disko layout provides a read-only versioned store subvolume and persistent `/persist`.
- The previous installation failed during SOPS activation before bootloader installation. The Miniserver SOPS key path now points directly to `/persist/etc/ssh/ssh_host_ed25519_key`; the mount/staging/activation boundary still needs a faithful disposable-QEMU test.
- The worktree is extensively dirty and includes unrelated user work. No files outside the task scope may be reset or normalized.

## Design contract

1. The bootstrap is a distinct NixOS configuration for each Miniserver host. It shares the host's machine identity, Disko devices, and safe `/persist` key path, but has a distinct bootstrap store namespace/version, a writable bootstrap store, `nix.enable = true`, and `system.switch.enable = true`.
2. The regular appliance configurations remain unchanged in their no-switch/no-runtime-Nix behavior and are the only systems selected for the final boot.
3. NixOS Anywhere installs the bootstrap configuration using its ordinary install phase. The root-shaped staged host key is copied to `/persist/etc/ssh/ssh_host_ed25519_key` before activation, with mode 0600 and without logging key material.
4. A guarded second stage stages the final appliance store archive and registration metadata, writes the matching slot-A and slot-B UKIs to their respective ESPs, and selects the final appliance UKI. The bootstrap must not be selected as the final default.
5. End-to-end disposable QEMU evidence must cover the exact install/activation boundary, `/persist` availability, SOPS decryption using a disposable test identity, both ESPs/slot UKIs, and a successful first appliance boot. Physical work is outside this QEMU validation plan; the user subsequently authorized physical Miniserver installation, subject to the fresh per-host checks and miniserver-01 recovery assessment in `miniserver-install-readiness.md` and `RESCUE-OPERATIONS.md`.

## Blast radius

- Host configuration wiring for `miniserver-01`, `miniserver-02`, and `miniserver-03`.
- A task-owned bootstrap feature/module and the rescue installation entry point.
- Miniserver evaluation/QEMU checks and `checks.nix`.
- `docs/plans/miniserver-install-readiness.md` and `docs/RESCUE-OPERATIONS.md`.
- No changes to shared nix-lib or user-managed secrets.

## Steps

1. **Trace bootstrap compatibility.** Inspect the locked NixOS `image-based-appliance` module and NixOS Anywhere 1.13.0 install-phase behavior. The locked profile uses ordinary-priority `nix.enable = false` and `system.switch.enable = false`, so define explicit bootstrap overrides for both and a separate writable store namespace while keeping the final profile read-only. Confirm the bootstrap's `/persist` mount is active at the SOPS activation boundary. Record the exact generated switch-to-configuration and bootloader-install artifacts. Verify with targeted `nix eval` and a bootstrap toplevel build.
2. **Add failing bootstrap evaluation coverage.** Add a test asserting each bootstrap toplevel contains `bin/switch-to-configuration`, uses a bootstrap-only store version, and leaves the final appliance's switch disabled. Run it and confirm failure before adding the bootstrap configurations.
3. **Add bootstrap profiles.** Define the temporary switch-enabled config and its peer/slot outputs without changing final appliance profiles. Ensure NixOS Anywhere uses the bootstrap flake attribute while retaining the validated disk identity, no-mounted-target, root-SSH, interactive wipe confirmation, and `/persist` key-staging guards. Verify all three profile evaluations and their distinct Disko/store configuration.
4. **Add image staging after bootstrap install.** Implement a second-stage operation that takes only local build outputs for the final store tarball, registration, and slot UKIs; transfers them without secrets; creates/populates the final versioned Btrfs store subvolume; installs the UKIs on the matching ESPs; and selects the final appliance for the first boot. Validate paths, hashes, free space, mounts, and both ESP identities before writes. Exercise only against disposable images.


**Validation and operator status:** The disposable-QEMU `miniserver-bootstrap-install` check and pre-install `./scripts/local-gate.sh` passed. The user explicitly authorized physical installation on 2026-11-09 and entered the exact `WIPE miniserver-01` confirmation after fresh live checks. NixOS Anywhere ran Disko and installation but failed during bootloader activation: chroot could not run `/nix/var/nix/profiles/system/activate` or `/nix/var/nix/profiles/system/sw/bin/bash`. The target's `system-2-link` points to the expected bootstrap toplevel, but 632 of 736 closure paths are missing from `/mnt/nix/store`, including Bash and system-path dependencies. The rescue ISO is still running and target filesystems are mounted read-write; the host is not a verified installed boot. No further writes, reboot, or installation retry until the incomplete store-transfer/mount behavior is diagnosed and recovery is reviewed. The tracked readiness and rescue docs record this failure; this plan remains pre-existing untracked work.
5. **Prove the full boundary in QEMU.** Use disposable virtual disks and a disposable SSH host key/SOPS fixture. Run the same NixOS Anywhere bootstrap installation and second-stage image staging as production, then boot the final appliance. Assert the key is present only under `/persist` before first SOPS activation, the secret decrypts, both slot UKIs are present on their intended ESPs, `/` is ephemeral, `/nix/store` is the final read-only versioned subvolume, and the bootstrap is not selected. Run the test before considering any physical install.
6. **Document and verify.** Update the rescue operator flow and readiness plan with the two-stage process, explicit non-reboot/authorization gates, and test evidence. Run the targeted QEMU/evaluation checks, repository local gate, formatting/syntax checks, and diff review. Do not run a physical operation or commit/push.

## Verification gates

- Bootstrap evaluation check fails before implementation and passes afterwards for all three hosts.
- Final appliance still evaluates with `system.switch.enable = false` and runtime Nix disabled.
- The bootstrap toplevel contains `bin/switch-to-configuration`; the final appliance toplevel does not.
- Disposable NixOS Anywhere install and second-stage staging pass on virtual disks only.
- First final-appliance boot succeeds with SOPS decrypting via the persisted disposable test key; both ESPs and slot UKIs are validated.
- Run `scripts/local-gate.sh`, relevant QEMU checks, and `git diff --check`; preserve and report the pre-existing dirty worktree.
- No physical install, commit, or push is part of this task.

## Rollback

Keep the existing final appliance profiles and rescue install path intact until the bootstrap and QEMU gates pass. If bootstrap or image staging fails, revert only the task-owned bootstrap/module/test/script/documentation changes. Do not reset or clean any other worktree path and do not touch physical media.

## Open questions to resolve during step 1

- Does the locked appliance module set `system.switch.enable` with a force priority, or can a bootstrap module safely override it?
- Does NixOS Anywhere's install phase mount `/persist` before running the activation script with `--extra-files` in the target root? Confirm from the pinned implementation and the disposable test, not assumption.
- What exact writable mount arrangement does the bootstrap use for its temporary store, and how will the final versioned store remain separate?
- What exact bootloader/UKI selection method is reliable across both ESPs and the target's firmware? Confirm with OVMF before documenting physical expectations.

### For Executor

Read order: this plan; `AGENTS.md`; `scripts/install-rescue-host.fish`; Miniserver configuration wiring; `hosts/features/opt-in/appliance/{image,boot,rootfs,persistence}.nix`; `hosts/features/opt-in/appliance-disko/disk-layout.nix`; `tests/miniserver-disko-layout.nix`; `checks.nix`; NixOS Anywhere 1.13.0 and locked nixpkgs module sources.

Assumed working state: branch `feat/miniserver-install-readiness`, prior commit `d8f17364680c14e2a10041385375ca777b0a7ad2`; worktree extensively dirty. Preserve everything outside task-owned changes. No physical writes, commits, or pushes.

Owned files: new Miniserver bootstrap configuration/module, rescue install script, task-specific tests/check wiring, and the two Miniserver installation docs named above. Avoid editing pre-existing unrelated work.

Verification commands: run targeted `nix eval`/`nix build` for bootstrap and final profiles; run the new bootstrap evaluation and full disposable-QEMU install/activation test; run `scripts/local-gate.sh` and `git diff --check`. Never run the physical installer during verification.
