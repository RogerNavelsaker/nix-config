# Generic OpenBao and Smallstep agent secrets integration

## User-approved scope

On 2026-10-28 the user authorized continuing the client and server setup, including an OpenBao mTLS endpoint at `openbao-mtls.naco.casa` behind Caddy TLS passthrough. Preserve the existing OpenBao API/UI route and its 8200/8201 listeners. The user clarified that HTTP-01 reachability must be tested only after the client Nix configuration (local Caddy, Lego, Step, OpenBao tooling) has been distributed and activated. The command-line secret runner must be generic and easy to use like Infisical, not coupled to Pi or LiteLLM.

## Goal

Give each agent a distinct Step-issued client certificate. Require and verify that certificate on a dedicated OpenBao TLS listener, then authorize only the matching agent's secrets. Provide a generic command wrapper:

```sh
graft run -- <command> [args...]
```

The Nix host profile declares which KV v2 fields become environment variables; the command runner itself accepts any command. Pi/LiteLLM is an optional consumer, not the runner's interface or a fixed secret path.

## Safety boundaries

- Never put secret values, client private keys, CA private keys, enrollment tokens, or OpenBao tokens in Nix, the Nix store, logs, command arguments, or normal Git files.
- Do not migrate or edit Pi auth files until generic secret injection and per-agent authorization pass end-to-end checks.
- Preserve the initialized OpenBao Raft data and unseal state. Keep 8200 and cluster port 8201 behavior unchanged; add a separate internal listener on 8202.
- Keep CA signing keys on the CA host. Do not edit nix-keys or nix-secrets.
- Before each live CA configuration change, make and verify a protected backup. The current Step CA config is mode 0600; the container mapping and file access were verified. Keep this boundary for future edits.
- Preserve pre-existing work in the nix-config and tailnet-gateway repositories. Do not stage or commit.

## Status update — 2026-10-29 (supersedes conflicting “Current evidence” statements below)

### Completed
- Removed the unused `pi-agent-bootstrap` JWK provisioner after verifying a protected backup. Step CA remains healthy with `agent-clients` and `openbao-server`; both ACME directories advertise usable public nonce URLs.
- Dependency checks found no `pi-agent-bootstrap` references in the searched local agent configuration and no active JWK client on agent-alex; offline agents were not inspected. Removing the provisioner does not revoke certificates already issued.
- Rowan’s canary client certificate is for the active identity `agent-rowan.wampus-cloud.ts.net`, with exact DNS SAN, ClientAuth EKU, and a valid chain to Step CA root fingerprint `43bb6340f33f75ba94342cf9b4578e270a4832e5d2f8e2b8672b35be967a6057`; it is valid through 2027-01-26. Do not infer an identity migration to `naco.casa`.
- Issued the OpenBao server certificate through `openbao-server` for `openbao-mtls.naco.casa`. It has the exact DNS SAN, ServerAuth EKU, and a verified chain to the same Step CA root; it is valid through 2027-01-27.
- Backed up the Lego ACME account/certificate state at `/home/alex/.local/share/agent-services/secure-backups/openbao-acme-20261029T002514Z` (directory 0700, archive/checksum 0600). The ACME account key is 0600. The server certificate and key were copied into OpenBao’s config directory as 0644 and 0600.
- Configured a daily Lego renewal service/timer. A manual run succeeded and correctly skipped renewal at 89 days remaining; the timer is enabled.
- Added the 8202 listener to `/home/alex/.local/share/agent-services/openbao/config/openbao.hcl` on disk, requiring and verifying Step CA client certificates, using the server certificate and root CA, and enabling TLS certificate auto-reload. The candidate validated on OpenBao 2.7.0 with only the pre-existing `disable_mlock` warning, but the running process has not loaded it. A SIGHUP kept the service healthy and unsealed but did not add the listener: port 8202 remains closed until a service restart.
- Enabled `auth/cert` and configured the exact Rowan role `agent-rowan` plus `agent-rowan-kv-read`. The role constrains both CN and DNS SAN to `agent-rowan.wampus-cloud.ts.net`, with 1h token TTL and 24h maximum. The KV v2 policy grants `read` only on `kv/data/agents/rowan` and descendants; a temporary capability-test token confirmed Rowan-path `read`, cross-agent `deny`, and metadata/list `deny`, then was revoked.
- The provided root admin token was read from its protected local file and used without logging or persisting its contents. Created one non-sensitive Rowan canary at `kv/data/agents/rowan/openbao-mtls-canary-20261029` (KV v2 version 1, create-only CAS); its value was neither logged nor read. Only Rowan currently has a configured cert-auth role.
- The host Caddyfile and `/home/alex/.local/share/agent-services/gateway/caddy-config/Caddyfile.openbao-final` have matching SHA-256; the container's read-only `/etc/caddy/Caddyfile` mount differs. Current validation of the candidate failed because `CLOUDFLARE_API_TOKEN` resolved to an empty value. No Caddy reload or restart was performed.

### Remaining at the initial 2026-10-29 status snapshot (superseded by follow-ups below)

- At this snapshot, Rowan end-to-end mTLS and Graft were not yet verified; the follow-ups below record later results.
- The authority-level SAN issuance policy remains unset; keep issuance limited to the approved canary identity.
- Other agent identities and client rollouts remain pending.

### Earlier follow-up — Rowan local `graft` injection milestone (2026-10-29)

This subsection supersedes earlier statements above that the 8202/Caddy route was inactive or Rowan mTLS and workload injection were untested.

- Later runtime checks confirmed the OpenBao 8202 listener and Caddy Layer4 passthrough active. The endpoint presented the expected server certificate and rejected clients without a certificate. Rowan certificate login and canary read succeeded; tested cross-agent data and metadata access were denied; temporary test tokens were revoked.
- The local Nix module now configures the OpenBao Agent `vault` stanza with Rowan's client certificate and key as well as server CA trust. Secret templates use direct `.Data.data.<field>` access and validate field names as Go-template identifiers; using `index` did not enforce `error_on_missing_key` for a missing field.
- A temporary `graft` binary and HCL generated from the local source were exercised against Rowan's live OpenBao endpoint. A harmless child received the mapped canary without printing it. A direct missing-field lookup failed before starting the child.
- A bounded 120-second unauthorized-path test used a temporary binary/config against `kv/data/agents/alex/graft-denied-probe`: external timeout returned 124, no child started or remained, and logs contained 18 lines matching 403/permission-denied, 9 retry lines, 116 lines / 5,331 bytes total. Agent was still retrying; exhaustion is unverified. Temporary artifacts were removed; no secret value was printed.
- Read-only Rowan review: `acme-renew-openbao-client-rowan.timer` is active daily; its last service run succeeded on 2026-10-29 06:03 UTC (success does not prove a certificate renewal occurred). Client files are owned by `acme:openbao-client-rowan-certs` (directory mode `0750`; fullchain/key `0640`), and `rowan` belongs to that group. The leaf certificate SAN is `agent-rowan.wampus-cloud.ts.net`, EKU is ClientAuth, and expiry is 2027-01-26. The installed OpenBao CA hash matches the checked-out CA file.
- The active Rowan HCL has client cert/key only under `auto_auth`, while the checked-out module also sets them under `vault`; `graft` is absent from the active system profile. These working-tree changes remain undeployed.
- ACME renewal writes to the same certificate directory; its `acme-postrun` hook only removes the `renewed` marker, and no Agent reload/restart is configured. OpenBao documents auth-method `reload = true` as rereading the keypair per authentication attempt, but this does not establish hot reload of a running vault client's transport; rollover remains unverified.
- A long-running child was started, the non-sensitive canary was rotated with CAS from KV version 1 to version 2, and the child restarted after receiving the updated value. The value was not printed. The 5-second render interval and all watcher artifacts were temporary test-only files.
- Go tests and vet passed; the updated Nix module passed `nixfmt --check`; a temporary Rowan flake copy evaluated the generated HCL and built the `graft` package. These are local checks only.
- No Nix activation, deployment, system-service restart, or application-credential change occurred. The live tests used Rowan's existing client certificate/key and the current OpenBao endpoint; the checked-out Nix changes are not thereby proven deployed.

### Latest follow-up — Rowan `graft` rollout and startup bounds (2026-10-29)

This subsection supersedes the earlier statements above that the 8202/Caddy route was inactive, Rowan mTLS/injection were untested, Graft was undeployed, or the retry policy was unchanged. It also records that the denied-path test reached Graft's outer deadline; it does **not** establish OpenBao Agent retry exhaustion.

- Deployed Rowan system generation 19 (`/nix/store/260jx8hwpz22p85fclb8c1dcrailnva6-nixos-system-agent-rowan-lxc-26.05.20261015.26f4107`). The closure diff only added `graft` 0.1.0 and removed `openbao-secrets` 0.1.0. The switch used a temporary `/run` staging tree with `--override-input openBaoClient path:<staged module>` and `--no-write-lock-file`; no source lockfile was changed. Activation restarted `sysinit-reactivation.target` and reloaded `dbus-broker.service`; afterward D-Bus, Caddy, and the ACME renewal timer were active, with no failed units. No OpenBao server restart, forced ACME run, or certificate change occurred.
- The active Agent HCL contains server CA trust, client certificate/key paths in both `vault` and cert auto-auth, 1s minimum / 8s maximum auth backoff, `exit_on_retry_failure = true`, and Rowan's canary mapping. `graft` is available in the system profile.
- Live smoke tests used a temporary binary built from the same Go source and a temporary HCL with a file token sink, mode `0600`, so each test token could be revoked immediately. The installed `graft --help` was also verified. The valid canary child exited successfully in 2 seconds and wrote only a non-secret presence marker; the canary value was not printed, and the token was revoked.
- The denied read of `kv/data/agents/alex/graft-denied-probe` returned through Graft's 60-second startup deadline with exit code 124. The child did not start; the test log had 40 denial and 10 retry lines. The temporary token was revoked. Agent was still retrying when Graft terminated its process group, so Agent retry exhaustion remains unverified.
- A token-lifecycle probe used the same private test sink: `bao token lookup` succeeded after the Agent exited, then `bao token revoke -self` succeeded. Test tokens were revoked without displaying their values. The normal Graft HCL has no token sink or revocation step; whether its no-sink token remains usable after exit was not tested directly.
- No `bao` or test Graft process remained. Temporary test configs, logs, token files, binaries, and staged source copies were removed.
- Local checks passed: `go test ./... -count=1`, `go vet ./...`, `go test -race ./...`, `nixfmt --check` on the module, and a Rowan NixOS build. The system profile is at generation 19; generation 18 remains available.
- The ACME renewal timer remains active, but no certificate replacement or renewal canary was run. `reload = true` is not proof that an already-running Agent's TLS transport reloads replaced files.

### Latest follow-up — local Graft systemd secret delivery (2026-10-30)

This records local implementation and verification only; it does not change Rowan's active generation or establish live workload use.

- Implemented per-service Graft render oneshot units and systemd LoadCredential integration in the working tree. Secret values remain outside Nix settings, the Nix store, generated unit contents, and logs. The renderer publishes private mode-0400 files atomically and revokes its captured Agent token before success; failures block the consumer start.
- The registered NixOS VM test passed with a fake OpenBao Agent and harmless fixture. It launches a mock Podman consumer through NixOS virtualisation.oci-containers and starts a one-shot systemd user unit invoking graft --env test.TOKEN run -- ...; the container receives a read-only systemd LoadCredential and the user-mode child receives a harmless canary, and a fake-backend marker confirms Graft called the token-revoke command. It also verifies other tested local users cannot read the credential, rendering reruns on container restart, and failed rendering blocks container startup. User-manager invocation is mocked; this does not validate live clanker credentials or OpenBao authorization. It is not production OCI support; Flakelet is not used.
- Go tests, go vet, race tests, Nix formatting, and the VM test passed. An isolated copy of Rowan's standalone flake also evaluated and built its full system toplevel as /nix/store/qnnr8jb4pzc9vfj0asxrniqw7l4x2rzz-nixos-system-agent-rowan-lxc-26.05.20261015.26f4107, with the local openBaoClient input explicitly overridden and no source lockfile update. This verifies candidate evaluation/build only, not live OpenBao behavior, deployment, activation, or secret rotation during a running service. ACME setup failures in the VM log are unrelated to this secret-delivery test.
- Files: hosts/features/opt-in/openbao-client/openbao-secrets/, hosts/features/opt-in/openbao-client/openbao-client.nix, and tests/graft-secret-render.nix. The focused check is registered as checks.x86_64-linux.graft-secret-render.

### Remaining

- Rowan's Graft startup deadline is 60 seconds, selected for this canary. Confirm that budget before deploying to other agents; the user has not specified a fleet-wide maximum.
- Decide whether Graft should capture and revoke its Auto-Auth token after child exit. The sink-backed probe showed a token remained usable after Agent exit; normal Graft has no sink/revoke cleanup, and the Rowan cert role issues 1-hour tokens (24-hour maximum). The no-sink path was not directly measured.
- Run an isolated certificate replacement/renewal canary without overwriting Rowan's installed certificate/key or exercising production ACME state. Use a controlled restart/relaunch for long-running Agent processes only if the isolated test shows that replacement files are not picked up.
- The authority-level SAN issuance policy remains unset. Keep issuance limited to the approved Rowan identity until that policy is reviewed. Other agent rollouts and Pi auth migration remain out of scope.

## Initial evidence and blockers (historical; superseded by status updates above)

### Live infrastructure

- OpenBao 2.7.0 is initialized and unsealed on agent-alex. Its current Caddy HTTPS route is `openbao.naco.casa`; preserve it.
- OpenBao runs rootlessly on Podman network `agent-openbao`, internal address `10.89.5.2`, with no host-published ports. Its config is mounted read-only at `/openbao/config`; data is writable at `/openbao/file`.
- The OpenBao host config is `/home/alex/.local/share/agent-services/openbao/config/openbao.hcl`, mode 0600. The existing cluster listener uses port 8201; do not alter it.
- Step CA runs in `smallstep-ca.service` on Podman network `agent-services`, using `/home/alex/.local/share/agent-services/smallstep-ca/data/authorities/pi-agent-ca/config/ca.json`. It is owned by `alex:users`, mode 0644. No recovery backup was found in the CA data tree.
- The container service uses rootless `keep-id:uid=10001,gid=10001`; the OpenBao service uses `keep-id:uid=100,gid=1000`. These mappings make owner-only files readable to the respective container process when owned by alex.
- The active tailnet-gateway image has Caddy Layer4 modules, but no `openbao-mtls.naco.casa` passthrough route is active. The tailnet-gateway worktree has unrelated dirty changes; preserve them.
- `openbao-mtls.naco.casa` resolves to the gateway. The Step CA container could not resolve/reach agent MagicDNS names in earlier probes. That result does not validate the intended client setup: the user requires the configured clients to be deployed and active before the HTTP-01 probe.
- The previous ACME directory `/acme/pi-agent-clients/directory` returned 404. The generic client config now points at `/acme/agent-clients/directory`; the live provisioner is not yet installed.
- On Alex, no `BAO_*`/`VAULT_*` authentication environment variable or default token file was found. No broad credential search was done. TLS configuration can proceed without an admin token; cert-auth roles, policies, KV setup, and end-to-end authorization need an authorized token source.
- At the time this initial draft was written, no live Step CA, OpenBao, Caddy, DNS, ACL, or client NixOS changes had been made; the status update above records later CA and Rowan client changes.

### Earlier local client work (historical)

- Renamed the client feature to `hosts/features/opt-in/openbao-client/openbao-client.nix` and the client option to `services.openBaoClient`.
- Reworked the Go runner into `graft run -- <command> [args...]`. It no longer selects or mentions Pi/LiteLLM. Nix can map arbitrary environment variable names to a KV v2 API path and field. The runner removes Bao/Vault override variables and replaces configured secret variables in the inherited environment.
- The client feature retains per-agent Caddy webroot HTTP-01, Lego key reuse, and Tailscale-interface-only TCP/80. It installs Lego, Step CLI, and OpenBao CLI; OpenBao Agent injection stays disabled by default.
- Updated Alex and Rowan profile option references and the flake input name to `openBaoClient`. The nested flake input was changed to a repository-root-relative path; verify it in a temporary Git copy before relying on it.
- Go unit tests pass. The runner Nix package builds. A standalone NixOS evaluation of the generic HCL template produced an arbitrary `APP_TOKEN` mapping correctly. Alex profile evaluation and all four Rowan profile evaluations passed from temporary copies with the local module input override. No host build or deployment ran.
- Existing Pi auth migrator `hosts/features/opt-in/pi-openbao-client-launcher.py` is a separate, opt-in compatibility helper. It was not changed or run.

## Execution sequence

1. **CA recovery check — complete 2026-10-29:** Create a mode-0700 backup directory outside the Step CA data mount; archive the CA data/config with a mode-0600 archive. Test archive integrity, extract to a temporary directory, and compare the active config hash. Confirm owner/mode access based on the Podman user mapping. Do not edit live CA config until this check passes.
2. **Provisioners — complete 2026-10-29:** On a copy, validate a generic `agent-clients` ACME provisioner using HTTP-01 and a `ClientAuth` template, plus a separate `openbao-server` provisioner with `ServerAuth`. Default/max validity: 90 days. Do not use a shared long-lived JWK bootstrap credential. Apply only after the recovery check; restart Step CA and verify the directory response.
3. **Client deployment — Rowan canary complete 2026-10-29; remaining agents pending:** Rowan's profile is active at generation 19 with local Caddy, Lego, Step/OpenBao tooling, and Graft. The issued client certificate's SAN, ClientAuth EKU, chain, validity, and file ownership were verified; the renewal timer is active. Do not infer a scheduled renewal from a successful service run.
4. **OpenBao TLS — active and verified 2026-10-29:** The dedicated 8202 listener requires client certificates; Rowan validated the server chain and completed cert-auth. Existing 8200/8201 listeners were preserved.
5. **Caddy passthrough — active and verified 2026-10-29:** The exact-SNI Layer4 route is mounted and active; the mTLS endpoint presents the expected certificate and rejects clients without a certificate. The existing OpenBao API/UI route remains preserved.
6. **Authorization — Rowan verified 2026-10-29:** The `agent-rowan` cert role and read-only KV v2 policy are active. Rowan's canary read succeeded; tested cross-agent data and Rowan metadata access were denied. Temporary tokens were revoked.
7. **Generic runtime test — Rowan canary complete 2026-10-29:** Graft injected the canary into a child without printing it; a denied cross-agent path prevented child startup and returned at the 60-second Graft deadline. See the latest follow-up for exact evidence and limits.
8. Only after all checks pass, decide whether to migrate any Pi auth file. Preserve existing OAuth data and the rollback copy.

## Verification

- Go: `cd hosts/features/opt-in/openbao-client/openbao-secrets && go test ./...`
- Nix formatting and parsing on the changed module and host flakes.
- Evaluate the generated OpenBao Agent HCL with a non-secret sample mapping and confirm the configured executable package builds.
- Evaluate Alex and all four Rowan profiles. Build/deploy serially only after checking memory and disk.
- On live systems, verify Step directory, actual HTTP-01 challenge retrieval, canary certificate properties, OpenBao TLS/mTLS, Caddy passthrough, own-path authorization, and negative authorization without exposing secret values.

## Rollback

Restore only the backed-up Step CA config if provisioner changes fail. Restore the backed-up OpenBao/Caddy config if validation or reload fails. Keep Raft, CA key material, ACME state, and client state intact. Revert only this feature's Nix/client files; never reset, clean, or stage the broader dirty worktree.
