# Appliance Updates

Appliance update bundles are built from Nix flake package outputs named `*-update-bundle`. After the `CI & Cache Build` workflow succeeds for a push to `main`, `Publish appliance update` builds every such bundle from that exact commit, merges the versioned files into one release manifest, signs `SHA256SUMS`, and publishes a GitHub Release tagged `appliance-release-<commit-sha>`. The repository is public, so appliances download release assets without a GitHub token. The release workflow skips publication until its signing secret is configured; after setting it, dispatch that workflow on `main` to publish the current commit.

## One-time signing setup

The appliance trusts the public OpenPGP key at `hosts/features/opt-in/appliance/update-signing-key.gpg`. The matching private key is never stored in Git. Configure the GitHub Actions repository secret from a secured copy of the private export:

```sh
gh secret set APPLIANCE_UPDATE_SIGNING_KEY \
  < ~/.local/share/nix-config/appliance-update-signing/signing-key.asc
```

The export is unencrypted and must be treated as a CI signing credential. Keep it in an encrypted offline backup after configuring the secret, then remove unsecured working copies. The workflow accepts only the matching public-key fingerprint. Rotate keys by first installing both old and new public keys in the appliance trust keyring, then changing the CI secret and removing the old key only after all appliances have received the new trust configuration.

`CACHIX_AUTH_TOKEN` is also used by the existing CI setup to accelerate Nix builds. It is not used by appliances.

## Publish a release

Every successful push to `main` triggers publication from the exact tested commit. The workflow validates the flake, discovers all `*-update-bundle` package outputs, builds and combines them, creates a binary-mode SHA-256 manifest, signs it with the CI key, and publishes the signed manifest and payload files. The release becomes the `latest` release used by appliances. A workflow-dispatch run on `main` can publish the current commit after the signing secret is configured. Release tags are commit-specific and must not be reused. Bundle filenames must be unique across appliance hosts; version numbers are carried in each filename and are independently selected by each host's `MatchPattern`.

The initial published release contained the Nanoserver v2 bundle and verified the publishing path, but it is not a newer update for a host already running v2. Current source now defines a v3 bundle with the generic updater and signed remote source. CI will publish it after the version-3 slot check and bundle build pass. The running host still needs an authorized update before it gains the new command and polling configuration.

## Poll, stage, and activate

With the appliance configuration deployed, `systemd-sysupdate.timer` checks the latest release daily (with a randomized delay) and stages newer matching resources. Remote files are checked against `SHA256SUMS`; `SHA256SUMS.gpg` is verified using `/etc/systemd/import-pubring.gpg`. The transfer set includes the store tarball, its registration metadata, and both slot-specific UKIs. Transfers protect the running version and retain the two most recent instances. Polling does not automatically reboot.

To explicitly select a staged version for the next boot, run:

```sh
sudo appliance-update <new-version>
```

The command rechecks the mirrored root devices and mounts, requests confirmation, runs `systemd-sysupdate` for the requested version, and sets a one-shot boot entry on the currently active ESP. Reboot separately during an approved window. Keep the previous version available until the new boot passes its health gate; boot counting and the other slot provide the recovery path.

The live Nanoserver must not be changed as part of CI verification. Publishing an artifact does not deploy the new NixOS configuration; deploying polling or activating an update still requires explicit authorization.
