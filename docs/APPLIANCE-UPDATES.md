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

The initial published release contained the Nanoserver v2 bundle and verified the publishing path, but it was not a newer update for a host already running v2. Release `appliance-release-b6931964ed72274e6f25110095e41f46698d1d4e` contains the signed v3 bundle. It was deployed to `nanoserver-01` after explicit authorization; v3 slot A is active and v2 remains installed for rollback.

## Poll, stage, and activate

The running v3 host's generic `systemd-sysupdate.service` currently fails with “No transfer definitions found”; do not rely on its timer to stage this update. The explicit `nanoserver` component path can list versions and verify the signed manifest. Use the guarded `appliance-update <new-version>` wrapper below; it runs the component-specific updater, checks the mirrored root and mounts, and requires confirmation. No update is staged automatically.

To explicitly select a staged version for the next boot, run:

```sh
sudo appliance-update <new-version>
```

The command rechecks the mirrored root devices and mounts, requests confirmation, runs `systemd-sysupdate` for the requested version, and sets a one-shot boot entry on the currently active ESP. Reboot separately during an approved window. Keep the previous version available until the new boot passes its health gate; boot counting and the other slot provide the recovery path.

CI and release publication do not themselves deploy or activate an update. The v4 transfer definitions omit unsupported systemd-sysupdate `Verify=` keys; signed-manifest verification remains enabled through the configured keyring. Keep each published per-host numeric version immutable. Staging and rebooting are separate operations; reboot only after staging succeeds and within the approved rollout window.
