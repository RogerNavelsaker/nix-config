# Resource tree and NixOS-WSL configuration plan

## Goal
Generate NixOS and Home Manager outputs from the main nix-config flake using the resource tree (vessels, clankers, hosts, users) and nix-lib, with separate Ester-desktop agent and services NixOS-WSL systems.

## Non-goals
- Deploy or switch either WSL distro.
- Change Windows WSL registration, startup tasks, firewall, driver, or inference runtime state.
- Replace existing host configurations or remove rollback state.
- Update unrelated in-progress Nanoserver, LXC, secrets, or workstation changes.
- Pull or publish remote changes without explicit approval.

## Desired generator interface
- Main flake uses one nix-lib resource-discovery/generation interface; resource directories are source of truth, not per-class configurations.nix registries.
- Consume the published RogerNavelsaker/nixpkgs aggregate as the nixpkgs-packages flake input; the flake-inputs overlay exposes selected outputs at pkgs.inputs.nixpkgs-packages.nixpkg-<repo>.<output>. Build only selected derivations; OCI images remain GHCR-only.
- Do not create a second stable agentLib builder, hosts/miniserver-common aggregator, or users/agents aggregator. Channel selection belongs to resource/config metadata interpreted by the shared generator.
- Prefer existing nix-lib mkSystem(s)/mkHome(s) and Foundry-style module discovery. If composition exposes a real gap, extend nix-lib with focused mkVessel(s) and/or mkClanker(s) helpers that reuse the same builder and folder discovery; do not add resource.nix registries or a second library instance.
- Preserve dirty behavior while migrating into resource-owned modules/features; remove old layouts only after parity.

## Resource layout approach
Reuse nix-lib/Foundry-style directory and module discovery. Do not add resource.nix files or a standalone resources.nix helper unless implementation demonstrates a concrete need beyond existing builder discovery. Resource role, module, and feature boundaries should emerge from the folder layout and normal Nix module metadata.

## Confirmed target tree
- vessels/{mara,mira,rowan,jules,avery,alex}
- clankers/{mara,mira,rowan,jules,avery,alex}
- hosts/{roger-aio,nanoserver-01,miniserver-01,miniserver-02,miniserver-03,ester-desktop}
- users/{rona,admin}
- Resource-local features/{default,opt-in,opt-out} provide defaults, data seeding, and scoped overrides.

## Confirmed resource and access model
- Clanker is agent identity; vessel is its LXC/WSL runtime. `agent@mara` means login `agent` on Mara vessel.
- Host is physical/virtual machine. User is human maintenance account: personal hosts use `rona`/`ester`; managed servers use `admin`.
- Host, vessel, clanker, user, service, ingress identities remain distinct. `user@node` is SSH notation, not resource ID.
- Rowan, Mira, Jules, Avery run as LXC agents on `roger-aio`; Mara runs on `ester-desktop`; Alex currently runs on a Linode host, with host/node rename planned.
- Host SSH: `rona@roger-aio`, `ester@ester-desktop`, and `admin@<host>` for managed servers.
- Ester services WSL: `users/admin`, OS hostname `services`, Tailscale node `ester-services`, `tag:server`; admin uses Tailscale SSH; service/model traffic uses ingress.
- Each independently addressable service has its own Tailscale service identity/node and uses `tailscale serve --service` where appropriate.
- Ingress is role-based, not one gateway per host. Separate WAN and LAN ingress are confirmed; remote mesh clients may use mesh-reachable LAN ingress or distinct mesh ingress (open).
- Existing gateway OCI names identify deployments; map them to ingress roles, not one-per-host architecture. Alex gateway rename remains pending.
- Tailscale is interim; Nebula is target after validation. Overlay transports ingress-to-backend traffic, including LAN users; no direct LAN backend bypass. Overlay failure makes remote backends unavailable from LAN/WAN; services local to ingress may remain.
- Preserve one service hostname across public WAN, LAN, and mesh via public DNS and split-horizon internal DNS.
- WAN ingress: Linode Caddy, strong Authelia for explicitly public services. LAN ingress: lower-friction LAN policy. Mesh clients: relaxed policy.
- Each independently addressable service gets its own Tailscale service identity/node, exposed with tailscale serve --service where supported. Service, backend host/vessel, and ingress identities remain distinct.
- Restrict backend ports to approved ingress/service identities. Admin access uses private-overlay SSH; public admin surfaces remain excluded.

## Confirmed mappings
- Ester-desktop agent WSL: vessel principal/configuration vessels/mara plus distinct user/clanker principal/configuration clankers/mara.
- Ester-desktop services WSL: host principal/configuration hosts/ester-desktop plus users/admin. Podman and vLLM are service-host features; hostname `services`, node `ester-services`, `tag:server`.
- hosts/nanoserver-01 and hosts/miniserver-{01,02,03} use users/admin.
- hosts/roger-aio maps to users/rona for maintenance identity, but generate no NixOS or Home Manager output while the host runs CachyOS. Revisit after migration to NixOS.
- Host/vessel identities and user/clanker identities remain separate principals, certificates, and access grants; system services use host/vessel scope, user services use user/clanker scope.

## Context and evidence
- Repository: /workspace/RogerNavelsaker/nix-config.
- The worktree already has extensive staged/unstaged/untracked changes, including hosts/rowan, vessels/mara, hosts/features, users/agents, flake.nix, and flake.lock. Preserve all existing changes and inspect diffs before touching overlapping paths.
- Related plan decisions reviewed: graft-management-plane and graft-systemd-secret-delivery define host/vessel vs user/clanker as separate principal classes; roger-aio-agents-nixos-lxc distinguishes LXC vessel profiles from Mara's separate WSL deployment; Nanoserver/miniserver platform and workload plans separate host configuration from Podman service workloads and prohibit unrelated deployment during config work.
- Relevant wiki entries: [[sources/obs-2026-11-05-nix-config-resource-tree-target]], [[sources/obs-2026-11-05-admin-user-mapping-for-nixos-hosts]], [[sources/obs-2026-11-05-separate-agent-and-services-nixos-wsl-distros]], [[sources/obs-2026-10-30-separate-user-clanker-and-host-vessel-certificate-identities]], [[concepts/nebula-mesh-and-unified-service-ingress-architecture]], [[sources/obs-2026-10-27-separate-lan-and-wan-ingress-over-overlay-interconnect]], [[sources/obs-2026-10-27-mesh-dependent-unified-service-routing-accepted]], [[sources/obs-2026-10-27-same-service-hostname-across-public-mesh-and-lan]], [[sources/obs-2026-10-27-nebula-gateway-dns-design-aligned-with-tailnet-gateway]]. Latest user mapping supersedes older conflicting plan text.
- Current dirty flake.nix creates agentInputs/agentLib with stable inputs, and merges hosts/rowan/configurations.nix plus users/agents/configurations.nix. User explicitly rejected this target interface.
- Current tree includes hosts/miniserver-common, hosts/miniserver-configurations.nix, users/agents, and per-agent host folders as dirty work. Migrate behavior deliberately into resource-owned modules/features before removing.
- hosts/rowan/flake.nix and vessels/mara/flake.nix are standalone entry points, contrary to the requested main-flake generation model.
- nix-lib memory-bank records that mkSystem discovers hosts/{hostname}/default.nix and host features, while mkHome loads users/{username}/default.nix and hostname-specific user modules. Reuse these patterns for vessel/clanker resources; add mkVessel(s)/mkClanker(s) only if the differing roots/features cannot be expressed cleanly.
- Existing host and user feature trees use features/{default,opt-in,opt-out}. Root mkSystem currently resolves host features globally and integrated user features; standalone HM uses user features.
- vessels/mara/configuration.nix is a NixOS-WSL agent configuration, and its adjacent flake imports nix-community/NixOS-WSL. It disables Windows automount and interop and defines Mara identity/tools.
- Root flake.nix and flake.lock have pre-existing modifications. Keep those and merge only targeted changes.

## Blast radius
- Root flake.nix output generation and possibly flake.lock if a WSL module input moves into the main flake.
- hosts/rowan/configurations.nix, hosts/rowan/flake.nix, vessels/mara/flake.nix, and their configuration modules.
- New hosts/ester-desktop, vessels/*, clankers/*, and users/admin resource modules/features.
- nix-lib APIs only if existing builders cannot compose resource modules/features cleanly; prefer additive root-flake composition first to avoid affecting other consumers.
- Checks for output enumeration, feature merging, NixOS evaluation, and formatting.

## Steps
1. **Inventory and preserve current state.** Review git status and diffs for flake.nix, flake.lock, hosts/rowan, vessels/mara, users/agents, and current host/user feature trees. Trace existing output names and state versions. Record collisions before edits.
   - Verify: git diff --check; capture baseline nix flake show --no-write-lock-file if evaluation is available without fetching.
2. **Map the Foundry directory-discovery pattern onto this repository.** Reuse module discovery and feature conventions; specify only the minimal nix-lib builder extension needed to compose hosts/vessels with users/clankers. Test folder discovery and generated output naming without introducing resource.nix metadata.
   - Verify: add focused evaluations for folder discovery, vessel/clanker pairing, feature composition, deterministic output names, and any new nix-lib mk helper behavior.
3. **Extend nix-lib only for a demonstrated gap.** Prefer existing builders; if needed, add mkVessel(s) and/or mkClanker(s) as thin reusable helpers over existing builder and folder-discovery primitives. Main flake remains the sole entrypoint; do not add per-agent registries or parallel library instances.
   - Verify: evaluate nixosConfigurations and homeConfigurations; assert expected outputs and confirmed mappings.
4. **Migrate agent and host entries without behavior drift.** Move existing Mara and Rowan configurations into the common entry point/resource modules; retain features, package args, user IDs, WSL settings, and deployment semantics. Keep standalone files until replacement outputs evaluate and parity checks pass; remove obsolete entry points only after references are accounted for.
   - Verify: evaluate Mara and Rowan and compare critical options against current configurations.
5. **Add Ester-desktop services host.** Create hosts/ester-desktop using NixOS-WSL and users/admin; compose service features under the resource tree. Add Podman declaratively. Keep vLLM runtime config isolated and conservative; assert AMD/WSL/GGUF/MTP compatibility only after evaluation or hardware testing. Bind APIs privately by default.
   - Verify: evaluate services host, Podman enablement, private listener/firewall defaults, and explicit model settings without implicit weight downloads.
6. **Validate integration and document invocation.** Update docs with generated output names and build commands. Run formatting and narrow flake checks; report unavailable fetches or hardware-only validation.
   - Verify: repository formatter, nix flake check --no-build where supported, and focused nix eval/build for each new output.

## Rollback
- Preserve pre-existing user changes; never restore the whole worktree.
- Revert only newly added files and exact flake.nix/lockfile hunks owned by this work if validation fails.
- Retain standalone Mara/Rowan configs until replacement outputs pass evaluation and parity checks.
- No WSL deployment or unregister operation is part of this plan.

## Open questions
- Wiki architecture is current ingress source: distinct WAN/LAN ingress confirmed; remote mesh clients may use mesh-reachable LAN ingress or a dedicated mesh ingress. Dedicated repo plan location remains unconfirmed.
- Verify exact `tailscale serve --service` support/configuration and per-service identity provisioning against selected Tailscale version and ACL policy; Tailscale is interim and Nebula migration follows validation.
- Final Alex host/node rename remains pending; `alex-gateway` is transitional.
- Define service-node names/tags per workload; specify DNS records, Authelia policies, gateway-to-ingress roles, and backend ACLs in ingress implementation planning.
- Preserve the existing distinct host/vessel and user/clanker identity model from docs/plans/graft-management-plane.md and docs/plans/graft-systemd-secret-delivery.md. Resource directories are declarative identity/configuration inputs, not assumptions that a clanker is a workload module.
- The main flake needs NixOS-WSL for both Ester-desktop WSL configurations. The existing vessels/mara/flake.nix already declares the input; integrate its pinned source/lock without remote updates unless authorized.
- Which model runtime is supported for the service-host vLLM feature remains a validation gate. Prior WSL experiments did not complete inference for the target GGUF; encode only verified capability.
- Defer both rona@aio and rona@roger-aio Home Manager outputs, plus the roger-aio NixOS output, until the CachyOS host transitions to NixOS.

### For Executor
Read order: this plan → AGENTS.md → root flake.nix/flake.lock diffs → /workspace/RogerNavelsaker/nix-lib/lib/{default.nix,builders.nix,features.nix} → hosts/rowan/* → vessels/mara/* → host/user feature trees.

Assumed state: /workspace/RogerNavelsaker/nix-config contains many unrelated local changes; preserve all. No remote or WSL deployment action is authorized by this plan.

Owned files: resource-tree implementation, narrow root-flake integration, and this plan; touch nix-lib only if a concrete builder limitation is demonstrated.

Verification: repository formatter/check conventions from AGENTS.md; focused Nix evaluation of every generated host/user output; git diff --check; inspect final diff and git status --short.
