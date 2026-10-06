# Rescue Installation Operations

Use the repository Devenv shell for repeatable commands:

```fish
devenv shell -- fish
```

## Host identity and secrets

Use the central `nix-ops` command from `nix-repos`; it dispatches into each owning repo's Devenv. `nix-ops install <host> <user@target>` stages the selected pass entry through the user-controlled YubiKey flow, installs, then cleans the stage directory. Staged extra files go under `/persist/etc/ssh/` so appliance impermanence can link the stable identity into `/etc/ssh` during activation. The key is never printed or stored in the repo or `/nix/store`.

The encrypted auth key remains in `nix-secrets`; use `secret-status` or `sops filestatus` for metadata-only checks. Never print or pass the Tailnet key as a command argument.

## Destructive install gate

Run from an interactive terminal in `nix-repos`, after reviewing the target:

```fish
devenv shell -- nix-ops install nanoserver-01 rona@rescue-4f8e903d48
```

The script compares NixOS Disko devices with live whole disks, reports sizes/filesystems without serials, refuses mounted or extra/missing disks, requires root-capable SSH before kexec/Disko, and asks for the exact `WIPE nanoserver-01` confirmation. It uses NixOS Anywhere 1.13.0 with `--no-use-machine-substituters --extra-files`; it never uses `--copy-host-keys`.

Root SSH to the rescue endpoint was verified before this install. Do not bypass the script's live-device/root checks or alter Tailnet ACLs from the script.

The combined `nix-ops install` command cleans its staged identity after N-A exits. The original attempt formatted the target and failed activation because the key was injected at `/etc/ssh`; staging and `sops.age.sshKeyPaths` now use `/persist/etc/ssh`. The corrected closure is deployed as `system-2-link`, and activation imported the persistent SOPS age key. A one-run `/run` patch bypassed N-A's `ssh-copy-id` loop over Tailscale SSH; install-only stopped at missing `switch-to-configuration`, intentionally disabled by the appliance configuration. Both ESPs now contain their slot UKI and systemd-boot fallback; both slot init closures are present, with boot counting verified. Rescue remains active; no reboot occurred. Source configuration now stages signed GitHub Release updates daily through `systemd-sysupdate`; reboot remains operator-controlled. This configuration is not deployed to the live appliance until explicitly authorized. Set the `APPLIANCE_UPDATE_SIGNING_KEY` GitHub secret and verify that CI published a signed latest release before treating polling as operational; see [Appliance Updates](APPLIANCE-UPDATES.md).

The Nanoserver auth key is single-use; reserve it for the intended host's first boot. Do not use it in a disposable VM.

## Next safe steps

1. While rescue remains active, perform read-only checks of both USB ESPs and the NVMe `/persist` mount: confirm the expected slot UKIs/fallback entries, both slot init closures, and the persisted host identity. Do not rerun Disko or nixos-anywhere.
2. Decide and authorize the reboot window. Before reboot, confirm rescue access and the intended firmware boot target; retain a way to return to rescue if the appliance fails to boot.
3. On first appliance boot, verify the active slot, `/` as tmpfs, the intended read-only `/nix/store` subvolume, `/persist`, stable SSH host identity, and SOPS secret activation. Verify the published release and signed manifest before enabling the new polling configuration; do not deploy it to the live host without explicit authorization.
4. Only after successful boot and recovery access are verified, consider local Nix-store garbage collection. Never delete store paths manually; inspect GC roots first.

The QEMU-only sysupdate tests were removed intentionally; production A/B configuration and slot-UKI evaluation remain. Reintroduce focused automated update/recovery coverage before changing those behaviors.
