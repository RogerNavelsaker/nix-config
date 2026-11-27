# Nanoserver Herdr headless server

## Goal
Install a headless Herdr server in the Nanoserver v4 candidate and make its machine API reachable from the current Herdr client over the existing SSH path.

## Non-goals
- Do not install/deploy on a live host, publish a release, or reboot.
- Do not open a Herdr TCP listener or add a new SSH credential/port.
- Do not add Herdr to published v2/v3 artifacts or their configs.
- Do not add desktop packages or VS Code to `rona@nanoserver-01`.
- Do not alter `nix-secrets`, current Herdr client config, or unrelated dirty changes.

## Context
- The current local client is 0.9.3. Although current upstream nixpkgs exposes `herdr` 0.9.3, the repository's locked nixpkgs does not; it also lacks the Herdr flake's required `zig_0_16`. Pin the official Herdr flake at `v0.9.3`, retain its independently locked nixpkgs/Rust overlay build toolchain, and use `inputs.herdr.packages.${pkgs.system}.default`.
- Official Herdr docs describe saved machines as SSH connections; machine setup installs/starts a compatible remote server after confirmation. No TCP machine API is required.
- Herdr supports a headless `herdr server` process. The Nanoserver host configs use `passwordless-sudo`; running the server as `rona` therefore gives its remote panes root-equivalent command capability, protected by existing SSH authentication.
- `rona@nanoserver-01` currently evaluates to a separate, non-desktop HM profile; VS Code is not among its enabled features. The AIO HM profile is disabled.
- Nanoserver's root is tmpfs and its current system persistence does not preserve `rona`'s home. Herdr's `~/.config/herdr` state (including session snapshots and config) must be added to NixOS `/persist`; persisting the directory is safe because Herdr removes stale Unix sockets on startup.
- Nanoserver v4 is unpublished. Preserve v2/v3 and only add Herdr to the v4 A/B candidate.
- The current local Herdr client is 0.9.3 and has no saved machine profiles. Do not run remote setup before v4 deployment; no live deployment is authorized here.

## Blast radius
- Add one top-level opt-in NixOS feature for Herdr package, `rona` user linger, persistent Herdr state, and a boot-starting user service.
- Opt the v4 A/B Nanoserver configs into that feature; leave older variants unchanged.
- Add an evaluation/runtime service check and update host-platform docs with SSH-only access and privilege implications.
- Rebuild the unpublished v4 bundle; its filenames may remain v4 because the release is not published.

## Steps
1. Add a `herdr` flake input pinned to `github:herdrdev/herdr/v0.9.3`; keep the release's independently locked build toolchain because repository nixpkgs lacks `zig_0_16`. Update only the new input and its transitive dependencies in `flake.lock`.
2. Add `hosts/features/opt-in/herdr-server.nix`: install the pinned Herdr package, enable `users.users.rona.linger`, persist `.config/herdr` under `/persist`, and start `herdr server` from `systemd.user.services.herdr-server` under `default.target`, restarting only on failure. Use a Unix socket; add no network listener.
3. Add the `herdr-server` opt-in to `nanoserver-01-update-v4-a` and `-v4-b` only. Verify v3 stays without the service.
4. Add `tests/herdr-server.nix` as a NixOS VM smoke test: boot with linger and the user unit, assert the Herdr Unix socket exists, and query the running server through the CLI/API as `rona`.
5. Wire the test in `checks.nix`; extend `tests/host-platform.nix` assertions for v4 service/package/linger and v3 exclusion.
6. Document that client setup uses `herdr machine add <ssh-target> --label Nanoserver` after the v4 deployment, is SSH-transported, and grants command execution as `rona` (wheel/passwordless sudo). Do not run that setup or deploy.

## Verification
- Focused: `nix build --option eval-cache false --no-link .#checks.x86_64-linux.herdr-server -L`
- Host platform: `nix build --option eval-cache false --no-link .#checks.x86_64-linux.host-platform -L`
- Formatting and hygiene: `nix fmt -- --check` (or the repository's format check) and `git diff --check`.
- Candidate artifact: build `.#packages.x86_64-linux.nanoserver-01-update-v4-bundle`, verify `SHA256SUMS`, and run the 1.9 GB size guard.
- Full regression: `nix flake check --option eval-cache false -L`.

## Rollback
Remove the v4-only feature opt-ins and the new Herdr module/test/docs. Published v2/v3 assets remain untouched. No runtime rollback is performed because deployment is out of scope.

## Open questions
None for the off-host configuration. Assumption: Herdr runs as `rona` because the requested machine-management protocol must access the user's machine environment; this is root-equivalent through existing passwordless sudo. The user must separately authorize live deployment and local machine-profile registration.

### For Executor
Read order: this plan; `hosts/nanoserver-01/configurations.nix`; `hosts/features/opt-in/host-platform/default.nix`; `tests/host-platform.nix`; a minimal NixOS VM test; `checks.nix`; `docs/HOST-PLATFORM.md`.

Assumed working state: substantial unrelated dirty changes exist; preserve them. v4 is unpublished; v2/v3 artifacts are immutable.

Owned files: this plan; new Herdr opt-in module and VM test; Nanoserver v4 config; checks; host-platform docs.

Verification commands are listed above. Do not invoke `herdr machine add`, change a remote host, publish, or reboot.