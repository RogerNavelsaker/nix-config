#!/usr/bin/env fish

if test (count $argv) -ne 3
    printf 'Usage: install-rescue-host <host> <user@ssh-host> <extra-files-dir>\n' >&2
    exit 2
end

set -l host $argv[1]
set -l target $argv[2]
set -l extra_files (realpath -e -- $argv[3])
if not string match -rq '^[a-z0-9][a-z0-9-]*$' -- $host
    printf 'Invalid host name.\n' >&2
    exit 2
end
if not string match -rq '^[^@]+@[^@]+$' -- $target
    printf 'Target must be user@host.\n' >&2
    exit 2
end
if test -z "$extra_files"; or not string match -q '/run/user/*/nixos-host-identity.*' -- "$extra_files"
    printf 'Extra-files must be a staged host identity under /run/user.\n' >&2
    exit 1
end
set -l private_key "$extra_files/persist/etc/ssh/ssh_host_ed25519_key"
set -l public_key "$extra_files/persist/etc/ssh/ssh_host_ed25519_key.pub"
if not test -f "$private_key"; or not test -f "$public_key"
    printf 'Extra-files tree lacks the expected host identity files.\n' >&2
    exit 1
end
if test (stat -c %a "$private_key") != 600
    printf 'Host private key must have mode 0600.\n' >&2
    exit 1
end
for directory in "$extra_files" "$extra_files/persist" "$extra_files/persist/etc" "$extra_files/persist/etc/ssh"
    if test (stat -c %a "$directory") != 700
        printf 'Host identity staging directories must have mode 0700.\n' >&2
        exit 1
    end
end
set -l runtime_dir "/run/user/"(id -u)
set -l derived_public (mktemp "$runtime_dir/nixos-install-public.XXXXXX")
set -l derived_fields (mktemp "$runtime_dir/nixos-install-derived-fields.XXXXXX")
set -l expected_fields (mktemp "$runtime_dir/nixos-install-expected-fields.XXXXXX")
ssh-keygen -y -f "$private_key" > "$derived_public" 2>/dev/null
if test $status -ne 0
    rm -f -- "$derived_public" "$derived_fields" "$expected_fields"
    printf 'OpenSSH rejected the staged private key.\n' >&2
    exit 1
end
awk '{ print $1 " " $2 }' "$derived_public" > "$derived_fields"
awk '{ print $1 " " $2 }' "$public_key" > "$expected_fields"
cmp -s "$derived_fields" "$expected_fields"
set -l key_pair_status $status
rm -f -- "$derived_public" "$derived_fields" "$expected_fields"
if test "$key_pair_status" -ne 0
    printf 'Staged private key does not match its public key.\n' >&2
    exit 1
end

set -l target_parts (string split '@' -- "$target")
set -l target_host $target_parts[2]
set -l flake_attr ".#nixosConfigurations.$host"
set -l expected_json (nix eval --no-write-lock-file --json --apply 'c: builtins.mapAttrs (_: d: d.device) c.config.disko.devices.disk' "$flake_attr")
if test $status -ne 0
    printf 'Could not evaluate configured Disko targets for %s.\n' $host >&2
    exit 1
end
set -l expected_paths (printf '%s' "$expected_json" | jq -r 'to_entries[].value' | sort)
if test (count $expected_paths) -eq 0
    printf 'No configured Disko target paths for %s.\n' $host >&2
    exit 1
end

printf 'Live block inventory (serials/models omitted):\n'
ssh -o BatchMode=yes -o ConnectTimeout=10 "$target" lsblk -e7 -o NAME,SIZE,TYPE,TRAN,FSTYPE,LABEL,MOUNTPOINTS
if test $status -ne 0
    printf 'Could not read live target inventory.\n' >&2
    exit 1
end
set -l live_json (ssh -o BatchMode=yes -o ConnectTimeout=10 "$target" lsblk --json --bytes -e7 -o PATH,TYPE,SIZE,MOUNTPOINTS | string collect)
if test $status -ne 0
    printf 'Could not collect machine-readable live target inventory.\n' >&2
    exit 1
end
set -l mounted_count (printf '%s' "$live_json" | jq '[.blockdevices[] | recurse(.children[]?) | (.mountpoints // [])[]? | select(. != null)] | length')
if test "$mounted_count" != 0
    printf 'Refusing install: one or more target block devices have mounted filesystems.\n' >&2
    exit 1
end
set -l live_disks (printf '%s' "$live_json" | jq -r '.blockdevices[] | select(.type == "disk") | .path' | sort -u)
set -l expected_real
for path in $expected_paths
    if not string match -rq '^/dev/disk/by-path/[A-Za-z0-9:._-]+$' -- "$path"
        printf 'Configured target is not a stable by-path device: %s\n' "$path" >&2
        exit 1
    end
    set -l real (ssh -o BatchMode=yes -o ConnectTimeout=10 "$target" readlink -e -- "$path")
    if test $status -ne 0
        printf 'Configured target path is absent on the live host: %s\n' "$path" >&2
        exit 1
    end
    set -l kind (ssh -o BatchMode=yes -o ConnectTimeout=10 "$target" lsblk -dn -o TYPE -- "$path")
    if test $status -ne 0; or test "$kind" != disk
        printf 'Configured target is not a whole disk: %s\n' "$path" >&2
        exit 1
    end
    set -l size (ssh -o BatchMode=yes -o ConnectTimeout=10 "$target" lsblk -b -dn -o SIZE -- "$path")
    if test $status -ne 0
        printf 'Could not read target size: %s\n' "$path" >&2
        exit 1
    end
    set -a expected_real "$real"
    printf 'Configured target: %s -> %s bytes=%s\n' "$path" "$real" "$size"
end
set expected_real (printf '%s\n' $expected_real | sort -u)
set live_disks (printf '%s\n' $live_disks | sort -u)
if test (string join '|' $expected_real) != (string join '|' $live_disks)
    printf 'Refusing install: configured and live whole-disk sets differ.\n' >&2
    exit 1
end

printf 'Checking root-capable SSH before any kexec or Disko phase...\n'
ssh -o BatchMode=yes -o ConnectTimeout=10 "root@$target_host" true
if test $status -ne 0
    printf 'Refusing install: root SSH is unavailable; provide a supported root-capable route.\n' >&2
    exit 1
end

printf 'This will erase every configured Disko target above.\nType WIPE %s to continue: ' $host
if not isatty stdin
    printf 'Refusing non-interactive destructive execution.\n' >&2
    exit 1
end
read -l confirmation
if test "$confirmation" != "WIPE $host"
    printf 'Confirmation did not match; no install started.\n' >&2
    exit 1
end

exec nix run --no-write-lock-file github:nix-community/nixos-anywhere/1.13.0 -- \
    --no-use-machine-substituters \
    --flake ".#$host" \
    --target-host "$target" \
    --extra-files "$extra_files"
