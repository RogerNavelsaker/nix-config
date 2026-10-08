---
id: 1396
type: discovery
project: nix-config
scope: project
topic_key: ""
session_id: manual-save-nix-config
created_at: "2026-10-05 07:45:04"
updated_at: "2026-10-05 07:45:04"
revision_count: 1
tags:
  - nix-config
  - discovery
aliases:
  - "disko umount recursive failure requires parent mountpoint"
---

# disko umount recursive failure requires parent mountpoint

On 2026-10-05, an isolated user+mount namespace probe reproduced the harness symptom: with only tmpfs mounted at `/mnt/nested`, `umount -Rv /mnt` exits 1 ('/mnt not mounted') and `mountpoint -q /mnt/nested` confirms the child remains mounted. With a tmpfs mount at `/mnt` and another nested below it, the same recursive command unmounts nested then parent successfully. This supports a test-harness root-mount assumption. It is not yet a reproduction through Disko's makeDiskoTest or Btrfs; test-only `/mnt` tmpfs or deepest-first child unmount are hypotheses to validate. Do not weaken production Disko safety or infer physical-device risk.

---
*Session*: [[session-manual-save-nix-config]]
