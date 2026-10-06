# Nanoserver + Miniserver host platform

## Scope and status

The shared `host-platform` NixOS feature provides QEMU/KVM + libvirt, Podman, and K3s on three miniservers plus Nanoserver. K3s uses its built-in containerd; Podman remains a separate host runtime. Miniservers are server nodes with embedded etcd; Nanoserver is an agent. Flux reconciles the public baseline in `clusters/nanoserver-miniservers/`.

The configuration is CI-only until separately authorized for rollout. It does not format disks, provision VMs, expose libvirt TCP APIs, deploy live, or alter the running/published Nanoserver v3 image. Nanoserver v4 is the first profile containing this stack. Miniserver profiles are still subject to the install-readiness gates in `docs/plans/miniserver-install-readiness.md`.

## Addressing and firewall

- Initial K3s join/API address: `miniserver-01.local:6443`, advertised by existing Avahi.
- This provides three-member etcd quorum, but the configured API address is **not HA**; agents and clients initially depend on miniserver-01. Use a separately approved LAN VIP/load balancer before describing the API endpoint as highly available.
- Pod CIDR: `10.42.0.0/16`; Service CIDR: `10.43.0.0/16`. Check both against LAN/VPN routes before rollout.
- Miniservers allow API, kubelet, etcd, and Flannel VXLAN traffic only on wired `eno1`. Nanoserver opens only kubelet and Flannel ports (no API or etcd listener). Remote Kubernetes API access should use an SSH tunnel; the K3s ports are not opened on `tailscale0`.
- Libvirt management stays on its local socket; use SSH transport for remote administration. Podman does not add a listening service.

## Persistent state

The appliance root is ephemeral. Under `/persist` (mirrored NVMe), the feature preserves `/var/lib/libvirt`, `/var/lib/containers`, `/var/lib/rancher`, `/var/lib/kubelet`, and Rona's rootless Podman storage. The K3s embedded-etcd snapshots therefore remain on the NVMe mirror with the cluster state. RAID1 protects against a single NVMe failure; it is not an off-host backup. Choose and test an off-host snapshot/VM backup target before placing important workloads on the cluster.

No VM, Podman service, Kubernetes application, external ingress, or off-host backup destination is provisioned by this change.

## Bootstrap and acceptance sequence (operator authorization required)

1. Complete the existing miniserver install and recovery gates; do not run Disko as part of this platform change.
2. Before enabling libvirt, confirm firmware VT-x is enabled and `/dev/kvm` is present on each machine. CPU model support alone does not prove firmware enablement.
3. Install/activate the miniserver profiles one at a time under a separate deployment authorization. Start miniserver-01 first and confirm its API and embedded-etcd health.
4. Join miniserver-02 and miniserver-03, then verify three ready server nodes and etcd quorum.
5. Deploy Nanoserver v4 only under separate authorization; verify its agent joins and returns to Ready after reboot.
6. Verify Flux source/kustomization Ready conditions and the `platform-system` namespace. Keep the public baseline and application workloads distinct.
7. Test an etcd snapshot restore and a libvirt VM backup/restore before relying on persistent workloads. The repository configures local persistence only; it does not claim off-host recovery.

The shared cluster token is SOPS-encrypted in the `nix-secrets` repository for the four host age recipients. The platform consumes it through the separate `nix-secrets-cluster` flake input, leaving the existing `nix-secrets` input unchanged for the immutable Nanoserver v3 closure. The NixOS service consumes it by `tokenFile`; the token is not embedded in the Nix store. Flux reads the public repository anonymously. Flux SOPS decryption is deferred until a separate Kubernetes-side age identity is provisioned for actual encrypted workload Secrets.

## Rollback

- Nanoserver v3 and v2 remain the boot/update rollback options; never rewrite their published artifacts.
- Keep each miniserver A/B slot and do not erase K3s state or etcd snapshots during diagnosis.
- Disable Flux reconciliation before intentionally changing/removing the cluster baseline.
- Host-state rollback does not restore application data or VM images without independent backups.
