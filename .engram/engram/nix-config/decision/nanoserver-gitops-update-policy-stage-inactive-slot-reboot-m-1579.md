---
id: 1579
type: decision
project: nix-config
scope: project
topic_key: appliance-gitops-stage-only
session_id: manual-save-nix-config
created_at: "2026-10-08 10:25:20"
updated_at: "2026-10-08 10:25:20"
revision_count: 1
tags:
  - nix-config
  - decision
aliases:
  - "Nanoserver GitOps update policy: stage inactive slot, reboot manually"
---

# Nanoserver GitOps update policy: stage inactive slot, reboot manually

Agreed update policy: Git declares the desired appliance version; successful CI should publish a new immutable signed release and a Nanoserver-specific component poller should stage it automatically. Keep reboot manual for now. If slot A is running, preserve A and stage the newer image in pending slot B; later releases should replace/update B until the user reboots. Preserve boot-count health rollback and existing v2/v3 release assets. Do not add a Nix CLI or daemon to the appliance. Current implementation evidence: systemd.sysupdate timer is daily and reboot.enable=false, but generic systemd-sysupdate.service fails with No transfer definitions found; component-specific --component=nanoserver works. appliance-update manually checks mirrors/mounts, stages a requested version, and arms a one-shot boot. Before automating, prove transfer semantics and repeated-staging tests cannot overwrite the running slot. Tracked in Seed nix-config-4ae7 under parent nix-config-a280.

---
*Session*: [[session-manual-save-nix-config]]
*Topic*: [[topic-appliance-gitops-stage-only]]
