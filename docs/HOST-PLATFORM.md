# Nanoserver + Miniserver host platform

## Scope and rollout phase

The host-services stage enables QEMU/KVM + libvirt and Podman on the Nanoserver v4 and miniserver NixOS profiles. Nanoserver v4 additionally runs a headless Herdr server for SSH-backed machine management. It does not enable K3s or install a GitOps controller. Podman remains independent of any future Kubernetes container runtime.

The future cluster stage is separate: Cilium, MetalLB, Multus, and Tailscale are planned, with Argo CD preferred over Flux. That stage needs its own configuration, network/IP decisions, and rollout authorization. The current Nanoserver v3 image remains unchanged; v4 removes unsupported systemd-sysupdate `Verify=` keys while retaining signed-manifest verification through the configured GPG keyring.

Miniserver profiles are not physically installed yet and remain subject to `docs/plans/miniserver-install-readiness.md`. Do not run Disko or change disks as part of this host-services stage.

## Host services and access
The opt-in `host-operations` feature on Nanoserver v4 installs headless Podman/libvirt TUI tools (`podman-tui`, `virt-top`) plus Btrfs, NVMe/SMART, network, and process diagnostics. Podman TUI uses the per-user socket; it adds no TCP listener or rootful Podman access. `virsh` and `qemu-img` are already provided by libvirt and QEMU. The separate `k3s-tools` feature installs `k9s` and `kubectl` only when explicitly selected; it is not enabled while K3s is deferred.

The appliance profile disables installed documentation. Libvirt's QEMU package is built without GTK/SDL/VNC/SPICE, OpenGL/virgl, or audio backends; manage guests headlessly through serial consoles. This keeps libvirt and Podman while removing desktop-style VM display/audio dependencies.

- Libvirt management stays on its local socket; use SSH transport for remote administration. Do not expose an unauthenticated libvirt TCP API.
- Nanoserver v4 runs Herdr 0.9.3 as `rona`'s lingering systemd user service. Herdr's machine protocol uses SSH and a per-user Unix socket; it opens no TCP listener. After deploying v4, register it from the local Herdr client with `herdr machine add <ssh-target> --label Nanoserver`.
- Herdr remote panes execute as `rona`, who has passwordless sudo on this profile, so machine access is root-equivalent. Protect it with the existing SSH authentication and only register trusted clients; no extra key or port is introduced.
- Podman does not add a listening service. This configuration does not create containers, VMs, or workloads.
- No Kubernetes API, ingress, MetalLB pool, or external service is configured in this stage.

## Persistent state

Nanoserver's root is ephemeral. Under `/persist` (mirrored NVMe), this stage preserves `/var/lib/libvirt`, `/var/lib/containers`, Rona's rootless Podman storage, and Herdr's `.config/herdr` state. The mirror protects against a single NVMe failure, but is not an off-host backup. No VM images or container workloads are created by this change.

## Rollout and acceptance sequence

1. Build and validate the Nanoserver v4 host-services bundle in CI; confirm the v4 profile has Herdr enabled, K3s disabled, and Podman/libvirt enabled.
2. Before switching Nanoserver, verify the signed v4 release is available and the appliance updater's Btrfs mirror, both boot ESPs, and `/persist` preflight passes. Keep v3 and v2 rollback images immutable.
3. Update Nanoserver through the existing `appliance-update` A/B path, reboot only after staging succeeds, then verify the active slot/version, `/dev/kvm`, `libvirtd.socket`, Podman availability, and Herdr's user service/API socket. Register the local Herdr machine profile with the SSH target. Do not create VMs or containers during this stage.
4. Miniserver installation and disk operations require their separate readiness gates and explicit authorization. Once installed, roll out host services one machine at a time and verify KVM/libvirt/Podman before continuing.
5. Defer K3s, Cilium, MetalLB, Multus, Tailscale Operator, and Argo CD until a separate cluster-stage plan and approval.

The repository continues to use one `nix-secrets` input. No cluster token is needed for this host-services stage. The already-published Nanoserver v3 image and v2 rollback remain unchanged. The currently running v3 host reports a failed generic `systemd-sysupdate.service` because it finds no generic transfer definitions; the explicit `nanoserver` component listing succeeds and verifies the signed manifest. Track that separately rather than treating it as proof that the A/B updater is unusable.

## Rollback

- Keep Nanoserver v3 and v2 bootable; never rewrite published assets.
- If v4 fails acceptance, boot the existing v3 slot and stop rollout.
- Do not format disks, provision VMs, or delete persisted data during diagnosis.
