# Nanoserver workload Nix runtime

Status: design/prototype only. A separately installed Nix workload layer is in scope; live installation/deployment is not authorized by this plan.

## Goal

Define and prototype an independently updateable Nix-managed workload layer for Nanoserver that cannot mutate or switch the booted NixOS appliance generation.

## Non-goals

- Do not bake the workload Nix installation into the appliance image or use it to evaluate/switch the NixOS base generation.
- Do not let workload Nix change boot, base-image `/etc`, host users, host networking, appliance-owned systemd services, or the appliance update mechanism.
- Do not install on or deploy to a live Nanoserver, publish a production workload artifact, reboot, or perform disk operations. Disposable local VMs/containers and test-only artifacts are allowed for the prototype.
- Do not grant workload code unrestricted root, `sudo`, rootful Podman, or `qemu:///system` access.
- Do not include secrets in Nix derivations, workload closures, OCI layers, logs, or artifact metadata.
- Kubernetes/GitOps remains out of scope.

## Context and existing decisions

- Seed `nix-config-82e1` requires a threat model, explicit allowed/denied operations and paths, rollback, and a prototype proving workload updates cannot change the booted OS generation or host configuration.
- Architecture decision `mx-965c4d` keeps workload Nix separate from the image-based-appliance system generation. The intended model is a separately installed Nix workload layer atop the running appliance, similar to installing Nix on a non-NixOS host; it may manage workload outputs but never the base NixOS generation. Rootless Podman/Quadlet is the first target. Libvirt access, if later needed, must use a fixed host-owned allowlisted activator.
- `hosts/features/opt-in/host-platform/virtualisation.nix` enables Podman and libvirt; `persistence.nix` preserves `/var/lib/containers`, `/var/lib/libvirt`, and Rona's rootless Podman storage under `/persist`. No workload is currently declared there.
- `docs/plans/nanoserver-miniserver-platform.md` explicitly excludes creating workloads during the host-platform rollout. The base appliance image disables its own runtime Nix and system switching; this does not prohibit a separately installed workload-Nix layer.
- `docs/RESCUE-OPERATIONS.md` contains dated deployment observations, not fresh live-host evidence. Verify current host state read-only before any future rollout.
- A local Nix 2.35.2 proof ran `nix run --store <temporary-root> nixpkgs#hello` successfully. The local chroot store kept physical paths under `<root>/nix/store` and metadata under `<root>/nix/var/nix`; it did not use the daemon. This demonstrates the local chroot-store mechanism on the development host only—not its compatibility with the appliance, persistence, Nanoserver user/mount namespaces, or Podman service integration. Store entries were read-only and required permission restoration for temp cleanup.

## Boundary to prototype

Install the workload Nix client/runtime separately from the image-based NixOS generation, with its own documented lifecycle and narrowly scoped workload outputs. It must not invoke `nixos-rebuild`, mutate the base appliance profile, or write configuration into appliance-owned paths. The first candidate to test is a local chroot store rooted in persistent storage: Nix documents that its logical store remains `/nix/store`, while physical store/state paths are rooted under the chosen directory and builds/runs occur chrooted. This avoids using the appliance's read-only versioned `/nix/store` and avoids a host Nix daemon, but requires working Linux mount/user namespaces and a way for rootless Podman/Quadlet services to consume workload outputs. If that boundary cannot support service activation, compare a persistent overlay store and a separately installed multi-user daemon; do not assume the standard installer is compatible with the appliance's ephemeral root or systemd policy.

### Off-host prototype evidence

The focused check `checks.x86_64-linux.nanoserver-workload-nix` passes in a disposable QEMU NixOS VM. A non-root `workload` user writes and reads a local chroot store on a separate ext4 virtual disk with the Nix daemon disabled; after VM shutdown/start, the stored path and contents remain available. The test asserts the base `/run/current-system` toplevel and digest of the complete top-level `/nix/store` path set are unchanged. Its Nix CLI is a test-only bootstrap package in the VM's system profile.

The focused check `checks.x86_64-linux.nanoserver-workload-podman` also passes in QEMU. It copies a test-only OCI archive into the user-owned chroot store, loads it with rootless Podman, and starts a generated user Quadlet service. The fixture writes only to its declared `/persist` state bind; it cannot see a host `/run` marker, and the test disables and verifies absence of rootful Podman/Docker sockets. In this VM, `dockerSocket.enable = false` alone did not disable the rootful Podman API socket; the fixture also masks `systemd.sockets.podman` and `systemd.services.podman`. The base toplevel and `/nix/store` path-set digest remain unchanged. The artifact is unsigned and built as a test fixture, not by the workload store.

The focused check `checks.x86_64-linux.nanoserver-workload-appliance` now passes in a disposable QEMU VM with tmpfs `/`, an EROFS read-only base `/nix/store`, and a separate Btrfs `@persist` disk. It copies a test-only Nix runtime and Bash closure into a persistent local store, registers that closure, then uses the copied CLI as the unprivileged `workload` user to build a tiny Bash-based derivation with `--offline` and `sandbox = true`, add and run a probe, and verify both outputs after VM power cycle. It also stages the package-only `nanoserver-workload-test` output (`pkgs.hello`, a 31.8 MiB runtime closure) into the workload store and runs it from inside that store's chroot as the unprivileged workload UID/GID both before and after power cycle. This confirms the package's runtime dependencies resolve from the workload store rather than the base store. The volatile root marker disappears; the CLI, local store database, derivation output, and workload data persist; the base toplevel and `/nix/store` path-set digest remain unchanged; and no Nix daemon/socket is present. The derivation declares its builder with `builtins.storePath` and `inputSrcs`, preserving the store-path context needed for Nix to expose the builder closure inside its build chroot. A root-owned test command creates a private mount namespace and drops to the unprivileged user; the probe confirms it cannot write `/etc`. This is test-fixture provisioning, not a production installer or signature-verified artifact.

A test-only attempt to put a standard package `.drvPath` in the copied workload closure pulled its complete derivation graph (1,135 references / about 569 MB). The fixture instead roots the package output closure, which is the runtime artifact the workload consumes; its small offline derivation build remains a separate test. A host-side Nix binary-cache signing experiment was blocked because the multi-user Nix daemon ignored the untrusted client's `secret-key-files` setting. In the disposable appliance-like VM, a root-only ephemeral key is generated, the unsigned file cache is captured before signing, and `nix store sign` signs every path in the workload generation closures. Recursive verification succeeds; importing the unsigned cache with `require-sigs = true` fails without installing the requested generation, while importing the signed cache succeeds and verifies using only the public key. The test activates v1 → v2 → v1 and confirms the selected v1 workload remains executable after VM power cycle. This verifies native Nix signature and activation primitives with test-only fixtures; it does not change the external production signer or resolve production trust-key distribution.

The earlier `No such file or directory` builder failure was traced to the diagnostic derivation using plain string literals for its builder store path. `strace` showed Nix's build chroot omitted that path; the same copied executable ran directly and from a rootless chroot. Using a typed `builtins.storePath` value plus `inputSrcs` caused Nix to mount the builder closure into the build chroot, and the sandboxed build then passed. This resolves the minimal fixture's builder-launch failure, but does not establish support for arbitrary workload derivations or a full package build workflow. The namespace probe does not establish a complete host-path allowlist or read isolation. Appliance-image compatibility, production OCI/Quadlet signing, and real hardware behavior remain unproven; the test-only signed Nix-cache and two-version Podman rollback fixtures do not establish production trust bootstrap.

Use an immutable, signed workload generation and rootless Podman/Quadlet as the first workload interface. Build/signing may be external, but the separately installed runtime on the appliance is the intended consumer/operator of workload generations. Keep signature verification and trust bootstrapping separate from secret material. Initial workload scope is one stateless rootless Podman service plus a separately mounted persistent state directory beneath `/persist`. Do not exercise libvirt operations in the first prototype; document the later activator contract separately.

## Threat model and policy

### Allowed in the initial prototype

- Evaluate and build only separately addressable workload outputs, never `nixosConfigurations`; whether derivations build locally or on remote builders remains a design choice.
- Verify artifact signature and digest before activation; retain the prior immutable digest for rollback.
- Run a workload as the unprivileged `rona` account through rootless Podman and a user Quadlet unit.
- Bind only an explicitly allowlisted workload state directory under `/persist`; keep image/root filesystem and configuration read-only where practical.
- Keep runtime-only credentials in a secret delivery path that is not a derivation input or artifact layer; do not implement secret delivery until its owning `nix-secrets` contract is reviewed.

### Denied

- Workload Nix access to the base NixOS profile, system generation, or system switching (`nixos-rebuild`); the separate workload runtime may evaluate/apply only its declared workload outputs.
- Writable binds to `/`, `/etc`, `/boot`, `/nix/store`, `/nix/var`, `/run`, host home directories, or host systemd control sockets.
- Privileged containers, host PID/network namespaces, added capabilities, arbitrary devices, rootful Podman socket, host SSH agent, or arbitrary hooks/commands.
- Workload control over system units, user accounts, firewall/network configuration, boot entries, appliance update state, or another workload's state.
- Any direct access to libvirt. A future fixed activator must allowlist operation, domain, disk path under `/persist`, network, and lifecycle transitions; it must reject arbitrary shell, XML, paths, and hooks.

## Implementation and verification steps

1. **Select artifact and trust format.** Prototype Nix's native signed file binary cache for immutable workload-generation paths, requiring `nix copy` signature checks and `nix store verify --recursive --sigs-needed 1` before activation. The disposable VM builds v1/v2 executable generation outputs in a source local store, captures the unsigned cache before adding an ephemeral root-only test signature to every closure path, rejects an unsigned-cache import into a separate persistent runtime store, verifies signed imports, then activates v1 → v2 → v1 and checks v1 after power cycle. The target-version package outputs are input-addressed scripts whose shebang references Bash; the signature-authenticated closure includes that runtime dependency. This validates native Nix cache trust and generation selection primitives only; production OCI/Quadlet generation signing and the external production signer/public-key distribution contract remain unresolved. Never generate or publish production signing credentials; tests may create disposable test keys inside their throwaway VM.
2. **Add a separate workload output.** Add a minimal workload flake output outside `nixosConfigurations`, with no dependency on host configuration evaluation. Verify the separately installed Nix runtime can select/evaluate/apply it independently and existing Nanoserver image outputs remain unchanged.
3. **Prototype separate installation and activation off-host.** Three QEMU checks pass: persistent local chroot-store state survives VM power cycle; rootless Podman consumes an OCI artifact through a user Quadlet; and an appliance-like VM with tmpfs `/`, a read-only EROFS base store, and persistent Btrfs state can copy a test-only Nix runtime, build a minimal Bash derivation with sandboxing enabled, add/run a store-backed workload as an unprivileged user, and retain outputs after power cycle without changing the base system toplevel or `/nix/store` path set. The appliance-like test additionally imports and runs a package-only Nixpkgs output whose complete runtime closure is staged in the persistent workload store. The fixture declares build-time store paths with `builtins.storePath` and `inputSrcs` so the builder closure is mounted into Nix's chroot; stage runtime output closures, not `.drvPath` build graphs. Its disposable native-cache signing test rejects the unsigned cache, verifies signed closure imports, and activates v1 → v2 → v1 across a power cycle, using an ephemeral test key generated inside the VM and a distinct persistent runtime store. This validates Nix trust/update primitives, not a production OCI/Quadlet signing pipeline; production signing remains external and trust-key distribution through `nix-keys` is unresolved. If the boundary fails, compare the documented overlay-store/daemon alternatives.
4. **Prove confinement.** Add automated negative tests showing the workload cannot write host `/etc`, boot/store paths, control system services, obtain a rootful Podman/libvirt socket, or access paths outside the declared bind allowlist. Test the state bind is the only writable host path.
5. **Prove OS-generation independence.** Record the appliance system toplevel/generation before and after workload activation and rollback; assert it is unchanged, no NixOS system switch occurred, and the separately installed workload runtime/daemon remains confined to its declared store and workload outputs.
6. **Document deployment gate.** Update host-platform documentation only after the prototype passes. Any host runtime installation, secret provisioning, workload publication, or Nanoserver rollout requires separate explicit approval and a fresh access/recovery check.

## Verification

- Focused appliance-like QEMU check passed after adding ephemeral signed/unsigned cache import, recursive signature verification, v1 → v2 → v1 activation, and post-reboot execution. The unsigned import was rejected without installing the path; the signed closure imported and verified using only the test public key. The signing key is generated in the disposable VM and is not production trust evidence.
- Full `nix flake check --option eval-cache false -L` passed after the latest workload-test edits. The flake currently targets `x86_64-linux` only; `aarch64-linux` is unsupported and is not a planned verification target.
- Focused QEMU store-persistence check: `nix build .#checks.x86_64-linux.nanoserver-workload-nix` (passed).
- Focused QEMU rootless Podman/Quadlet check: `nix build --option eval-cache false --no-link .#checks.x86_64-linux.nanoserver-workload-podman -L` passed with ephemeral VM-generated Nix signing keys: unsigned input-addressed OCI image paths are rejected, signed imports verify in a separate persistent workload store, and rootless Quadlet activates v1 → v2 → v1 while preserving workload state. Rootful sockets remain absent and base system/store are unchanged. `nix store add` creates content-addressed paths for which Nix does not require signatures, so the fixture uses derivation-produced input-addressed OCI paths to exercise signature rejection. The OCI archives themselves are Nix-signed store outputs; production registry/image-signature verification and trust-key distribution remain untested.
- Focused appliance-like QEMU check: `nix build --option eval-cache false --no-link .#checks.x86_64-linux.nanoserver-workload-appliance -L` (passed for an unprivileged sandboxed Bash derivation build, a 31.8 MiB Nixpkgs package runtime closure, Btrfs persistence, and unchanged base store/system toplevel; it also rejects an unsigned cache, accepts/verifies the signed test closure, and activates v1 → v2 → v1 with v1 execution after reboot).
- These VM tests do not establish appliance-image compatibility, production signing/trust bootstrap, arbitrary-workload safety, complete path isolation, or hardware behavior.
- Compare the booted-system toplevel before/after in the prototype and assert equality.
- `git diff --check` and Nix formatting checks.
- Do not claim real hardware/deployment behavior from flake evaluation or a local container test.

## Rollback

Remove only the new workload output, prototype fixture, tests, and this plan. Do not modify the appliance boot/system generation or persistent host state. For a prototype workload rollback, restore the previous pinned artifact digest and stop/remove only the test user unit/container.

## Open questions — resolve before implementation

- Native Nix signed/unsigned file-cache trust primitives pass in the disposable VM. Does production need a separate signed OCI archive/attestation in addition to the Nix-signed generation closure?
- How should the production verification public key be distributed through the separate `nix-keys` trust/bootstrap contract without changing appliance trust policy?
- What exact runtime state path and quota/cleanup policy should be used under `/persist`?
- Is there an initial real workload to validate, or should the prototype use a harmless fixture service?
- Where must the separately installed Nix store, daemon state, profiles, and systemd units live so image updates and ephemeral-root boots cannot corrupt or silently remove them? The appliance already uses a versioned `/nix/store`; prove the layout before installation.
- Does the local chroot-store candidate support the required user Quadlet/rootless Podman service lifecycle without exposing host paths? If not, which alternative boundary is acceptable: a persistent overlay store, a constrained daemon, or an isolated runtime container?
- If a daemon is needed, can the standard multi-user Nix daemon be safely installed on this NixOS appliance, or must it run inside a stronger boundary? Specify trusted users, build users, writable paths, and permitted commands.
- Is the Nanoserver v4 platform rollout complete and healthy enough to begin a workload prototype? Check current status read-only; do not infer it from dated docs.
- What is the narrowly allowed libvirt lifecycle API for a later phase? Keep libvirt out of the initial prototype.

### For Executor

Read order: this plan; Seed `nix-config-82e1`; Mulch decision `mx-965c4d`; `docs/HOST-PLATFORM.md`; `docs/RESCUE-OPERATIONS.md`; `hosts/features/opt-in/host-platform/{virtualisation,persistence}.nix`; rootless Podman/Quadlet module documentation.

Assumed working state: substantial unrelated changes exist in this checkout and adjacent secret/key repositories. Preserve all staged, unstaged, encrypted, and untracked state. Do not switch branches or synchronize unrelated stores.

Owned files: workload-specific output/prototype/tests and this plan only; do not edit appliance boot/update modules, secrets, signing credentials, or live host state.

Verification commands: `nix flake check --option eval-cache false -L`, focused workload isolation test, Nix formatter, and `git diff --check`. No live deployment command is part of this plan.
