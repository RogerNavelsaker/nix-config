# Nanoserver operational CLI tools

## Goal
Install a small headless operations toolkit for current Nanoserver host services, make Nushell available without changing the login shell, and provide Kubernetes clients only through an inactive opt-in feature.

## Non-goals
- Do not enable K3s, add kubeconfig/credentials, or install K9s/kubectl in the v4 profile.
- Do not create or configure Podman/libvirt workloads, expose TCP sockets, or grant new privileges.
- Do not install a desktop environment, virt-manager, or virt-viewer.
- Do not deploy, publish, reboot, or alter disks.

## Context
- Nanoserver v4 host platform already includes libvirt, QEMU, and Podman. Its system package closure includes `virsh` and `qemu-img`.
- Locked Nixpkgs provides `podman-tui`, `virt-top`, `nvme-cli`, `smartmontools`, `ethtool`, `tcpdump`, and `btrfs-progs`.
- Podman TUI uses Podman's API and requires the Podman user socket; NixOS Podman config already enables user socket activation. It adds no TCP listener.
- `k9s` and `kubectl` are available as packages but K3s remains deferred from the current rollout.
- The Home Manager shell feature already uses Fish and modern CLI replacements. Adding `nushell` to `home.packages` makes `nu` available without enabling Nushell's HM program or changing the account's shell.

## Steps
1. Add `nushell` to the Home Manager shell package list only. Verify the Nanoserver HM generation builds and Fish stays enabled.
2. Add a top-level opt-in `k3s-tools` host feature installing only `k9s` and `kubectl`; leave it unselected. Verify Nanoserver v4 has neither package and K3s remains disabled.
3. Add `host-operations.nix` with `btop`, `nvme-cli`, `smartmontools`, `btrfs-progs`, `ethtool`, `tcpdump`, `podman-tui`, and `virt-top`; opt into it in Nanoserver v4 A/B only. Existing `virsh`/`qemu-img` need no duplicate packages.
4. Assert in `tests/host-platform.nix` that the operational tools are present in v4, Kubernetes tools remain absent, K3s stays disabled, and no GUI dependencies enter the QEMU closure. Document the toolbox and boundaries in `docs/HOST-PLATFORM.md`.

## Verification
- Build the `home-rona@nanoserver-01` check.
- Build the `host-platform` check and Nanoserver v4 update bundle; verify bundle SHA256SUMS and the 1.9 GB limit.
- Run the repository format check, `git diff --check`, and full `nix flake check --option eval-cache false -L`.

## Rollback
Remove the new opt-ins/module and Nushell package entry. No runtime change occurs until an explicitly authorized deployment.

### For Executor
Read order: this plan; `users/features/default/shell.nix`; `hosts/features/opt-in/host-platform/virtualisation.nix`; `hosts/nanoserver-01/configurations.nix`; `tests/host-platform.nix`; `checks.nix`; `docs/HOST-PLATFORM.md`.

Assumed working state: unrelated dirty changes and the earlier Herdr work exist; preserve them. No live deployment is authorized.

Owned files: this plan, Home Manager shell module, new `k3s-tools` and `host-operations` modules, Nanoserver v4 configs, host-platform checks, and docs.

Verification commands are listed above. Do not enable K3s tools, K3s service, or run workload-management commands.