# Nanoserver stage-only GitOps updates — retired

This plan described the legacy Btrfs/A-B appliance's `systemd-sysupdate` path. The appliance profiles, transfer definitions, release artifacts, tests, and operator workflow have been removed from the active checkout under explicit user direction. The archived checkout at `/workspace/RogerNavelsaker/nix-config-archive` retains the historical source and plan.

Do not use or deploy the former update procedure. The current storage/root direction is [the Bcachefs plan](bcachefs-ephemeral-root-multihost.md); it authorizes planning only, not implementation or physical operations.
