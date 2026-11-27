# Nanoserver stage-only GitOps updates

## Goal

Automatically stage the newest signed Nanoserver software version alongside the currently running version; preserve the running version for rollback, replace an older staged version when a newer one arrives, and leave reboot entirely manual.

## Slot terminology

A/B here means **software versions**, not physical USB/ESP slots. The running version is active; the next version is staged. If staged B boots successfully, B becomes active and the prior version's capacity is reused for the next staged update. Physical USBs remain mirrored Btrfs members, and matching slot-specific UKIs continue to be installed on both ESPs.

## Non-goals

- No live-host update, reboot, disk operation, release publication, or PR merge.
- No automatic reboot or change to the user's manual reboot policy.
- No changes to v2/v3 published asset names or contents.
- No Nix CLI/daemon on the appliance.
- No K3s/GitOps cluster work or workload-Nix runtime work.
- No physical USB/ESP transfer redesign; both physical boot paths retain their versioned UKIs.
- Do not change the release publisher from manual without separate authorization; this plan covers host polling/staging once an approved immutable release exists.

## Context and evidence

- `hosts/features/opt-in/appliance/sysupdate.nix` currently defines four transfers: the shared versioned Btrfs store, registration metadata, and UKIs for both ESP A and ESP B in every slot profile. The UKI transfer source pattern is explicitly slot-specific (`...-slot-a.efi` or `...-slot-b.efi`).
- Each profile has a build-time `config.appliance.rootSlot`; `/nix/store` and `/run/nanoserver-rootpool` use the corresponding Btrfs mirror member. Both members belong to the mirrored filesystem, so versioned store subvolumes are shared.
- The current `appliance-update <version>` script checks both mirror members, both ESP mounts, `/persist`, and the Btrfs mirror health; runs `systemd-sysupdate --component=nanoserver update <version>`; checks the store and registration; then calls `bootctl set-oneshot` on the *active* ESP. It prompts for confirmation and does not reboot.
- NixOS's `systemd.sysupdate` module enables the daily timer, but the upstream service invokes the default component. The transfer files are under `/etc/systemd/sysupdate.nanoserver.d`, so the generic service fails with “No transfer definitions found.”
- `systemd-sysupdate` 259 documents `check-new` as printing the newest candidate version and returning nonzero when there is no candidate. A local fixture confirmed `list --json=short` reports the newest installed version in `current` and all available/installed versions in `all`; use a successful listing to distinguish “no candidate” from network/signature/configuration errors.
- `ProtectVersion=%A` resolves to the running `IMAGE_VERSION`; `InstancesMax=2` retains the running version plus one staged version. A newer release replaces the previous staged version while preserving the running one. After reboot into the staged version, `%A` resolves to that newly running version and protects it during the next update.
- `systemd-sysupdate.reboot.enable` is already false. Existing UKI boot-counting and `systemd-bless-boot` support health-based fallback.
- User-confirmed policy (Seed `nix-config-4ae7`, Mulch decision, Engram #1580): A/B means software versions. A is running, B is staged; newer releases replace B. After B boots successfully it becomes active and the next update stages into the other version. Reboot remains manual.

## Blast radius

- `hosts/features/opt-in/appliance/sysupdate.nix`: add a noninteractive latest-version mode to the guarded updater and configure the daily systemd service to use it.
- `tests/nanoserver-slot-uki.nix`: assert active-version protection, two-version retention, component-specific service invocation, no automatic reboot, and unchanged physical per-slot UKI transfer behavior.
- `docs/APPLIANCE-UPDATES.md`: distinguish automatic stage-only polling from manual reboot and from the manual break-glass command.
- `docs/plans/nanoserver-miniserver-platform.md`: align the update workflow and rollback policy.
- No release workflow or published artifacts are changed in this implementation.

## Steps

1. **Add automatic discovery to the guarded updater.** Preserve `appliance-update <version>` and its confirmation prompt. Add `appliance-update --latest` for the systemd timer: run `systemd-sysupdate --component=nanoserver check-new`; validate a returned positive numeric version newer than the running version. If no candidate is returned, use `list --json=short` to confirm the signed source is reachable and the newest available version is already installed; treat listing/network/signature errors or an uninstalled candidate as visible failures, not “nothing to do.”
2. **Reuse fail-closed staging checks.** Both modes require root, identify the running software version and physical boot slot, verify the running profile's slot identity, require both mirrored root members and matching filesystem UUIDs, a non-degraded Btrfs pool, both ESPs, and `/persist`, and stage the exact selected version. Verify the versioned store, registration, and matching UKIs on both ESPs; sync; then set the one-shot entry on the currently active physical ESP. Automatic mode skips only interactive confirmation. It must never invoke reboot.
3. **Connect the daily timer.** Override the upstream `systemd-sysupdate.service` `ExecStart` to call `appliance-update --latest`. Use a one-shot service type suitable for the wrapper while preserving upstream hardening and existing `/persist` ordering. Keep `systemd.sysupdate.reboot.enable = false`.
4. **Prove repeated staging and operator behavior.** Extend `tests/nanoserver-slot-uki.nix` to check `ProtectVersion=%A` and `InstancesMax=2` on store/registration/UKI transfers; both physical slot-specific UKIs remain configured; component-specific candidate discovery/update; timer uses the wrapper; and no automatic reboot is configured. Add focused checks for candidate/no-candidate/error handling and absence of a reboot command without weakening production absolute-path safety.
5. **Document operations.** Update `docs/APPLIANCE-UPDATES.md` with poll cadence, what “staged” means, manual reboot, how to inspect running/pending versions, boot-count fallback, and manual break-glass usage. Mark release publication as separately controlled and do not imply an unapproved release exists.

## Tests and verification

- Nix evaluation check: `nix build -L .#checks.x86_64-linux.nanoserver-slot-uki` (or the repository's equivalent check attribute).
- Host config evaluation: evaluate `nanoserver-01-update-v3-a` and `nanoserver-01-update-v3-b`; inspect generated transfer files and `systemd-sysupdate.service` unit text.
- Build the relevant Nanoserver host-platform check and run repository formatting/diff checks using the commands in `AGENTS.md`.
- Inspect the generated updater script for `check-new`, JSON list fallback, numeric validation, mirror/ESP preflight, both physical UKIs, active-ESP one-shot selection, and absence of a reboot command.
- Confirm the daily timer remains enabled and `systemd-sysupdate-reboot.timer` remains disabled.
- Do not claim real hardware behavior verified: actual automatic polling/staging and boot-count fallback require a later explicitly authorized Nanoserver rollout.

## Rollback

Revert the `sysupdate.nix`, test, and documentation changes together. Until validated, keep the generic timer from invoking the updater and retain the existing manual command. Never modify or remove published v2/v3 assets as part of rollback.

## Open questions / guardrails

- Do not infer that a successful update selected the intended software version. Verify the store, registration, and matching UKIs on both physical ESPs before setting one-shot on the currently active ESP.
- A no-candidate result is a successful no-op only after a successful signed-manifest listing; network, signature, and transfer errors must remain visible and must not arm a boot target.
- Confirm exact generated service drop-in semantics by evaluating the NixOS unit, not only by reading the source assignment.
- Existing v4+ signature verification is outside this change; preserve the current signed-manifest trust path and do not bypass it.
- Release automation remains manual pending separate explicit authorization; do not publish or deploy as part of this work.

### For Executor

Read order:
1. This plan.
2. `hosts/features/opt-in/appliance/sysupdate.nix`.
3. `hosts/features/opt-in/appliance/boot.nix` and `rootfs.nix`.
4. `tests/nanoserver-slot-uki.nix` and `docs/APPLIANCE-UPDATES.md`.
5. Seed `nix-config-4ae7` and Mulch architecture record.

Assumed working state: branch `feat/nanoserver-miniserver-platform`; PR #7 open; do not merge, publish, or touch a host.

Owned files: `hosts/features/opt-in/appliance/sysupdate.nix`, `tests/nanoserver-slot-uki.nix`, `docs/APPLIANCE-UPDATES.md`, `docs/plans/nanoserver-miniserver-platform.md`, and this plan.

Verification commands: focused Nix check, both slot profile evaluations, relevant host-platform check, formatter, `git diff --check`, then review generated transfer and service unit text.
