# Miniserver bootstrap installation — retired

This plan described the legacy Btrfs/image-appliance bootstrap and rescue installer. That implementation, its tests, and its operator workflow have been removed from the active checkout under explicit user direction. The archived checkout at `/workspace/RogerNavelsaker/nix-config-archive` retains the historical plan and source.

Do not execute its bootstrap, Disko, `nixos-anywhere`, or physical-install steps. The current storage/root direction is [the Bcachefs plan](bcachefs-ephemeral-root-multihost.md); implementation and physical operations remain unauthorized. Miniserver-01's last recorded state and safety constraint are in [Miniserver install readiness](miniserver-install-readiness.md).
