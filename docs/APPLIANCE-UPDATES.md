# Appliance Updates

CI builds the existing Nanoserver bundle and candidate versioned bundle for validation. Publication is a separate manual `workflow_dispatch` on `main`, after CI passes. The publisher signs a `SHA256SUMS` manifest and creates a GitHub Release tagged `appliance-release-<commit-sha>`. Existing v2/v3 release assets are neither rebuilt nor copied into the new release. The repository is public, so appliances download release assets without a GitHub token. Publication is skipped until its signing secret is configured.

## One-time signing setup

The appliance trusts the public OpenPGP key at `hosts/features/opt-in/appliance/update-signing-key.gpg`. The matching private key is never stored in Git. Configure the GitHub Actions repository secret from a secured copy of the private export:

```sh
gh secret set APPLIANCE_UPDATE_SIGNING_KEY \
  < ~/.local/share/nix-config/appliance-update-signing/signing-key.asc
```

The export is unencrypted and must be treated as a CI signing credential. Keep it in an encrypted offline backup after configuring the secret, then remove unsecured working copies. The workflow accepts only the matching public-key fingerprint. Rotate keys by first installing both old and new public keys in the appliance trust keyring, then changing the CI secret and removing the old key only after all appliances have received the new trust configuration.

`CACHIX_AUTH_TOKEN` is also used by the existing CI setup to accelerate Nix builds. It is not used by appliances.

## Publish a release

After CI succeeds on `main`, an operator dispatches the publisher for that exact commit. It is currently allowlisted to `nanoserver-01-update-v4-bundle`; it does not publish the default v3 bundle or historical rollback assets. It creates a binary-mode SHA-256 manifest, signs it with the CI key, and publishes the v4 payload files. The release becomes the `latest` release used by appliances, and its manifest lists only that new version's assets. Historical releases remain available in GitHub Release history. The workflow rejects any payload filename already present in a release, so a new image version must use new versioned filenames. Release tags are commit-specific and must not be reused.

The initial published release contained the Nanoserver v2 bundle and verified the publishing path, but it was not a newer update for a host already running v2. Release `appliance-release-b6931964ed72274e6f25110095e41f46698d1d4e` contains the signed v3 bundle. It was deployed to `nanoserver-01` after explicit authorization; software version v3 is active and v2 remains installed for rollback.

## Poll, stage, and activate

The currently deployed v3 host's generic `systemd-sysupdate.service` fails with “No transfer definitions found.” The component-specific stage-only service is part of the pending v4 configuration and is not active on the host until an approved v4 release is installed. Until then, use the guarded manual command below.

In the updated configuration, the daily timer runs `appliance-update --latest`. It checks the signed `nanoserver` component for a newer version, validates the mirrored root and mounts, stages the exact version, verifies the store, registration, and UKIs on both physical ESPs, then sets a one-shot entry on the currently active ESP. It never reboots. `ProtectVersion=%A` and `InstancesMax=2` keep the running software version and one staged version; newer releases replace the staged version. After rebooting successfully into B, B becomes the running version and the next update replaces the other version. The user initiates reboot manually.

Inspect the running and available/staged versions and the polling service with:

```sh
grep -E '^(IMAGE_ID|IMAGE_VERSION)=' /etc/os-release
grep -o 'nanoserver.version=[0-9]*' /proc/cmdline
systemd-sysupdate --component=nanoserver list
systemctl status systemd-sysupdate.timer
journalctl -u systemd-sysupdate.service
```

The listing shows installed and available versions; compare it with `IMAGE_VERSION` or the kernel command line to identify a staged version. If staging fails, the service logs the failure and does not arm a boot target.

For the operator-controlled break-glass path, stage a specific version with confirmation:

```sh
sudo appliance-update <new-version>
```

This performs the same fail-closed checks and one-shot selection but prompts before staging. Reboot separately when ready. Keep the running version available until the new boot passes its health gate; UKI boot counting and `systemd-bless-boot` provide fallback.

CI and release publication do not themselves deploy or activate an update. The v4 transfer definitions omit unsupported systemd-sysupdate `Verify=` keys; signed-manifest verification remains enabled through the configured keyring. Keep each published per-host numeric version immutable. Release publication remains a separate manual operation; staging and rebooting are separate, and reboot remains manual.
