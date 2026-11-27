# Nanoserver + Miniserver Platform (Phased)

## Goal

Roll out host virtualization and container tools first, then build the Kubernetes service platform as a separate phase. Keep Kubernetes/VM/container service availability separate from host-level HA: there is no HA host or VM layer in this plan.

## Phase 1: Podman and libvirt

- Enable QEMU/KVM + libvirt and Podman on the Nanoserver v4 profile and miniserver NixOS profiles.
- Keep K3s disabled. Do not install a GitOps controller in this phase.
- Persist `/var/lib/libvirt`, `/var/lib/containers`, and Rona's rootless Podman storage under `/persist`.
- Keep libvirt management on its local Unix socket; use SSH for remote administration. Do not expose unauthenticated libvirt TCP.
- Do not create VMs, containers, or workloads.

## Phase 1 rollout status and gates

- Nanoserver v3 remains active; v3 and v2 artifacts are immutable rollback options. The P/L-only v4 image must pass CI and be published as a new signed version before updating the host. Release publication and host rollout remain separately authorized.
- Read-only preflight on Nanoserver confirmed the two-device Btrfs root mirror, both boot ESPs, and `/persist` are mounted; the CPU exposes `vmx`. The explicit `nanoserver` sysupdate component can list and verify the signed manifest. The deployed v3 generic `systemd-sysupdate.service` currently fails with “No transfer definitions found”; the local v4 configuration overrides it with a component-specific stage-only wrapper. The `nanoserver-01-slot-uki` and host-platform checks pass, including candidate discovery/no-candidate and staged-version replacement fixtures. The v4-root disposable-QEMU boot/recovery test also passes. These are local validation only: v4 behavior is not active until its release is separately approved and installed.
- Deploy Nanoserver through the guarded `appliance-update` path, verify boot and host services, then use it as the first canary. Reboot remains manual. Once the stage-only v4 configuration is running, newer signed versions are polled and staged automatically; do not bypass the updater with an in-place rebuild.
- Miniserver profiles remain uninstalled. Their physical installation, Disko, and disk changes are outside this phase and require explicit authorization. Once installed, apply the P/L profile one host at a time.

## Phase 2: Kubernetes service platform (deferred)

The intended cluster has three K3s server nodes on the miniservers and Nanoserver as an agent. K3s keeps containerd; Podman remains independent. The service network plan is Cilium as primary CNI, MetalLB for explicit LAN service VIPs, Multus only for workloads needing secondary networks, and Tailscale for private administration/service access. Argo CD is preferred over Flux. No components in this phase are enabled by the P/L-only host feature.

This cluster does not add host/VM HA. Service-level redundancy will be planned through workload replicas and placement. The API endpoint remains a separate availability decision; do not use MetalLB as the bootstrap/API endpoint. No Kubernetes service is to be exposed publicly without explicit approval.

## Verification

- Evaluate all miniserver profiles and Nanoserver v4: libvirt and Podman enabled; K3s disabled.
- Evaluate Nanoserver v3: P/L and K3s remain disabled; retain the existing signed-manifest and `Verify=` compatibility assertions for the published v3 artifact, while v4 omits unsupported `Verify=` keys.
- Build the v4 A/B bundle and enforce the release-asset size limit in CI. CI does not publish or deploy.
- After the signed release is available and separately authorized, use `appliance-update 4` to stage it; reboot manually. Verify the running version/slot, `/dev/kvm`, `libvirtd.socket`, Podman, and persisted paths. Keep v3/v2 rollback intact.

## Safety constraints

- Do not format disks, install NixOS on miniservers, alter rescue media, create VMs/containers, or launch application workloads as part of Phase 1.
- Do not expose libvirt management over unauthenticated TCP.
- Treat the existing Nanoserver v3 and v2 releases as immutable; a new platform build always gets a new numeric version.
- Cluster bootstrap, CNI, MetalLB address pools, Multus attachments, Tailscale Operator, and Argo CD require a separate implementation and verification phase.
