# NixOS Rescue ISO

RAM-only, headless NixOS rescue/installer ISO. GRUB selects the network policy explicitly; it never guesses that a quiet network is isolated. Every boot mode passes `copytoram`: the initrd copies the ISO contents to RAM before mounting the compressed Nix store, so the boot medium can be detached after stage 2 starts. Ensure the machine has enough free RAM for the ISO payload plus the running system.

## Security model

- The ISO carries the encrypted pass store and encrypted SOPS files, not decrypted private SSH keys or a build-time password hash.
- Initrd tries to unlock the ISO host SSH identity with GPG/YubiKey for up to the configured timeout (180 seconds in this flake). On success, the identity lives in `/run` only. sops-nix uses it at target runtime to install the `rona` password hash and runtime secrets, then removes the identity.
- If the injected archive is missing, GPG setup fails, or unlock times out, initrd powers off before stage 2. No network, SSH, DHCP, Wi-Fi, or Tailscale service starts.
- Root SSH and empty-password authentication are disabled in every mode.
- Initrd uses `pinentry-tty`; an isolated dummy-value test confirmed input is not echoed, and QEMU displayed the target PIN prompt with the YubiKey attached. One QEMU run reported the host identity unlocked into RAM and entered stage 2; the assistant did not receive or enter a PIN.

## Network modes

Select one of these entries in GRUB. **WAN is the default.** The mode is fixed for that boot; there is no DHCP-timeout or host-count inference.

| GRUB entry | Network behavior | Remote access |
|---|---|---|
| **WAN** | Wired DHCP client; no DHCP server; iwd auto-connects to the SOPS-provisioned Wi-Fi profile after unlock | Normal OpenSSH is disabled. After network and SOPS are available, the ISO joins Tailscale with Tailscale SSH enabled; tailnet ACLs control access. |
| **LAN** | Wired DHCP client; no DHCP server; Wi-Fi is manual after unlock | `rona` password SSH after SOPS activation. Tailscale is manual after unlock. |
| **Rescue LAN** | Wired static `192.168.77.1/29`; DHCP pool `192.168.77.2–192.168.77.6` (five leases); no router, DNS, or IP forwarding; Wi-Fi is manual after unlock | `rona` password SSH after SOPS activation. Tailscale is manual after unlock. |

Use **Rescue LAN only on an isolated cable**. Its DHCP server is enabled because that entry was explicitly selected; it is not safe to connect that interface to a shared LAN.

## Build and run

```bash
nix develop
iso build
iso run
iso stop
```

`iso build` creates the ISO and Ventoy injection archive. The archive contains encrypted key material; the target unlocks it during initrd. No YubiKey PIN is needed to build the ISO.

The default QEMU boot entry is WAN. QEMU must receive the Ventoy-injected archive and a YubiKey for the normal path to reach stage 2. Without a successful unlock, the VM powers off after the initrd timeout by design.

## After unlock

### Read-only hardware inventory

The ISO includes `nixos-facter` for offline hardware inventory. Run a restricted probe into `/run` (tmpfs):

```bash
sudo nixos-facter --hardware memory,pci,cpu --log-level error --output /run/nixos-facter.json
```

The default Facter probe set can include hardware serials; keep reports in RAM, use only the required hardware probes, and sanitize before copying facts into the repository. `lsblk` is also available for read-only disk inspection. Never run Disko or `nixos-anywhere` until targets are explicitly verified and authorized.

### LAN or Rescue LAN

SSH to the published `rescue-<suffix>.local` name or the DHCP/static address as `rona`, using the SOPS-managed password. The user is a non-root administrator; root SSH remains disabled.

In LAN or Rescue LAN, Wi-Fi stays disconnected until requested. After sops-nix has installed the iwd profile, connect using the saved SOPS passphrase without entering it again:

```bash
sudo rescue-wifi-up
```

If the machine has multiple wireless interfaces, pass the desired interface, for example `sudo rescue-wifi-up wlan0`. The generated iwd profile sets `[Settings] AutoConnect=true` only for WAN; LAN and Rescue LAN profiles set it to `false`.

Tailscale is also manual in these modes:

```bash
sudo rescue-tailscale-up
```

The command uses the runtime SOPS auth key, enables Tailscale SSH under tailnet ACLs, and removes the auth-key file after joining successfully. Tailscale daemon state is memory-only.

### WAN

After runtime SOPS activation and network availability, the ISO automatically joins Tailscale with `--ssh`. Use `tailscale ssh rona@rescue-<suffix>` subject to the tailnet SSH ACL; configure the ACL to authorize `rona` only, never `root`. Normal OpenSSH is not listening on WAN.

## Credential and boot flow

1. Ventoy injects the encrypted pass-store archive into initrd at `/private`.
2. Initrd starts PC/SC and GPG, then waits for YubiKey unlock up to `rescueIso.yubikeyUnlockTimeoutSeconds` (180 seconds in `flake.nix`). Initrd starts no networking.
3. Successful unlock places only the host SSH age identity at `/run/rescue/ssh_host_ed25519_key`; it is never copied into the ISO or persistent storage.
4. Stage 2 runs sops-nix using that identity. The `rona` password hash, Wi-Fi passphrase, and Tailscale auth key are decrypted at runtime. The temporary host identity is removed after secret activation.
5. The selected GRUB mode configures networkd and SSH/Tailscale policy. LAN/Rescue LAN expose password SSH only after the SOPS-backed account password is installed; WAN uses ACL-managed Tailscale SSH only. Tailscale node state stays in memory; generated Tailscale SSH host keys live under `/run/tailscale/ssh` on tmpfs.

## Troubleshooting

- **Target powers off before stage 2:** a missing archive or GPG setup failure powers off immediately; a failed YubiKey unlock powers off when its configured timeout expires. Check the Ventoy injection archive and masked pinentry setup before another attempt. Do not enter a PIN into an unmasked prompt.
- **No SSH in WAN mode:** expected for normal OpenSSH. Unlock SOPS, verify Tailscale joins, and use `tailscale ssh` with an authorized ACL.
- **WAN join rejects `tag:rescue`:** ensure the tag exists and the auth-key owner is authorized to use it in the tailnet tag-owner policy. Because Tailscale state is memory-only and every boot registers a new node, use a reusable auth key permitted for `tag:rescue`; a one-time key can only enroll the first boot. Never expose the key value.
- **Tailscale SSH is unreachable while the node is online:** keep `--state=mem:` for ephemeral node state and provide a tmpfs-backed `--statedir` for generated SSH host keys; otherwise tailscaled has no var root for those keys.
- **No SSH in LAN/Rescue LAN:** `sshd` waits for SOPS secret activation. Confirm successful initrd unlock and sops-nix activation; verify GRUB entry selected.
- **No Wi-Fi in WAN:** after SOPS unlock, verify iwd is active and the saved `NaCo` profile is present; WAN uses iwd autoconnect. In LAN/Rescue LAN, connect explicitly with `sudo rescue-wifi-up`.
- **No Tailscale in LAN/Rescue LAN:** these modes do not auto-join; after SOPS unlock and internet connectivity, run `sudo rescue-tailscale-up`.
- **DHCP conflict:** stop using Rescue LAN on that interface if it is connected to a shared network; select LAN or WAN instead.

## Verification status

The standard ISO builds successfully at `/nix/store/br8s7bzl1mfzbrxpb64jshgs90zj04n6-iso.iso`; its GRUB menu contains WAN, LAN, and Rescue LAN entries in that order, with WAN first/default. QEMU verified shutdown before stage 2 without an archive and, with the encrypted archive but no YubiKey, after the 180-second timeout. A user-controlled LAN-mode QEMU boot used the full encrypted injection archive and real YubiKey; `/nix` was `0755`, SOPS, nscd, networkd, and sshd were active, there were zero failed units, `rona` reached Fish, and `/run/rescue` was empty after SOPS activation. A loopback-only SSH forward completed the handshake and offered password authentication; no password was supplied. After `tag:rescue` was added, a WAN QEMU built with the updated encrypted auth-key file joined successfully (`BackendState=Running`, tag `tag:rescue`, auth-key file removed). Tailscale SSH initially failed because tailscaled had no var root for SSH host keys despite `RunSSH=true`; `hosts/iso/tailscale.nix` now supplies `--statedir=/run/tailscale` alongside `--state=mem:`. The rebuilt test ISO `/nix/store/hs5cskidmc6hwa256wg2bnz5gdkac5bz-iso.iso` booted with a user-controlled YubiKey unlock; generated host keys appeared under `/run/tailscale/ssh`, and host-side `tailscale ssh rona@rescue-c401d8ec88 ... id -un` returned `rona`. Node state remained in memory and the SOPS auth-key file was absent. A follow-up local-secrets build at `/nix/store/rhjl1280zh79dvqxyyv9ki6a0bg0r3lj-iso.iso` tested Rescue LAN on an isolated QEMU socket network. The client received `192.168.77.4/29` from the five-address pool (`.2–.6`), received no router or DNS, had no default route, pinged `192.168.77.1` with 0% loss, and received the OpenSSH 10.2 banner. The DHCP range is bounded but the exact leased address is dynamic. In the same boot, `iwd.service` was active and `/var/lib/iwd/NaCo.psk` existed with mode `0600`; its contents were not read. A later physical-host Rescue LAN test verified password SSH, manually connecting to NaCo, DHCP (`172.17.2.157/24`), outbound connectivity, and `sudo rescue-tailscale-up`. The first Wi-Fi attempt prompted for the passphrase despite the SOPS profile; the profile template now uses iwd's `Passphrase=` field. The next physical image auto-connected Wi-Fi in all modes because its `AutoConnect=false` setting was in global `main.conf`, where iwd does not define that option. AutoConnect now lives in the generated network profile: true only for WAN and false for LAN/Rescue LAN. The `rescue-wifi-up` helper and per-mode policy are build-verified but still need physical boot verification. The previous Tailscale auth key was rejected with `invalid key: API key does not exist`; the user replaced it with a reusable, ephemeral, pre-approved key tagged `tag:rescue`. The latest ISO was rebuilt using the local encrypted nix-secrets input and staged on Ventoy; Tailscale acceptance of the replacement key remains unverified. SSH host keys are generated successfully at boot because the ISO is RAM-only, so host-key changes across boots are expected. Latest ISO: `/nix/store/g3q6i1ak197jljf5zpwfqchamms2gslr-iso.iso/iso/iso.iso`. No PIN or auth-key contents were seen or entered by the assistant. No PIN or auth-key contents were seen or entered by the assistant.
