# Graft per-service systemd secret delivery plan

## Goal

Extend Graft so a flakelet-managed systemd service can fetch its declared OpenBao secrets once at each service start, stage them as protected runtime files, and expose them to the application through systemd credentials, while keeping the current `graft run -- COMMAND` environment-injection path and leaving a persistent broker/refresh agent as a future-compatible option.

## Decisions

- First implementation is **per-service oneshot rendering at service start**; no shared broker or persistent secret refresher in this milestone.
- `graft --env PROFILE.VARIABLE run -- COMMAND [ARGS...]` selects a profile-specific variable; bare `--env VARIABLE` selects only a profile-independent variable. Repeated `--env` flags select multiple variables. Long-running children keep the launch-time environment snapshot; Graft/Agent remains alive for the child lifetime, but no secret-change restart is enabled by default.
- Add a systemd-oriented file-render operation for configured secret names/destinations. Files are materialized at service startup; systemd loads them into the service credential directory. Refresh and restart-on-change are deferred/non-default.
- Never place secret values in Nix settings, the Nix store, generated unit contents, command arguments, or logs.
- Keep Graft, Caddy, and Lego as independently supervised systemd services even if a flakelet update coordinates their generation.
- Design config/request boundaries so a future broker can implement the same render/run contract without changing workload declarations; do not build broker protocol or daemon now.

## Implementation progress — 2026-10-30

- Implemented the `run` selector slice locally: repeatable profile-qualified or unprofiled `--env` flags resolve only exact configured mappings; malformed, duplicate, unknown, profile-ambiguous, and duplicate-target selections fail before starting OpenBao Agent. Agent HCL contains only selected templates and sets `restart_on_secret_changes = "never"`.
- With no `--env`, Graft directly launches the command without reading Agent HCL or contacting OpenBao; mapped secret-variable names and Bao/Vault override variables are removed from the inherited environment.
- Nix stores only non-secret mapping metadata in a root-readable generated JSON file and keeps the base Agent HCL free of secret templates. Go tests, vet, race tests, Nix parsing, and formatter check pass.
- This is a partial implementation milestone: file-render/oneshot systemd delivery, token revocation behavior, module/host evaluation, and deployment remain outstanding. No host was activated or changed.

### Latest follow-up — per-service systemd secret rendering (2026-10-30; local only)

This supersedes the earlier partial-implementation status above. The Graft render command and the Nix module's per-service oneshot renderer/consumer units are implemented locally. The renderer stages credentials privately, atomically publishes mode-0400 files, revokes its captured Agent token before reporting success, and fails closed on render or revocation errors. The consumer declares systemd LoadCredential and depends on the renderer; no secret values enter Nix configuration or generated unit contents.

Verification passed: Go tests, vet, race tests; Nix formatting for the module and VM test; and the registered NixOS VM test. The VM test uses a fake OpenBao Agent and harmless fixture value, launches a mock Podman container through NixOS virtualisation.oci-containers, and starts a one-shot systemd user unit invoking graft --env test.TOKEN run -- .... The container successfully reads its read-only systemd LoadCredential mount; the user-mode child receives the harmless canary and writes only a marker, and a fake-backend marker confirms Graft called the token-revoke command. The test also verifies denial to other local users, rerender on consumer restart, and startup blocked after render failure. This validates mock user-manager invocation, not a live user/clanker identity or OpenBao authorization; it is not production container support, and Flakelet is not used. The test harness writes its render counter before publishing readiness markers because Graft may terminate the Agent immediately after readiness. The isolated Rowan standalone flake also evaluated and built its full system toplevel using the local module input override (candidate output: /nix/store/qnnr8jb4pzc9vfj0asxrniqw7l4x2rzz-nixos-system-agent-rowan-lxc-26.05.20261015.26f4107). No live OpenBao request, deployment, or activation was performed. The VM test's inherited ACME units emit irrelevant setup failures because the test does not create ACME challenge infrastructure.

## Non-goals

- Deploying or activating the change on Rowan, Alex, or another agent.
- Changing OpenBao policies, certificates, ACME behavior, Caddy/Lego units, or agent identities.
- Implementing a persistent broker, file watcher, secret refresh loop, automatic service restart on rotation, or container integration.
- Generalizing fleet-wide startup timeout values; Rowan's existing 60-second `graft run` timeout is a canary setting.
- Storing secret values as Nix options/settings or exposing them through flakelet exports.

## Context and evidence checked

- Repository: `/workspace/RogerNavelsaker/nix-config`, branch `feat/nanoserver-miniserver-platform`; one working tree. The checkout has extensive unrelated staged/unstaged/untracked/intent-to-add work (72 dirty paths at planning time, no staged diff). Preserve it; do not reset, stage, or broadly format the repo.
- Repo instructions: `/workspace/RogerNavelsaker/nix-config/AGENTS.md`; no deeper `AGENTS.md` found under the touched module paths.
- Existing Graft implementation at planning time: `hosts/features/opt-in/openbao-client/openbao-secrets/main.go`, `main_test.go`, `go.mod`. The local implementation progress above now records explicit `run` selectors and selected-only templates; the systemd file-render operation remains unimplemented. Startup still has a 60-second bound/readiness marker and signal forwarding.
- Existing Nix integration: `hosts/features/opt-in/openbao-client/openbao-client.nix` defines `services.openBaoClient.openBao.secrets` as `PROFILE.VARIABLE` or unprofiled `VARIABLE` selectors mapped to `{ path, field }`, and packages Graft. The local implementation now keeps those templates out of base Agent HCL and adds only runtime-selected templates. Rowan's config currently has a canary env mapping; Alex enables the client but has no secret mapping. Host configs are already dirty; only change them if required by the implementation contract and preserve all existing edits.
- Current call-site search found Graft usage/config only in the module, its Go tests, Rowan canary config, and the existing integration plan. A separate unreferenced Python prototype exists at `hosts/features/opt-in/pi-openbao-client-launcher.py`; do not change it in this milestone.
- Flakelet's service interface supports systemd service settings and `LoadCredential`-style unit options; its docs warn that settings enter the Nix store, so only non-secret names/paths/modes may be passed. systemd credentials are acquired at service activation, exposed under `$CREDENTIALS_DIRECTORY`, and immutable during a running service. Target docs: https://github.com/Mic92/flakelet/blob/main/docs/guides/writing-a-service.md#secrets and https://systemd.io/CREDENTIALS/.
- User chose NixOS `virtualisation.oci-containers` for container workloads; container delivery is outside this initial native systemd service milestone.

## Intended interface and security contract

- Preserve argv-safe `graft run -- COMMAND [ARGS...]`; add repeatable `--env PROFILE.VARIABLE` selectors, with bare `--env VARIABLE` allowed only for variables with no profile assignment. Omitting `--env` injects no configured secrets; explicit selection is required and acts as an allowlist bounded by mappings configured for and authorized to this Graft identity. Reserve `.` as the profile/variable separator; require variable names to match the portable environment-name pattern `[A-Za-z_][A-Za-z0-9_]*`, and forbid `.` in profile names. Reject empty, malformed, duplicate, and unknown selections. Generate Agent config only for selected mappings, so unselected secrets are neither fetched nor exposed. The child receives only selected secret values (plus unrelated inherited environment, subject to existing credential-override filtering). Infisical uses its own `--env` to select a project environment (e.g. dev/prod); Graft must document its distinct selector semantics and must not copy Infisical-style implicit secret injection.
- Add a distinct `graft render` (or equivalent clearly named non-daemon subcommand) that selects configured file outputs and writes secrets only to explicitly configured destinations. Do not make the user-provided `env:owner:group:mode:path` string a privileged arbitrary write/chown API. Prefer typed Nix declarations (secret name, credential name, source path, owner/group, mode) compiled into non-secret command arguments/config; validate paths, names, modes, owners/groups, and parent-directory policy at the trust boundary.
- Secrets are rendered through OpenBao Agent into a private temporary/runtime staging directory, then installed atomically (same filesystem, restrictive temporary mode, rename) into the service-specific runtime source directory. A failed fetch/write must not publish a partial or stale credential as a successful start. Never log values.
- Let each flakelet service declare its own companion systemd oneshot renderer and application unit/dependency. The renderer authenticates, renders, and exits. The main unit uses `LoadCredential=` to load the staged source into its private `$CREDENTIALS_DIRECTORY`; verify systemd ordering and repeated service restarts so rendering runs on each start. Ensure failed rendering blocks app start and cleanup removes staging files after stop/failure, without deleting systemd's already-loaded credential copy prematurely. The host module supplies Graft/OpenBao client support; workload secret names/output policy remain in trusted service declarations.
- Authorization is granted per variable + profile pair, not per variable across all profiles or per profile as a blanket grant. Profile-independent variables have a distinct unprofiled grant. Selecting a pair requests it; it never grants access. Enforce these grants with OpenBao policies generated per workload from its exact grants; Graft selection is not the authorization boundary. For systemd, the host/vessel identity is used by the system manager, while the user/clanker identity is used by that user manager; units within each manager share that manager-scope identity. Thus OpenBao authorizes at host/vessel or user/clanker scope, not per unit. Keep output mapping separate from OpenBao path authorization: only trusted declarative service configuration chooses mappings. Avoid exposing a general root broker/socket or broad host identity in this milestone. If the implementation cannot safely restrict per-service mappings with the existing shared host role, stop and report that limitation rather than claiming workload isolation.
- Token cleanup: attempt `bao token revoke -self` (or equivalent supported Agent cleanup) on graceful Agent shutdown, without replacing the original child exit status; document token expiry as crash/offline fallback. Verify behavior in tests before relying on it. Existing live test showed a sink-backed token remained usable after Agent exit, so do not assume shutdown revokes it.
- Rotation behavior: fetch latest values on each service start only. Running services retain systemd credential snapshots and env values until restart. Persistent refresh/restart remains a later opt-in design.

## Blast radius

Expected owned files for implementation:

1. `hosts/features/opt-in/openbao-client/openbao-secrets/main.go` — CLI parsing, selected env generation, file rendering, safe filesystem operations, process/token cleanup.
2. `hosts/features/opt-in/openbao-client/openbao-secrets/main_test.go` — parser, allowlist, atomic/private file output, owner/mode/path validation, failure cleanup, signal/exit/token behavior.
3. `hosts/features/opt-in/openbao-client/openbao-client.nix` — typed secret-file declarations, Agent templates and packaged CLI config/units or helper options; retain existing ACME/OpenBao behavior.
4. A focused NixOS VM test under `tests/` plus registration in `checks.nix` only if it can reliably test the systemd ordering/LoadCredential contract without live credentials/network. Otherwise document a local generated-unit/systemd test and leave live auth as a separate canary.
5. `docs/plans/pi-openbao-smallstep-integration.md` — update Graft capabilities/status only after checks pass; preserve historical status and avoid unrelated integration-plan cleanup.

Do not change `flake.lock`, host identities, Rowan/Alex deployment config, or system activation unless evaluation proves an exact necessary change and it is separately reviewed. Do not stage or commit.

## Implementation steps and verification gates

1. **Lock down CLI/config contract.** Add tests first for profile-qualified and bare `--env` selectors, `render` selection, invalid names/separators, unknown/duplicate/malformed selections, and unchanged `run --` argv/help/exit behavior. Make Agent HCL generation disable secret-change restarts for default one-shot invocation. Verify: `devenv shell -- sh -c 'cd hosts/features/opt-in/openbao-client/openbao-secrets && go test ./... -count=1'`.
2. **Add secure file rendering.** Implement minimal typed file-output configuration and atomic writes with restrictive permissions; ownership/group changes must be validated and applied only with explicitly authorized privilege. Add tests for mode, output bytes using harmless fixtures, replacement semantics, path/symlink rejection, no partial files on failure, and cleanup. Verify Go tests, `go vet`, and race tests inside the repo devenv.
3. **Wire per-service systemd oneshot + credentials.** Extend the Nix module to emit non-secret config and a narrowly scoped renderer unit; define required/after ordering, runtime staging location, `LoadCredential`, and cleanup. Keep secret values out of derivations/unit text. Add assertions for unsafe file declarations and eval checks proving generated units contain no secret value. Verify `nixfmt --check`, module evaluation, and NixOS VM/systemd test for render-before-start, credential readability by the service only, failed-render blocking, and repeat render on service restart.
4. **Retain env `run` behavior.** Test selection delivers only configured requested names; for long-running children Graft stays alive, does not rewrite the process environment, and does not restart on secret updates by default. Test graceful signal/exit cleanup and token revocation with a fake or isolated backend; never print test secrets.
5. **Review and record.** Inspect the exact diff and status; run focused tests/builds only. Update the integration plan with verified behavior and limitations. Confirm no unrelated files changed and no staging/deployment occurred.

## Verification commands

- `devenv shell -- sh -c 'cd hosts/features/opt-in/openbao-client/openbao-secrets && go test ./... -count=1 && go vet ./... && go test -race ./...'`
- `nixfmt --check hosts/features/opt-in/openbao-client/openbao-client.nix tests/<new-focused-test>.nix checks.nix` (only files actually changed)
- `nix build --option eval-cache false .#checks.x86_64-linux.<focused-check> -L` (if a focused check is registered)
- Evaluate Rowan's candidate config from a temporary staged copy if needed; do not activate it. Preserve its current generation and do not run remote/service commands.
- `git diff --check` and targeted `git status --short`; ensure no staged diff was introduced.

## Rollback

Keep the implementation behind opt-in `services.openBaoClient.openBao` configuration and avoid activating hosts. If tests fail, revert only the exact newly introduced lines/files from this implementation, preserving pre-existing worktree changes. Do not use `git checkout`, `reset`, `clean`, or stash. Runtime render output is confined to `/run` and should be removed by unit cleanup; no deployment rollback is part of this plan.

## Open questions — resolve during implementation, do not guess

1. Confirm the systemd oneshot model can re-run on every main-service start with the selected `Requires/After` and `LoadCredential` ordering; prove it in a VM test before depending on it.
2. Decide the minimal declarative file mapping schema, including whether owner/group are names resolved at evaluation or runtime, and whether the first milestone supports only root-owned sources plus systemd credential copies. Prefer no arbitrary caller-supplied chown. Preserve the least-privilege default: no `--env` selection means inject nothing; explicit selection is required and remains bounded by configured mappings and the workload authorization policy.
3. Determine whether OpenBao Agent can revoke its cert-auth token on shutdown without a token sink. Test against an isolated harmless test identity/backend; if not, document TTL fallback and decide whether a private token sink is acceptable.
4. Confirm whether file-render mode should accept a service-local selection list only or reuse configured `--secretfile` entries. Keep the contract stable for a future broker but do not implement the broker.

### For Executor

Read order:
1. `AGENTS.md`
2. This plan
3. `hosts/features/opt-in/openbao-client/openbao-secrets/main.go` and `main_test.go`
4. `hosts/features/opt-in/openbao-client/openbao-client.nix`
5. `checks.nix`, relevant existing NixOS VM tests, and the current integration plan

Assumed working state: the existing checkout is intentionally dirty; preserve all staged, unstaged, untracked, and intent-to-add work. No deployment is authorized by this plan.

Owned files: only the scoped implementation files listed under Blast radius; do not edit host rollout files or the legacy Python prototype without a justified, separately reviewed need.

Verification commands: use the focused commands above; report any VM-test/systemd limitations rather than substituting an unverified claim.
