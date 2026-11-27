---
id: 1580
type: decision
project: nix-config
scope: project
topic_key: appliance-stage-only-manual-reboot
session_id: manual-save-nix-config
created_at: "2026-10-08 10:27:19"
updated_at: "2026-10-08 10:27:19"
revision_count: 1
tags:
  - nix-config
  - decision
aliases:
  - "Automate Nanoserver update staging; keep reboot manual and A safe"
---

# Automate Nanoserver update staging; keep reboot manual and A safe

User-confirmed A/B policy for appliance GitOps: Git declares image version; CI validates/signs/publishes it; a Nanoserver-specific systemd-sysupdate reconciler polls and stages automatically, but does not reboot. If slot A is active, preserve A and stage the newer image in pending B; additional releases replace pending B until user manually reboots. Keep boot-count health rollback and v2/v3 artifacts. The appliance remains without a Nix CLI/daemon. Current sysupdate.nix has a daily timer and reboot.enable=false, but generic systemd-sysupdate.service fails with No transfer definitions found; component-specific --component=nanoserver works. The manual appliance-update script preflights both Btrfs mirror members and ESPs, updates a selected version, checks store/registration, syncs, then sets one-shot boot. Verify with tests that repeated automatic staging replaces only B and never active A before enabling. Tracked in Seed nix-config-4ae7.

---
*Session*: [[session-manual-save-nix-config]]
*Topic*: [[topic-appliance-stage-only-manual-reboot]]
