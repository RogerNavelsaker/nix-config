---
id: 1576
type: decision
project: nix-config
scope: project
topic_key: workload-nix-isolation
session_id: manual-save-nix-config
created_at: "2026-10-08 09:55:47"
updated_at: "2026-10-08 09:55:47"
revision_count: 1
tags:
  - nix-config
  - decision
aliases:
  - "Separate workload Nix from appliance OS updates"
---

# Separate workload Nix from appliance OS updates

Agreed architecture direction for nix-config: the appliance stays a systemd-repart/systemd-sysupdate image without a Nix CLI or daemon. After the Podman/libvirt host baseline, evaluate an independent unprivileged Nix runtime using devenv/Home Manager, with workload flake outputs separate from NixOS configurations and built/signed outside the appliance. Start with rootless Podman Quadlet workloads. Libvirt access is privileged and must not be granted broadly via qemu:///system or unrestricted sudo; any host-owned activator must enforce a fixed allowlist of domains, storage paths, networks, and lifecycle operations, with no arbitrary commands or hooks. Store writable VM disks under /persist. Use nix-keys for trust/bootstrap identity and nix-secrets for runtime-only credentials; never put secrets in derivations. Workload changes must not modify the booted OS generation, boot files, /etc, host users/network, or unrelated systemd services. Threat-model and prototype before deploying. Tracked in Seeds nix-config-a280 and child nix-config-82e1; current P/L-only PR #7 remains a separate first phase.

---
*Session*: [[session-manual-save-nix-config]]
*Topic*: [[topic-workload-nix-isolation]]
