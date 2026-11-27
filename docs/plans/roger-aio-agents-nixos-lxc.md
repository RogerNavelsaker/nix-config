# Agent NixOS deployments: LXC and WSL

## Goal

Run one ordinary NixOS LXC per agent on the CachyOS roger-aio host. Each LXC has one fixed-capacity ext4 disk image for the NixOS root and agent state. The store currently resides in each image; the user now permits sharing the host /nix/store for space savings if a safe NixOS pattern is validated. No Btrfs inside the image, A/B slots, or separate /persist filesystem. Mara's Windows deployment uses ext4 inside a WSL VHD.

The existing Debian roger-aio-agents LXC remains untouched as the rollback source.

## Guardrails

- Do not reboot the host, stop/restart Debian roger-aio-agents, transfer its production identity/data, or cut over services.
- Do not change the CachyOS host OS or unrelated services. Limit host changes to these agent containers and their storage/lifecycle plumbing.
- Preserve unprivileged mapping 0 -> 100000, length 65536; start LXCs as host user rona; keep autostart disabled.
- Do not bake contents of any /home/<agent>, /workspace, credentials, SSH host keys, Tailscale state, or live agent data into base images.
- Preserve all pre-existing nix-config changes. Do not stage unrelated work or rewrite the root flake/lockfile.
- NixOS in LXC has no guest firmware or bootloader. The host loop-mounts agent.img at /var/lib/lxc/rona/<agent>/rootfs; this is the LXC rootfs mountpoint, not a second disk.
- Never use privileged LXC, unconfined profiles, broad capability additions, or global host policy changes.

## Decisions

- LXC agents on roger-aio: Rowan, Jules, Mira, Avery. One LXC and one ext4 image per agent.
- Each agent's Unix username and primary group match its short name; guest hostname is agent-<agent>. LXC IDs and config directory names remain the short name.
- The current guest images hold the normal Nix store, devenv, and state. The user approves host-store sharing; nixcloud-container is the cited LXC example (last commit 2018-11-02). Its lxc-container.nix bind-mounts host /nix/store read-only and a per-container system profile, but requires NixOS, sets lxc.apparmor.profile=unconfined, and omits a guest Nix daemon socket/database mount. Do not apply it wholesale; an adaptation must preserve LXC confinement and guest-side Nix/devenv builds through a safe host-daemon and per-container GC-root arrangement.
- Initial image cap: 5 GiB. Format with ext4 inode ratio 1 inode per 4 KiB; the default inode ratio ran out of inodes during devenv's Nixpkgs copy despite free data blocks. Four 5 GiB images have a 20 GiB maximum, so recheck host free space before staging each.
- Use the regular NixOS flake profile and system configuration. No appliance A/B machinery or GitHub Actions image pipeline is required.
- Mara's WSL VHD also uses ext4; WSL import/boot behavior is separate from LXC and must be tested on Windows.

## Current status

- Rowan, Jules, Mira, and Avery are all RUNNING from separate 5 GiB ext4 images at /var/lib/lxc/rona/<agent>/agent.img. Each image is loop-mounted at its rootfs directory and contains the guest's root and normal /nix/store. Autostart is disabled and no /persist mount exists.
- All four original NixOS 25.11 LXC base images were built and staged. The named-account/hostname profile was evaluated and activated in place in all four guests.
- NixOS reports hostnames agent-rowan, agent-jules, agent-mira, and agent-avery. Each guest now has its own locked Unix user and primary group (rowan/jules/mira/avery), UID/GID 1000, and /home/<agent>. The former /home/agents home was moved so its contents were preserved; Rowan.s Nix tarball-download cache was trimmed during disk recovery; a later Devenv smoke recreated it after its remaining partial Git metadata was removed.
- Passwordless sudo is scoped to the named account inside each unprivileged guest. OpenSSH remains disabled and root remains locked. Account name, home, password lock, hostname, and sudo were verified in all four.
- Each image is formatted with -i 4096 for 1,310,720 inodes. Default formatting (327,680 inodes) failed during devenv's Nixpkgs copy despite free data blocks. The original sandboxed normal-store build and disposable devenv shell with pkgs.hello passed in each guest.
- A post-identity Rowan-only nixpkgs#hello build as user rowan passed. A subsequent fresh devenv shell evaluation filled Rowan's 5 GiB filesystem and failed with ENOSPC; that retry did not complete and was not repeated in the other guests. Temporary test projects were removed. Nix GC removed unreferenced store paths and retained the current and previous system generations; Rowan had 2.9 GiB free before shared-store setup and has 2.8 GiB free now; Jules, Mira, and Avery each had about 1.4 GiB at the prior check. The independent-store retry failed; a later small Devenv shell passed through the shared host store.
- Per-container LXC configs retain unprivileged mapping 0 -> 100000, length 65536, lxc.apparmor.allow_nesting = 1, and autostart disabled. No privileged mode, keyctl, broad capability, or host-wide policy was enabled.
- The guest root and store are ext4. The host owns each container directory as mapped root UID 100000 and group rona (mode 0770), allowing user-namespace root to traverse the rootfs while host user rona retains management access.
- DHCP addresses: Rowan 10.0.3.226, Jules 10.0.3.83, Mira 10.0.3.204, Avery 10.0.3.107. The earlier sys-kernel-debug.mount and logrotate failures are resolved in all four profiles: the debugfs mount is suppressed, and a guest-owned logrotate config is staged in /run for both the check and hourly service. All four NixOS switches returned 0; checkconf passes in each, and an actual Rowan logrotate service smoke run succeeded without rotating its below-threshold wtmp/btmp files. LXC attach emits a cgroup-scope warning, but commands complete.
- User selected direct Tailscale networking. Each LXC has a per-container /dev/net/tun bind and cgroup allow for char device 10:200; create/delete probes passed. CAP_NET_ADMIN was already present in each user namespace; no extra capabilities or host-wide policy changes were made. Tailscale 1.90.9 is active in all four, each enrolled with its own preapproved tagged key streamed through stdin. The authkeys and temporary host staging directory were removed after enrollment; the four guests retain independent Tailscale state and each reports Running, one tag, an assigned IP, and tailscale0 in its own network namespace. The user confirmed the ACL was updated and approved Tailscale SSH; RunSSH=true is now set in all four guests, while OpenSSH remains disabled.
- Debian remains RUNNING and untouched with PID 3579138; Rowan PID 1939277, Jules 1822809, Mira 1823388, Avery 1824022. rona's five veth slots are consumed by Debian plus four agents. Host free space is 9.6 GiB after all four shared-store and Devenv tests (filesystem 98% used).
- Shared-store rollout is live on all four guests. All four Nix clients use host daemon 2.35.2 from guest Nix 2.31.5 and report Trusted: 0. Each untrusted sandbox probe could not read a host-only /tmp canary. Host store, DB, and daemon-socket mounts are read-only; separate per-agent profile and GC-root mounts are writable. Current system profiles point to host store paths; each rootfs local store remains intact beneath the mounts. No local-store cleanup, host GC, or fstrim has occurred.
- The first Rowan Devenv retry failed because capacity recovery left an invalid partial tarball-cache Git repository. Removing only that broken cache directory let Devenv 1.11.1 recreate it; a disposable pkgs.hello shell passed in all four guests and temporary projects were removed. Rootfs free space is Rowan 2.8 GiB, Jules 1.3 GiB, Mira 1.3 GiB, Avery 1.4 GiB.
- Nix store root-query commands (including --gc --print-roots and --query --roots) remove stale auto-root symlinks as a side effect. The pilot query removed stale roots pointing to the deleted smoke project and a guest-only cache path. Current system profiles are direct host-visible roots. Auto-root symlinks that target guest-only paths such as /home/<agent> are not host-resolvable; do not run host GC until their rooting behavior is addressed. No Nix GC was run.
- Read-only host-namespace inspection of all four GC-root trees confirms auto roots still point at guest-absolute paths such as /nix/var/nix/profiles/system-N-link, /home/<agent>/..., and /run/current-system; these are absent or resolve to the host profile instead. The authoritative system-N links are present directly under each host per-container profile directory. No host /home aliases were created. Do not treat the shared GC-root bind alone as proof that home-based roots survive host GC.

## Implementation gates

1. Build and evaluate the normal NixOS profiles. All four profiles and original rootfs images were built; the updated profiles evaluate for all four.
2. Create one ext4 filesystem image per agent, install the standard NixOS LXC rootfs with mapped ownership, and verify ext4 capacity. Passed for all four.
3. Run all four LXCs unprivileged with autostart disabled. Verify agent-<agent> hostname, matching locked user, UID/GID mapping, DHCP, agent-only NOPASSWD sudo, SSH-disabled state, ext4 root, and ordinary Nix store. Passed.
4. Initial sandboxed normal-store build and Devenv shell passed in all four. The post-identity Rowan repeat exhausted its private 5 GiB store; after the shared-store rollout, all four passed an untrusted sandboxed derivation and a small Devenv shell.
5. Per-container TUN access is configured and verified for all four. All four agents are enrolled via distinct preapproved tagged keys, report Tailscale BackendState=Running, and have RunSSH=true under the user-confirmed ACL. Temporary keys were deleted; OpenSSH remains disabled.
6. Validate Mara's WSL VHD/ext4 deployment separately on Windows.
7. Shared-store rollout passed for all four guests: read-only mounts, untrusted host-daemon sandbox builds, writable per-agent profiles/GC-root directories, and small Devenv shells. Existing local stores remain intact; duplicate-store cleanup and fstrim are deferred.

## Rollback

Keep Debian roger-aio-agents running and untouched. A failed agent image stays stopped; rollback uses the existing Debian LXC or an ordinary whole-image backup. There is no A/B slot controller. Do not enable autostart or cut over services without separate approval.

Multi-host orchestration remains future work.

## Approved shared-store adaptation

The user approved adapting the shared-store design for these unprivileged LXC guests. Use the NixOS nixos-containers mount model, not nixcloud-container's unsafe wrapper:

- Bind host /nix/store, /nix/var/nix/db, and /nix/var/nix/daemon-socket into each guest read-only.
- Give each guest its own host-side /nix/var/nix/profiles/per-container/<agent> and /nix/var/nix/gcroots/per-container/<agent> directories, bind-mounted read-write at the guest's normal profile and GC-root paths. Seed these from the existing guest profiles/roots.
- NixOS boot.isContainer already sets NIX_REMOTE=daemon; disable only the guest nix-daemon.socket and nix-daemon.service so clients use the host socket and no local daemon competes for it.
- Host Nix 2.35.2 currently reports allowed-users = *, trusted-users = root, sandbox = true, build-users-group = nixbld; guest Nix is 2.31.5. An untrusted host user connected to the daemon with Trusted: 0, and a sandbox canary build could not read a host-only /tmp file. Do not change host Nix settings, trusted users, AppArmor, capabilities, or other host policy.
- Shared builds execute through the host daemon and consume host storage/resources. The guests remain untrusted clients; no agent gets Nix trusted-user status. No secrets may enter the shared store.

### Rollout gates

1. Evaluate the guest config changes and check that Nix clients still select daemon, while guest daemon socket/service are disabled. Check formatting and all four profiles.
2. Measure closure sizes and host free space before importing any paths. Import each existing system-generation closure (and referenced user profiles/GC roots) into the host store; verify all profile targets exist in the host store.
3. Pilot Rowan only: seed its per-agent profile/GC-root directories, add only the approved bind mounts to its LXC config, and restart Rowan without changing UID maps, AppArmor, autostart, or capabilities. Keep its original ext4 store intact for rollback.
4. Verify read-only host store/database/socket mounts, host daemon version and untrusted status from inside Rowan, current and previous system generations, and an untrusted sandboxed derivation build. Run a small devenv shell smoke without fresh large Nixpkgs evaluation. Confirm system-profile paths are host-visible roots. Guest-home auto-roots are not host-resolvable and must not be assumed safe for host GC.
5. Passed for Jules, Mira, and Avery one at a time after Rowan. Never stop or modify Debian roger-aio-agents.
6. Deferred: remove duplicated files hidden below the shared /nix/store mount and fstrim each ext4 loop filesystem only after verifying image rollback and discard. Current system profiles are host-visible; arbitrary guest-home auto-roots may not be. Do not run host Nix GC until a safe host-visible rooting strategy is validated.

### Rollback and verification

For the Rowan pilot, retain the old image store and a backup of its LXC config until the shared mounts and guest builds pass. If the mount or daemon path fails, stop Rowan, remove the shared-store include, restore its prior config/system generation, and restart against its untouched local store. Apply the same one-container-at-a-time rollback for later agents. Do not alter the Debian rollback LXC or transfer production identity/data.

Required checks include standalone nix flake check --no-build for the agent flake, nixfmt --check for changed Nix files, root-flake evaluation of all four profiles, live LXC mount/options and Nix daemon status checks, untrusted nix build plus small devenv shell in each guest, and GC-root inspection. Note: Nix root-query commands may remove stale auto-root symlinks; do not run host GC until guest-home root mapping is understood.

### For Executor

Read order: this section; hosts/rowan/configuration.nix; NixOS virtualisation/container-config.nix, services/system/nix-daemon.nix, and virtualisation/nixos-containers.nix; live LXC configs under /var/lib/lxc/rona/{rowan,jules,mira,avery}.

Assumed working state: preserve the existing dirty/staged repository; all four named-agent LXCs are running; Debian roger-aio-agents stays running and untouched; host Nix daemon settings remain unchanged.

Owned files/state: hosts/rowan/configuration.nix, this plan, and only the four agent LXC configs plus their per-agent Nix profile/GC-root directories. Do not touch unrelated files or stage changes.

Verification commands: standalone nix flake check --no-build with extra-experimental-features nix-command flakes for path hosts/rowan; nixfmt --check; root-flake evaluation; live LXC mount, daemon, build, devenv shell, and GC-root checks described above.

## Tailscale enrollment: preapproved tagged agent keys

### Goal and non-goals
Bring Rowan, Jules, Mira, and Avery online as separate Tailscale nodes using their already-preapproved, individually tagged authkeys. Keep each key out of the Nix store, repository, and persistent base image. The user confirmed the ACL update and authorized enabling Tailscale SSH; OpenSSH remains disabled. Do not change host Tailscale, host firewall/policy, LXC UID maps, autostart, or Debian.

### Context and blast radius
All four guests already have isolated /dev/net/tun access and passed a create/delete probe. Their system profiles are built from hosts/rowan/flake.nix and shared hosts/rowan/configuration.nix. Four authkeys were staged in host /run/tailscale-authkeys on tmpfs, streamed only to their matching guests, and removed after enrollment. The host maps each guest root to UID 100000; per-agent runtime config belongs under /var/lib/lxc/rona/<agent>/.

### Completed result
All four named NixOS profiles were built and switched. Tailscale 1.90.9 is active and authenticated in every guest; each reports BackendState=Running, exactly one tag, an IPv4 address, and tailscale0 in its separate network namespace. The one-time authkey was streamed through stdin and removed from host /run; restarting tailscaled after key removal restored Running from that guest's persistent state. Initial enrollment omitted --ssh; after the ACL update, NixOS extraSetFlags enabled it with tailscale set --ssh. The initial activation failures (debugfs mount and logrotate config ownership) were resolved in the shared profile; current switches return 0, and logrotate runs from a guest-owned /run copy.
### Steps and verification gates
1. Enable services.tailscale in hosts/rowan/configuration.nix. Keep authKeyFile and key material out of Nix; after ACL approval configure services.tailscale.extraSetFlags = [ "--ssh" ]. Evaluate/build all four named profiles using the locked standalone agent flake. Verify no key contents are referenced by any build input.
2. Switch the shared NixOS profile in each guest, one at a time, using the archived flake source in the shared host store. Verify tailscaled is active while each guest is still unauthenticated.
3. Stream only that guest's authkey from the host /run file through lxc-attach stdin into tailscale up; do not print, log, or persist the key. Initial enrollment omitted --ssh; after the ACL update, enable it declaratively with extraSetFlags. Verify BackendState=Running, an assigned Tailscale IP, and tailscale0 in that guest's network namespace. The CLI briefly receives the key as an argument inside that same guest.
4. Remove each host /run key after successful enrollment. Keep only the independent Tailscale state in that guest's ext4 image. Restart tailscaled and verify reconnection without a key file, while the shared Nix daemon still reports Trusted: 0.
5. Update this status and the Rowan README. The user confirmed the ACL update and approved Tailscale SSH; verify RunSSH=true while keeping OpenSSH disabled.

### Rollback
If a profile build or enrollment fails, leave that guest's staged key available for retry and use its previous NixOS system generation. Do not remove successful agents' state or touch Debian. Never copy or mount an authkey into a persistent guest file.

### Resolved ACL decision
The user confirmed the ACL was updated; Tailscale SSH is enabled on all four. End-to-end client access was not tested because no remote client identity was supplied.

## Investigation and resolution of LXC unit failures

The root causes were confirmed, then fixes were built and activated in all four guests.

- sys-kernel-debug.mount: NixOS systemd.nix included this unit in sysinit.target wants even with boot.isContainer=true. The upstream unit tried to mount debugfs at /sys/kernel/debug and all four unprivileged guests received permission denied; the host mount is not shared into the guests. Resolved with systemd.suppressedSystemUnits = [ "sys-kernel-debug.mount" ] in the shared profile. No privileged LXC, broad capabilities, or host debugfs exposure was added. All four now report LoadState=not-found and sysinit.target is active.
- logrotate: the generated config was UID:GID 0:0 in the host store, but each guest saw 65534:65534 because host root is outside map 0 -> 100000. Logrotate rejected it. The generated rules only rotate /var/log/btmp and /var/log/wtmp (monthly, minsize 1 MiB); /var/log also contains journald files. The regular hourly logrotate.service had failed as well as the debug checker.
- Resolved both logrotate units by copying config.services.logrotate.configFile to /run/logrotate.conf as guest root in each unit preStart, and overriding ExecStart to use that copy. All four have /run/logrotate.conf owner 0:0 mode 0644 and logrotate-checkconf.service Result=success. A real logrotate.service smoke run succeeded in Rowan; wtmp (3,456 bytes) and btmp (0 bytes) were unchanged because they are below the 1 MiB threshold. No rotation was forced.
- The generated config is currently self-contained. If future settings add include directives, their files must also be copied into the guest namespace and made guest-root-owned. All four final NixOS switches returned 0; systemctl --failed is empty in all four. Tailscale remains Running and RunSSH=true.
