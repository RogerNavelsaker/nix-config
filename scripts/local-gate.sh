#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

nix run nixpkgs#nixfmt-rfc-style -- --check \
  flake.nix \
  overlays/default.nix \
  vessels/features/default/lxc-agent.nix \
  vessels/rowan/default.nix \
  vessels/jules/default.nix \
  vessels/mira/default.nix \
  vessels/avery/default.nix \
  clankers/rowan/default.nix \
  clankers/jules/default.nix \
  clankers/mira/default.nix \
  clankers/avery/default.nix

nix flake check --no-build

for agent in rowan jules mira avery; do
  host_name="$(nix eval --raw ".#nixosConfigurations.$agent.config.networking.hostName")"
  test "$host_name" = "agent-$agent"
  nix eval --raw ".#nixosConfigurations.$agent.config.system.build.image.drvPath" >/dev/null
  nix eval --raw ".#homeConfigurations.$agent@agent-$agent.activationPackage.drvPath" >/dev/null
done

git diff --check
