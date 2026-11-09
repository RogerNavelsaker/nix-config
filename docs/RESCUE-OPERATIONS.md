# Rescue Installation Operations

Use the repository Devenv shell for repeatable commands:

```fish
devenv shell -- fish
```

## Host identity and secrets

Use the central `nix-ops` command from `nix-repos`; it dispatches into each owning repo's Devenv. `nix-ops install <host> <user@target>` stages the selected pass entry through the user-controlled YubiKey flow, installs, then cleans the stage directory. Staged extra files go under `/persist/etc/ssh/` so appliance impermanence can link the stable identity into `/etc/ssh` during activation. The key is never printed or stored in the repo or `/nix/store`.

The encrypted auth key remains in `nix-secrets`; use `secret-status` or `sops filestatus` for metadata-only checks. Never print or pass the Tailnet key as a command argument.

## Miniserver physical installation status

The user explicitly authorized physical installation of the Miniserver appliances on 2026-11-09. Disposable-QEMU bootstrap install/activation, SOPS identity, final appliance staging/boot, and `./scripts/local-gate.sh` passed. Fresh read-only miniserver-01 inspection matched its four configured stable by-path targets to the four whole disks and found no Ventoy device. Its target filesystems have been unmounted to satisfy the installer guard; no disk contents were changed. The guarded `nix-ops install` attempt stopped during host-identity staging with `gpg: public key decryption failed: Timeout`; NixOS Anywhere/Disko did not start and the exact `WIPE` prompt was not reached. Resolve pass/YubiKey decryption before retrying. No destructive disk writes have occurred under this authorization.

Before operating on each host, use a fresh rescue session to confirm host identity and enumerate all live whole disks, stable by-path targets, sizes, and mounts. Match the live configured Disko target set exactly; exclude the Ventoy device and stop on any ambiguity or mismatch. Use the guarded `nix-ops install <host> rona@<current-rescue-endpoint>` workflow, which selects the Miniserver bootstrap configuration, checks the live targets and root-capable SSH, and requires the exact `WIPE <host>` confirmation. Never substitute remembered `/dev/nvme*` or `/dev/sd*` names or reuse an old inventory as pre-install proof. Install one host at a time and verify the installed appliance boots and recovery access works before moving to the next host.

**Miniserver-01 exception:** a prior destructive installation attempt repartitioned its target disks but failed during activation; the host is not verified as installed or booted. A fresh read-only assessment from rescue-4b9b3c1fba confirmed the four configured target paths resolve to two 500,107,862,016-byte NVMe disks and two 64,160,400,896-byte USB disks; no Ventoy device was visible. The persistence and USB-root Btrfs filesystem reports listed both expected members; the USB-root mount was nevertheless marked degraded. The existing system closure is present but lacks `bin/switch-to-configuration`; `/mnt/etc/ssh/ssh_host_ed25519_key` is empty, while the persisted key is mode 0600 and 411 bytes. Target filesystems are currently unmounted. A guarded install attempt stopped before NixOS Anywhere/Disko because pass/YubiKey identity staging timed out; resolve key access first. Do not assume disks are blank or a successful install occurred.

## Destructive install gate

Run from an interactive terminal in `nix-repos`, after reviewing the target:

```fish
devenv shell -- nix-ops install nanoserver-01 rona@rescue-4f8e903d48
```

The script compares NixOS Disko devices with live whole disks, reports sizes/filesystems without serials, refuses mounted or extra/missing disks, requires root-capable SSH before kexec/Disko, and asks for the exact `WIPE nanoserver-01` confirmation. It uses NixOS Anywhere 1.13.0 with `--no-use-machine-substituters --extra-files`; it never uses `--copy-host-keys`.

Root SSH to the rescue endpoint was verified before this install. Do not bypass the script's live-device/root checks or alter Tailnet ACLs from the script.

The combined `nix-ops install` command cleans its staged identity after N-A exits. The original attempt formatted the target and failed activation because the key was injected at `/etc/ssh`; staging and `sops.age.sshKeyPaths` now use `/persist/etc/ssh`. The corrected closure was deployed as `system-2-link`, and activation imported the persistent SOPS age key. A one-run `/run` patch bypassed N-A's `ssh-copy-id` loop over Tailscale SSH; install-only stopped at missing `switch-to-configuration`, intentionally disabled by the appliance configuration. These were rescue-install observations; the rescue environment has since been left after the authorized appliance update.

As of 2026-10-06, `nanoserver-01` is reachable on v3, slot A. The v2 image remains installed for rollback. The v3 command `appliance-update` is available, `systemd-sysupdate.timer` is active, and the system is running with no failed units. The latest release manifest was fetched and its GPG signature verified by systemd. Systemd 259 logs that the source `Verify=` keys are unknown and ignores them, but still verifies `SHA256SUMS.gpg` using the configured public keyring. Remove those unsupported keys before the next image-version bump; preserve v3 artifact immutability. See [Appliance Updates](APPLIANCE-UPDATES.md).

The Nanoserver auth key is single-use; reserve it for the intended host's first boot. Do not use it in a disposable VM.

## Next safe steps

1. Keep v2 installed as rollback while v3 is health-checked. Confirm the systemd boot counter marks v3 successful before considering cleanup.
2. Before publishing a future image change, remove the unsupported `Verify=` keys, retain the public keyring, and increment the per-host numeric image version. Do not replace content under an already-published version.
3. Let the signed-source timer stage future versions; require explicit authorization for boot selection and reboot.
4. Only after v3 and recovery access remain stable, consider local Nix-store garbage collection. Never delete store paths manually; inspect GC roots first.

The QEMU-only sysupdate tests were removed intentionally; production A/B configuration and slot-UKI evaluation remain. Reintroduce focused automated update/recovery coverage before changing those behaviors.
