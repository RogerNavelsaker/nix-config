# Nanoserver + Miniserver host platform

## Scope and rollout phase

The first rollout stage enables only QEMU/KVM + libvirt and Podman on the Nanoserver v4 profile and the miniserver NixOS profiles. It does not enable K3s or install a GitOps controller. Podman remains independent of any future Kubernetes container runtime.

The future cluster stage is separate: Cilium, MetalLB, Multus, and Tailscale are planned, with Argo CD preferred over Flux. That stage needs its own configuration, network/IP decisions, and rollout authorization. The current Nanoserver v3 image remains unchanged; v4 removes unsupported systemd-sysupdate `Verify=` keys while retaining signed-manifest verification through the configured GPG keyring.

Miniserver profiles are not physically installed yet and remain subject to `docs/plans/miniserver-install-readiness.md`. Do not run Disko or change disks as part of this host-services stage.

## Host services and access

- Libvirt management stays on its local socket; use SSH transport for remote administration. Do not expose an unauthenticated libvirt TCP API.
- Podman does not add a listening service. This configuration does not create containers, VMs, or workloads.
- No Kubernetes API, ingress, MetalLB pool, or external service is configured in this stage.

## Persistent state

Nanoserver's root is ephemeral. Under `/persist` (mirrored NVMe), this stage preserves `/var/lib/libvirt`, `/var/lib/containers`, and Rona's rootless Podman storage. The mirror protects against a single NVMe failure, but is not an off-host backup. No VM images or container workloads are created by this change.

## Rollout and acceptance sequence

1. Build and validate the P/L-only Nanoserver v4 bundle in CI; confirm the v4 profile has K3s disabled and Podman/libvirt enabled.
2. Before switching Nanoserver, verify the signed v4 release is available and the appliance updater's Btrfs mirror, both boot ESPs, and `/persist` preflight passes. Keep v3 and v2 rollback images immutable.
3. Update Nanoserver through the existing `appliance-update` A/B path, reboot only after staging succeeds, then verify the active slot/version, `/dev/kvm`, `libvirtd.socket`, and Podman availability. Do not create VMs or containers during this stage.
4. Miniserver installation and disk operations require their separate readiness gates and explicit authorization. Once installed, roll out host services one machine at a time and verify KVM/libvirt/Podman before continuing.
5. Defer K3s, Cilium, MetalLB, Multus, Tailscale Operator, and Argo CD until a separate cluster-stage plan and approval.

The repository continues to use one `nix-secrets` input. No cluster token is needed for this host-services stage. The already-published Nanoserver v3 image and v2 rollback remain unchanged. The currently running v3 host reports a failed generic `systemd-sysupdate.service` because it finds no generic transfer definitions; the explicit `nanoserver` component listing succeeds and verifies the signed manifest. Track that separately rather than treating it as proof that the A/B updater is unusable.

## Rollback

- Keep Nanoserver v3 and v2 bootable; never rewrite published assets.
- If v4 fails acceptance, boot the existing v3 slot and stop rollout.
- Do not format disks, provision VMs, or delete persisted data during diagnosis.
