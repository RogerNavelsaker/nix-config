---
id: 1402
type: discovery
project: nix-config
scope: project
topic_key: ""
session_id: manual-save-nix-config
created_at: "2026-10-05 09:02:55"
updated_at: "2026-10-05 09:02:55"
revision_count: 1
tags:
  - nix-config
  - discovery
aliases:
  - "Disko nested-mount repeatability QEMU regression fixed"
---

# Disko nested-mount repeatability QEMU regression fixed

On 2026-10-05, nix-config's shared disposable QEMU Disko layout test now mounts a test-only tmpfs at /mnt, runs two format/mount/assert/unmount cycles, and runs Disko destroy twice after each. All four checks passed with the command-local unpublished nix-lib override: miniserver-01, miniserver-02, miniserver-03, nanoserver-01. The test file passes nixfmt --check; git diff --check passes. No production Disko changes or physical devices. nix-config-d21c is closed. The generic unmount helper still needs a root mountpoint for recursive cleanup in these layouts; future tests should preserve this fixture setup.

---
*Session*: [[session-manual-save-nix-config]]
