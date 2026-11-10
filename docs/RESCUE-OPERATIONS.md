# Rescue Installation Operations

Use the repository Devenv shell for repeatable commands:

```fish
devenv shell -- fish
```

## Host identity and secrets

Use the central `nix-ops` command from `nix-repos`; it dispatches into each owning repo's Devenv. `nix-ops install <host> <user@target>` stages the selected pass entry through the user-controlled YubiKey flow, installs, then cleans the stage directory. Staged extra files go under `/persist/etc/ssh/` so appliance impermanence can link the stable identity into `/etc/ssh` during activation. The key is never printed or stored in the repo or `/nix/store`.

The encrypted auth key remains in `nix-secrets`; use `secret-status` or `sops filestatus` for metadata-only checks. Never print or pass the Tailnet key as a command argument.

## Miniserver physical installation status

The user explicitly authorized physical installation of the Miniserver appliances on 2026-11-09. The latest guarded Miniserver-01 attempt accepted `WIPE miniserver-01`, ran Disko and reformatted the target, then failed during activation because the bootstrap `activate` and `sw/bin/bash` paths were missing. The user reports Ctrl+C did not stop the stalled `ssh-copy-id`; Ctrl+D was used, after which NixOS Anywhere continued. SSH-key upload success is unconfirmed. Latest read-only inspection found 0 of 736 expected closure paths in the fresh Btrfs store subvolume, while `/mnt/nix/var/nix/db/db.sqlite` retained old validity records from before Disko. In disposable QEMU, preserving the target DB while removing store payloads caused `nix copy` to leave all 738 closure paths absent; deleting the DB before retrying restored all 738/738 paths, and the full install/activation/final-boot test passed. This confirms the stale-DB mechanism in QEMU, not yet on the physical host. The guarded helper now separates kexec/Disko from install, validates the expected mounted bootstrap subvolume, and removes the stale DB before closure transfer. Do not reboot or make another physical write until the updated workflow is reviewed/published and the user authorizes a fresh guarded attempt.

Before operating on each host, use a fresh rescue session to confirm host identity and enumerate all live whole disks, stable by-path targets, sizes, and mounts. Match the live configured Disko target set exactly; exclude the Ventoy device and stop on any ambiguity or mismatch. Use the guarded `nix-ops install <host> rona@<current-rescue-endpoint>` workflow, which selects the Miniserver bootstrap configuration, checks the live targets and root-capable SSH, and requires the exact `WIPE <host>` confirmation. Never substitute remembered `/dev/nvme*` or `/dev/sd*` names or reuse an old inventory as pre-install proof. Install one host at a time and verify the installed appliance boots and recovery access works before moving to the next host.

**Miniserver-01 exception:** the host remains in rescue and is not installed or boot-verified. Its freshly created store subvolume had 0/736 closure paths while a stale Nix DB outside that subvolume still referenced the previous closure. Disposable QEMU reproduced the resulting skipped transfer and showed clearing the DB before copying restores the closure and permits a full test boot. The local guarded helper now performs that cleanup only after checking the expected Btrfs bootstrap subvolume, but it has not been exercised on the physical host. No reboot or further target write until the change is reviewed/published and a new attempt is explicitly authorized.

## Destructive install gate

Run from an interactive terminal in `nix-repos`, after reviewing the target:

```fish
devenv shell -- nix-ops install nanoserver-01 rona@rescue-4f8e903d48
```

The guarded installer compares NixOS Disko targets with live whole disks, refuses mounted or mismatched devices, requires root-capable SSH, and asks for the exact `WIPE <host>` confirmation. Its updated flow runs NixOS Anywhere 1.13.0 through `kexec,disko`, verifies the expected Btrfs bootstrap-store subvolume over SSH, clears `/mnt/nix/var/nix/db`, then runs `install,reboot` so closure transfer starts with a fresh validity database. It still uses `--extra-files` and never `--copy-host-keys`. Do not bypass the checks or treat the patch as permission to operate on a host; follow fresh inventory and explicit authorization gates.

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
