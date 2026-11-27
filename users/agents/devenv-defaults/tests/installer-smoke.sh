#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 INSTALLER SOURCE_DIR AGENT" >&2
  exit 2
fi

installer=$1
source_dir=$2
agent=$3
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
home="$tmp/home"
mkdir -p "$home/.local/share" "$tmp/legacy"

cat > "$tmp/legacy/devenv.yaml" <<'YAML'
inputs:
  nixpkgs:
    url: github:cachix/devenv-nixpkgs/rolling
  pi-coding-agent:
    url: github:RogerNavelsaker/nixpkg-pi-coding-agent
YAML
cat > "$tmp/legacy/devenv.nix" <<'NIX'
{ inputs, pkgs, ... }:

let
  piPackage = inputs."pi-coding-agent".packages.${pkgs.system}.default;
in
{
  packages = [
    piPackage
    piPackage.pi
  ];
}
NIX
cp "$source_dir/devenv.lock" "$tmp/legacy/devenv.lock"
seed_lock_hash=$(sha256sum "$source_dir/devenv.lock" | cut -d' ' -f1)

[[ "$(sha256sum "$tmp/legacy/devenv.yaml" | cut -d' ' -f1)" == cc78ef0bebfa9c138b62a0f6189af593e72ba65315db89f30a3c3d9e9026f9d4 ]]
[[ "$(sha256sum "$tmp/legacy/devenv.nix" | cut -d' ' -f1)" == e16d13f6d7316488d7b5608e919fdc7b1ee18fe29f8dda08d9ffe6cbd9f9fc47 ]]
[[ "$(sha256sum "$tmp/legacy/devenv.lock" | cut -d' ' -f1)" == "$seed_lock_hash" ]]

for alias in sd ml tr; do
  grep -Fq "scripts.$alias.exec" "$source_dir/shared-config/devenv.nix"
done
for command in seeds mulch git terrarium worktrunk; do
  grep -Fq "$command" "$source_dir/shared-config/devenv.nix"
done
for package in seeds mulch terrarium; do
  grep -Fq "inputs.$package.packages." "$source_dir/shared-config/devenv.nix"
done
for package in openbao step-cli; do
  grep -Fq "pkgs.$package" "$source_dir/shared-config/devenv.nix"
done
for package in git worktrunk; do
  grep -Fq "agentPkgs.$package" "$source_dir/shared-config/devenv.nix"
done
for input in agentToolsNixpkgs seeds mulch terrarium; do
  grep -Fq "$input:" "$source_dir/devenv.yaml"
done
if grep -Fq "scripts.wt.exec" "$source_dir/shared-config/devenv.nix"; then
  echo "Devenv wt wrapper would shadow Worktrunk." >&2
  exit 1
fi
if grep -Eq 'scripts\.pi\.exec|pi-compression-proxy|PROXY_CHAIN_' "$source_dir/shared-config/devenv.nix"; then
  echo "Shared Devenv config still wraps Pi through the compression proxy." >&2
  exit 1
fi
if grep -Eq '^[[:space:]]+pi-coding-agent:' "$source_dir/devenv.yaml"; then
  echo "Devenv YAML still declares the Pi package input." >&2
  exit 1
fi

ln -s "$tmp/legacy/devenv.yaml" "$home/devenv.yaml"
ln -s "$tmp/legacy/devenv.lock" "$home/devenv.lock"
ln -s "$tmp/legacy/devenv.nix" "$home/devenv.nix"

sed "s|/home/$agent|$home|g" "$installer" > "$tmp/installer"
HOME="$home" bash "$tmp/installer"

for name in devenv.yaml devenv.lock devenv.nix; do
  [[ -f "$home/$name" && ! -L "$home/$name" ]]
done
[[ -w "$home/devenv.lock" ]]
config_hash=$(sha256sum "$source_dir/shared-config/devenv.nix" | cut -d' ' -f1)
grep -Fq "agent-devenv-shared/$config_hash" "$home/devenv.yaml"
cmp "$source_dir/shared-config/devenv.nix" "$home/.local/share/nix-config/agent-devenv-shared/$config_hash/devenv.nix"
backup=$(find "$home/.local/state/pi/backups" -mindepth 1 -maxdepth 1 -type d -name 'devenv-import-pre-*')
[[ -n "$backup" ]]
for name in devenv.yaml devenv.lock devenv.nix; do
  [[ -f "$backup/$name" ]]
done

HOME="$home" bash "$tmp/installer"
[[ "$(find "$home/.local/state/pi/backups" -mindepth 1 -maxdepth 1 -type d -name 'devenv-import-pre-*' | wc -l)" -eq 1 ]]

link_home="$tmp/link-home"
mkdir -p "$link_home/.local/share"
cp "$home/devenv.yaml" "$tmp/matching-yaml"
cp "$home/devenv.nix" "$tmp/matching-stub"
ln -s "$tmp/matching-yaml" "$link_home/devenv.yaml"
ln -s "$tmp/matching-stub" "$link_home/devenv.nix"
ln -s "$source_dir/devenv.lock" "$link_home/devenv.lock"
sed "s|/home/$agent|$link_home|g" "$installer" > "$tmp/link-installer"
HOME="$link_home" bash "$tmp/link-installer"
for name in devenv.yaml devenv.lock devenv.nix; do
  [[ -f "$link_home/$name" && ! -L "$link_home/$name" ]]
done
[[ -w "$link_home/devenv.lock" ]]

printf '\n# user edit\n' >> "$home/devenv.yaml"
if HOME="$home" bash "$tmp/installer" > "$tmp/refusal.log" 2>&1; then
  echo "Installer unexpectedly overwrote a local edit." >&2
  exit 1
fi
grep -Fq "Refusing to replace unexpected file" "$tmp/refusal.log"
grep -Fq "# user edit" "$home/devenv.yaml"

mira_home="$tmp/mira-home"
mkdir -p "$mira_home/.local/share"
cat > "$tmp/mira-legacy.yaml" <<'YAML'
inputs:
  nixpkgs:
    url: github:cachix/devenv-nixpkgs/rolling
  seeds:
    url: github:RogerNavelsaker/nixpkg-seeds
  mulch:
    url: github:RogerNavelsaker/nixpkg-mulch
  terrarium:
    url: github:RogerNavelsaker/nixpkg-terrarium
  shared-config:
    url: path:./.local/share/nix-config/agent-devenv-shared/8b099d6c16096af8cfae1e618d55d4b4e12368c85ae9fdde3a97701c898ceebb
    flake: false
imports:
  - shared-config
YAML
cat > "$tmp/mira-legacy.nix" <<'NIX'
{ pkgs, inputs, ... }:
let
  pi-compression-proxy = pkgs.callPackage /workspace/RogerNavelsaker/nixpkg-pi-compression-proxy/nix/package.nix { };
in
{
  cachix.enable = true;
  packages = [
    pkgs.chromium
    pkgs.firefox
    pkgs.browsh
    pi-compression-proxy
    inputs.browser-cli.packages.${pkgs.system}.default
    inputs.crawlberg.packages.${pkgs.system}.default
    inputs.xberg.packages.${pkgs.system}.default
  ];
}
NIX
cp "$tmp/mira-legacy.yaml" "$mira_home/devenv.yaml"
cp "$tmp/mira-legacy.nix" "$mira_home/devenv.nix"
cat > "$mira_home/devenv.lock" <<'LOCK'
{"nodes":{"root":{"inputs":{"mira-specific":"preserve"}}}}
LOCK
[[ "$(sha256sum "$mira_home/devenv.yaml" | cut -d' ' -f1)" == ef033ff39613f0afae25a58a8baae7bc0f98c82fc12bf550c25fcf2b42b5367b ]]
[[ "$(sha256sum "$mira_home/devenv.nix" | cut -d' ' -f1)" == d7e7dbd5c662691bb84d08812447974bbeb3fd7c7185d31b425c412f2061aabb ]]
mira_lock_hash=$(sha256sum "$mira_home/devenv.lock" | cut -d' ' -f1)
sed "s|/home/$agent|$mira_home|g" "$installer" > "$tmp/mira-installer"
HOME="$mira_home" bash "$tmp/mira-installer"
[[ -w "$mira_home/devenv.lock" ]]
[[ "$(sha256sum "$mira_home/devenv.lock" | cut -d' ' -f1)" == "$mira_lock_hash" ]]
cmp "$source_dir/devenv.nix" "$mira_home/devenv.nix"
mira_backup=$(find "$mira_home/.local/state/pi/backups" -mindepth 1 -maxdepth 1 -type d -name 'devenv-import-pre-*')
cmp "$tmp/mira-legacy.yaml" "$mira_backup/devenv.yaml"
cmp "$tmp/mira-legacy.nix" "$mira_backup/devenv.nix"
cmp "$mira_home/devenv.lock" "$mira_backup/devenv.lock"
HOME="$mira_home" bash "$tmp/mira-installer"
[[ "$(find "$mira_home/.local/state/pi/backups" -mindepth 1 -maxdepth 1 -type d -name 'devenv-import-pre-*' | wc -l)" -eq 1 ]]
echo "Installer smoke passed: backup, writable lock, idempotence, symlink repair, and edit protection."
