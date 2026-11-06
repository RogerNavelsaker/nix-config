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
  vessels/mara/default.nix \
  vessels/mara/resource.nix \
  clankers/rowan/default.nix \
  clankers/jules/default.nix \
  clankers/mira/default.nix \
  clankers/avery/default.nix \
  clankers/mara/default.nix \
  clankers/mara/resource.nix

if grep -Eq 'url = "path:' flake.nix; then
  printf 'flake.nix must use locked remote inputs.\n' >&2
  exit 1
fi

nix flake metadata --json >/dev/null
nix flake check --no-build

home_configurations="$(nix eval --json --apply builtins.attrNames .#homeConfigurations)"
if [[ "$home_configurations" == *'"rona@aio"'* || "$home_configurations" == *'"rona@roger-aio"'* ]]; then
  printf 'Roger-AIO Home Manager output must remain deferred until the CachyOS-to-NixOS migration.\n' >&2
  exit 1
fi

nixos_configurations="$(nix eval --json --apply builtins.attrNames .#nixosConfigurations)"
if [[ "$nixos_configurations" == *'"roger-aio"'* ]]; then
  printf 'Roger-AIO NixOS output must remain deferred until the CachyOS-to-NixOS migration.\n' >&2
  exit 1
fi

for agent in rowan jules mira avery; do
  host_name="$(nix eval --raw ".#nixosConfigurations.$agent.config.networking.hostName")"
  test "$host_name" = "agent-$agent"

  image_drv="$(nix eval --raw ".#nixosConfigurations.$agent.config.system.build.image.drvPath")"
  [[ "$image_drv" == /nix/store/*.drv ]]

  home_drv="$(nix eval --raw ".#homeConfigurations.$agent@agent-$agent.activationPackage.drvPath")"
  [[ "$home_drv" == /nix/store/*.drv ]]
done

mara_host_name="$(nix eval --raw .#nixosConfigurations.mara.config.networking.hostName)"
test "$mara_host_name" = "agent-mara"
test "$(nix eval --raw .#nixosConfigurations.mara.config.system.stateVersion)" = "26.05"
test "$(nix eval --json .#nixosConfigurations.mara.config.wsl.enable)" = "true"
mara_system_drv="$(nix eval --raw .#nixosConfigurations.mara.config.system.build.toplevel.drvPath)"
[[ "$mara_system_drv" == /nix/store/*.drv ]]
mara_home_drv="$(nix eval --raw .#homeConfigurations.mara@agent-mara.activationPackage.drvPath)"
[[ "$mara_home_drv" == /nix/store/*.drv ]]

git diff --check
