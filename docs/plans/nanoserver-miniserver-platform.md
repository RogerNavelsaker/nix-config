# Unified Hypervisor and Kubernetes Platform

## Goal

Configure Nanoserver and all three miniservers with the same declarative host stack—QEMU/KVM + libvirt, Podman, and K3s—and reconcile Kubernetes workloads from Git.

## Agreed topology

- All four hosts receive the shared host-platform feature.
- `miniserver-01`, `miniserver-02`, and `miniserver-03` are K3s server nodes using embedded etcd; `miniserver-01` initializes the cluster.
- `nanoserver-01` is a K3s agent/worker.
- K3s uses its normal containerd runtime. Podman is a separate host container runtime, not K3s's CRI.
- Flux is the default GitOps controller.

## Non-goals

- No live host deployment, reboot, disk formatting, rescue-ISO changes, or VM/workload creation in this implementation phase.
- Do not change the already-published/running Nanoserver v3 artifact. Add the platform to a new Nanoserver v4 image; preserve v3 and v2 rollback images.
- Do not expose libvirt's management socket over unauthenticated TCP or publish Kubernetes services externally before network policy is agreed.

## Context and evidence

- All four machines are x86_64. The miniserver readiness plan records three identical Intel i5-8600T / 64-GiB hosts with two 465-GiB NVMe devices and two USB A/B devices each; Nanoserver has a separate USB A/B root and mirrored-NVMe `/persist` layout. Firmware virtualization enablement still requires a read-only hardware check.
- Miniservers currently use systemd-networkd with DHCP on wired interfaces, Avahi hostnames, Tailscale, and volatile root/log state. Nanoserver has wired, QEMU-wired, and WLAN DHCP profiles plus Tailscale.
- Appliance `/persist` is backed by mirrored NVMe Btrfs. Existing persistence currently covers host keys and small runtime paths, not K3s or libvirt state.
- The pinned NixOS 25.11 `services.k3s` module supports server/agent roles, embedded-etcd `clusterInit`, `serverAddr`, and `tokenFile`. The token must never use the literal `token` option, which stores it in the world-readable Nix store.
- Current Nanoserver v3 store archive is 1,166,046,696 bytes. GitHub Release assets have a per-file size ceiling; CI must reject an oversized store bundle before publishing and the delivery backend must be revisited if the platform closure exceeds that ceiling.
- Relevant existing files: `hosts/miniserver-configurations.nix`, `hosts/nanoserver-01/configurations.nix`, `hosts/features/opt-in/appliance/persistence.nix`, `hosts/miniserver-common/{network,persistence,secrets}.nix`, `hosts/nanoserver-01/{network,persistence,secrets}.nix`, `hosts/nanoserver-01/update-bundles.nix`, `tests/nanoserver-slot-uki.nix`, `.github/workflows/{ci,publish-appliance-update}.yml`, `docs/APPLIANCE-UPDATES.md`.
- No existing K3s/libvirt/Podman/GitOps module or matching Mulch decision exists. Durable project work should be tracked in Seeds.

## Blast radius

- Add one shared opt-in NixOS feature for libvirt/QEMU/KVM, Podman, K3s common settings, and persistent state.
- Apply it to all miniserver A/B profiles and only the new Nanoserver v4 A/B profiles. Preserve the live v3 profile and released assets.
- Add per-host K3s roles, endpoint/bootstrap settings, token-file wiring, and scoped firewall rules.
- Add the shared encrypted cluster token in the owning `nix-secrets` repository through a platform-only `nix-secrets-cluster` input; preserve the existing `nix-secrets` pin so Nanoserver v3 keeps its original source closure. No plaintext credential may enter `nix-config`, CI logs, or the Nix store.
- Add a Flux bootstrap/reconciliation path and a `clusters/nanoserver-miniservers/` manifest tree in Git. Keep application secrets SOPS-encrypted.
- Extend NixOS evaluation/checks, signed bundle build/size gate, and operations documentation. No deployment is performed by CI.

## Implementation steps

1. **Networking and secret bootstrap.** Use `miniserver-01.local:6443` as the stable initial join/API endpoint (provided by existing Avahi); explicitly document that etcd is three-node but the client API endpoint is a single-node availability dependency. Use K3s defaults `10.42.0.0/16` Pod and `10.43.0.0/16` Service CIDRs and assert the selected values in CI; review overlap with actual LAN/VPN routes before rollout. Store the shared cluster token in a dedicated SOPS-encrypted file with age recipients for all four hosts, accessed through `nix-secrets-cluster` only.
2. **Create shared host feature.** Add `hosts/features/opt-in/host-platform/` to enable QEMU/KVM + libvirt and Podman; keep libvirt management local/SSH-only. Persist `/var/lib/libvirt`, `/var/lib/rancher/k3s`, and the chosen rootless Podman storage under `/persist`. Configure only required K3s ports on trusted interfaces.
3. **Define K3s roles.** Set the three miniserver server roles and first-server `clusterInit`; set Nanoserver as agent in v4. Use `tokenFile`, explicit Pod/Service CIDRs, stable server endpoint, node address selection, and required TLS SANs.
4. **Add GitOps bootstrap.** Add Flux installation/bootstrap manifests and a public read-only Git source rooted at `clusters/nanoserver-miniservers/` in `nix-config`. The initial baseline has no Kubernetes Secrets; defer Flux SOPS decryption until a separate Kubernetes-side age identity is provisioned, and never store an age private key in Git.
5. **Version Nanoserver safely.** Add v4 A/B Nanoserver configuration profiles and a v4 update bundle; never rewrite v3 assets. Enable the shared feature on initial miniserver A/B profiles, which have not been physically installed.
6. **Add checks and documentation.** Add evaluation assertions for host roles, persistence, K3s endpoint/token-file wiring, runtime separation, and firewall policy. Add CI builds for the four configs and Nanoserver v4 bundle plus a release asset-size limit. Document bootstrap order, GitOps reconciliation, backup/restore, and rollback. Keep this work on a PR branch: do not merge to main or publish signed release assets as part of CI-only validation.

## Tests and verification

- `nix eval --raw .#nixosConfigurations.miniserver-01.config.services.k3s.role` (and equivalent for miniserver-02/03 and Nanoserver v4 agent) verifies intended roles without building.
- Evaluate all relevant A/B configurations and the new platform feature; assert persistent paths, `tokenFile` use (never literal `token`), endpoint/TLS SAN consistency, K3s containerd, and firewall ports.
- Build the focused Nanoserver slot check and v4 update bundle in GitHub Actions, not as a local appliance build. Fail if any release asset exceeds its size budget; signed publication is a separate authorized release step.
- Validate Flux manifests with pinned Flux/Kustomize tooling and check that no plaintext secrets or private age keys are present. Verify the existing `nix-secrets` pin remains unchanged for the Nanoserver v3 profile.
- Live bootstrap, K3s quorum, Podman/libvirt runtime smoke, GitOps reconciliation, and rollback are separate operator-authorized acceptance gates; CI config checks alone do not prove a running cluster.

## Rollback

- Before deployment, revert the new feature/profile commit; existing v3/v2 artifacts remain unchanged.
- For Nanoserver, keep v3 and its working systemd-boot fallback until v4 passes boot and cluster-agent checks.
- For miniservers, retain each A/B slot and do not run Disko as part of this feature rollout.
- If cluster bootstrap fails, stop Flux reconciliation and leave the K3s state directories intact for diagnosis; do not wipe etcd or reformat disks.

## Endpoint decision

Use `miniserver-01.local:6443` for the initial server/agent join endpoint. Existing Avahi publishes the DHCP hostnames, so no new IP reservation is assumed. This gives a three-member embedded-etcd control plane but **not** a highly available client/API endpoint: Nanoserver and external clients initially depend on `miniserver-01` for API access. A later LAN VIP/load balancer requires a reserved address and separate operator/network approval; this implementation does not invent one.

### For Executor

Read order: this plan; `hosts/miniserver-configurations.nix`; `hosts/nanoserver-01/configurations.nix`; `hosts/features/opt-in/appliance/{persistence,sysupdate}.nix`; `hosts/miniserver-common/{network,persistence,secrets}.nix`; NixOS 25.11 `services.k3s` and `virtualisation.libvirtd` modules; the focused checks and publisher workflows.
Assumed working state: Nanoserver v3 is live and healthy; its v3 artifact is immutable. Miniserver physical installs are still gated by `docs/plans/miniserver-install-readiness.md`.
Owned files: shared platform module, four host/slot profiles, K3s token wiring, GitOps manifests, targeted checks, CI size guard, and platform operations docs; coordinate encrypted token material with the separate `nix-secrets` repository.
Verification commands: the listed `nix eval` role checks, `nix flake check`/focused checks in CI, actionlint, Flux manifest validation, and signed v4 bundle publishing. Do not run live deployment or Disko commands without separate authorization.
