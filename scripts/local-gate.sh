#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
flake_ref="path:$repo_root"

nix run --no-write-lock-file "$flake_ref#formatter.x86_64-linux" -- --check \
  flake.nix \
  checks.nix \
  devenv.nix \
  hosts/nanoserver-01/default.nix \
  hosts/miniserver-01/default.nix \
  hosts/miniserver-02/default.nix \
  hosts/miniserver-03/default.nix \
  hosts/features/default/impermanence.nix \
  overlays/default.nix \
  hosts/ester-desktop/default.nix \
  hosts/features/opt-in/herdr-server.nix \
  hosts/features/opt-in/host-platform/persistence.nix \
  hosts/features/opt-in/host-platform/virtualisation.nix \
  hosts/miniserver-common/ssh.nix \
  hosts/nanoserver-01/ssh.nix \
  vessels/features/default/agent-toolchain.nix \
  vessels/features/default/lxc-agent.nix \
  vessels/rowan/default.nix \
  vessels/jules/default.nix \
  vessels/mira/default.nix \
  vessels/avery/default.nix \
  vessels/alex/default.nix \
  vessels/mara/default.nix \
  clankers/rowan/default.nix \
  clankers/jules/default.nix \
  clankers/mira/default.nix \
  clankers/avery/default.nix \
  clankers/alex/default.nix \
  clankers/mara/default.nix

if grep -Eq 'url = "path:' flake.nix; then
  printf 'flake.nix must use locked remote inputs.\n' >&2
  exit 1
fi

nix flake metadata --json --no-write-lock-file "$flake_ref" >/dev/null
nix build --no-link --no-write-lock-file "$flake_ref#checks.x86_64-linux.resource-tree"


home_configurations="$(nix eval --no-write-lock-file --json --apply builtins.attrNames ${flake_ref}#homeConfigurations)"
if [[ "$home_configurations" == *'"rona@aio"'* || "$home_configurations" == *'"rona@roger-aio"'* ]]; then
  printf 'Roger-AIO Home Manager output must remain deferred until the CachyOS-to-NixOS migration.\n' >&2
  exit 1
fi

nixos_configurations="$(nix eval --no-write-lock-file --json --apply builtins.attrNames ${flake_ref}#nixosConfigurations)"
if [[ "$nixos_configurations" == *'"roger-aio"'* ]]; then
  printf 'Roger-AIO NixOS output must remain deferred until the CachyOS-to-NixOS migration.\n' >&2
  exit 1
fi

for agent in rowan jules mira avery; do
  host_name="$(nix eval --no-write-lock-file --raw "${flake_ref}#nixosConfigurations.$agent.config.networking.hostName")"
  test "$host_name" = "agent-$agent"

  image_drv="$(nix eval --no-write-lock-file --raw "${flake_ref}#nixosConfigurations.$agent.config.system.build.image.drvPath")"
  [[ "$image_drv" == /nix/store/*.drv ]]

  home_drv="$(nix eval --no-write-lock-file --raw "${flake_ref}#homeConfigurations.$agent@agent-$agent.activationPackage.drvPath")"
  [[ "$home_drv" == /nix/store/*.drv ]]
done

alex_system_drv="$(nix eval --no-write-lock-file --raw "${flake_ref}#nixosConfigurations.alex.config.system.build.toplevel.drvPath")"
[[ "$alex_system_drv" == /nix/store/*.drv ]]
alex_home_drv="$(nix eval --no-write-lock-file --raw "${flake_ref}#homeConfigurations.alex@agent-alex.activationPackage.drvPath")"
[[ "$alex_home_drv" == /nix/store/*.drv ]]

mara_host_name="$(nix eval --no-write-lock-file --raw ${flake_ref}#nixosConfigurations.mara.config.networking.hostName)"
test "$mara_host_name" = "agent-mara"
test "$(nix eval --no-write-lock-file --raw ${flake_ref}#nixosConfigurations.mara.config.system.stateVersion)" = "26.05"
test "$(nix eval --no-write-lock-file --json ${flake_ref}#nixosConfigurations.mara.config.wsl.enable)" = "true"
mara_system_drv="$(nix eval --no-write-lock-file --raw ${flake_ref}#nixosConfigurations.mara.config.system.build.toplevel.drvPath)"
[[ "$mara_system_drv" == /nix/store/*.drv ]]
mara_home_drv="$(nix eval --no-write-lock-file --raw ${flake_ref}#homeConfigurations.mara@agent-mara.activationPackage.drvPath)"
[[ "$mara_home_drv" == /nix/store/*.drv ]]

git diff --check
nix flake check --no-build --no-write-lock-file "$flake_ref"
