#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
installer="$repo_root/scripts/install-rescue-host.fish"
runtime_dir="/run/user/$(id -u)"
umask 077
mkdir -p -- "$runtime_dir"
stage="$(mktemp -d "$runtime_dir/nixos-host-identity.test.XXXXXX")"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$stage" "$tmp"' EXIT

mkdir -p "$stage/persist/etc/ssh" "$tmp/bin"
chmod 0700 "$stage" "$stage/persist" "$stage/persist/etc" "$stage/persist/etc/ssh"
printf 'mock private key\n' >"$stage/persist/etc/ssh/ssh_host_ed25519_key"
printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeKeyForOrchestrationTest mock\n' >"$stage/persist/etc/ssh/ssh_host_ed25519_key.pub"
chmod 0600 "$stage/persist/etc/ssh/ssh_host_ed25519_key"

cat >"$tmp/bin/nix" <<'MOCK_NIX'
#!/usr/bin/env bash
set -euo pipefail
args="$*"
if [[ "${1:-}" == eval ]]; then
  if [[ "$args" == *disko.devices.disk* ]]; then
    cat <<'JSON'
{"disk0":"/dev/disk/by-path/pci-0000:00:14.0-usb-0:9:1.0-scsi-0:0:0:0","disk1":"/dev/disk/by-path/pci-0000:00:14.0-usb-0:10:1.0-scsi-0:0:0:0","disk2":"/dev/disk/by-path/pci-0000:01:00.0-nvme-1","disk3":"/dev/disk/by-path/pci-0000:02:00.0-nvme-1"}
JSON
  elif [[ "$args" == *config.appliance.storeName* ]]; then
    printf 'miniserver-01-bootstrap-store\n'
  elif [[ "$args" == *config.appliance.rootVersion* ]]; then
    printf 'bootstrap\n'
  else
    printf 'Unexpected nix eval: %s\n' "$args" >&2
    exit 80
  fi
elif [[ "${1:-}" == run ]]; then
  phases=""
  target=""
  extra="none"
  while (($#)); do
    case "$1" in
      --phases) phases="$2"; shift 2 ;;
      --target-host) target="$2"; shift 2 ;;
      --extra-files) extra="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  printf 'run phases=%s target=%s extra=%s\n' "$phases" "$target" "$extra" >>"$MOCK_TRACE"
else
  printf 'Unexpected nix invocation: %s\n' "$args" >&2
  exit 81
fi
MOCK_NIX

cat >"$tmp/bin/ssh" <<'MOCK_SSH'
#!/usr/bin/env bash
set -euo pipefail
while (($#)); do
  case "$1" in
    -o|-i|-p|-F|-S|-l) shift 2 ;;
    -*) shift ;;
    *) break ;;
  esac
done
target="${1:-}"
shift || true
remote_command="${1:-}"
shift || true
if [[ "$target" != *"@rescue-test" ]]; then
  printf 'Mock SSH refused unexpected target: %s\n' "$target" >&2
  exit 82
fi
if [[ "$remote_command" == true ]]; then
  printf 'root-preflight\n' >>"$MOCK_TRACE"
elif [[ "$remote_command" == lsblk* ]]; then
  if [[ "$remote_command $*" == *--json* ]]; then
    cat <<'JSON'
{"blockdevices":[{"path":"/dev/sdb","type":"disk","size":64160400896,"mountpoints":null},{"path":"/dev/sdc","type":"disk","size":64160400896,"mountpoints":null},{"path":"/dev/nvme0n1","type":"disk","size":500107862016,"mountpoints":null},{"path":"/dev/nvme1n1","type":"disk","size":500107862016,"mountpoints":null}]}
JSON
  elif [[ "$*" == *"-o TYPE"* ]]; then
    printf 'disk\n'
  elif [[ "$*" == *"-o SIZE"* ]]; then
    case "$*" in
      *usb-0:9:1.0*) printf '64160400896\n' ;;
      *usb-0:10:1.0*) printf '64160400896\n' ;;
      *01:00.0*) printf '500107862016\n' ;;
      *02:00.0*) printf '500107862016\n' ;;
      *) exit 84 ;;
    esac
  else
    printf 'NAME SIZE TYPE\nsdb 64160400896 disk\nsdc 64160400896 disk\nnvme0n1 500107862016 disk\nnvme1n1 500107862016 disk\n'
  fi
elif [[ "$remote_command" == readlink ]]; then
  case "${@: -1}" in
    *usb-0:9:1.0-scsi-0:0:0:0) printf '/dev/sdb\n' ;;
    *usb-0:10:1.0-scsi-0:0:0:0) printf '/dev/sdc\n' ;;
    *01:00.0-nvme-1) printf '/dev/nvme0n1\n' ;;
    *02:00.0-nvme-1) printf '/dev/nvme1n1\n' ;;
    *) printf 'Unexpected stable path: %s\n' "${@: -1}" >&2; exit 83 ;;
  esac
elif [[ "$remote_command" == "set -eu;"* ]]; then
  [[ "$remote_command" == *"findmnt -n -T /mnt/nix/store -o TARGET | grep -Fx /mnt/nix/store"* ]]
  [[ "$remote_command" == *"findmnt -n -T /mnt/nix/store -o FSTYPE | grep -Fx btrfs"* ]]
  [[ "$remote_command" == *"findmnt -n -T /mnt/nix/store -o FSROOT | grep -Fx /miniserver-01-bootstrap-store_bootstrap"* ]]
  [[ "$remote_command" == *"rm -rf -- /mnt/nix/var/nix/db"* ]]
  [[ "$remote_command" == *"test ! -e /mnt/nix/var/nix/db"* ]]
  printf 'cleanup\n' >>"$MOCK_TRACE"
  if [[ "${MOCK_FAIL_CLEANUP:-0}" == 1 ]]; then
    printf 'Simulated store identity/DB cleanup failure\n' >&2
    exit 42
  fi
else
  printf 'Unexpected mock SSH command for %s: %s %s\n' "$target" "$remote_command" "$*" >&2
  exit 86
fi
MOCK_SSH

cat >"$tmp/bin/ssh-keygen" <<'MOCK_SSH_KEYGEN'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == -y ]]; then
  while (($#)); do
    if [[ "$1" == -f ]]; then
      key_path="$2"
      break
    fi
    shift
  done
  [[ -n "${key_path:-}" ]]
  cat "$key_path.pub"
else
  printf 'Unexpected mock ssh-keygen invocation: %s\n' "$*" >&2
  exit 87
fi
MOCK_SSH_KEYGEN
chmod 0700 "$tmp/bin/nix" "$tmp/bin/ssh" "$tmp/bin/ssh-keygen"

run_case() {
  local name="$1" fail_cleanup="$2" expected_status="$3"
  local case_dir="$tmp/$name" output="$tmp/$name.out" status
  mkdir -p "$case_dir"
  local trace="$case_dir/trace"
  set +e
  printf 'WIPE miniserver-01\n' | \
    PATH="$tmp/bin:$PATH" TERM=dumb MOCK_TRACE="$trace" MOCK_FAIL_CLEANUP="$fail_cleanup" \
      fish --no-config -c 'function isatty; return 0; end; source "$argv[1]" "$argv[2]" "$argv[3]" "$argv[4]"' \
      -- "$installer" miniserver-01 rona@rescue-test "$stage" >"$output" 2>&1
  status=$?
  set -e
  if [[ "$status" -ne "$expected_status" ]]; then
    cat "$output" >&2
    printf '%s: expected exit %s, got %s\n' "$name" "$expected_status" "$status" >&2
    return 1
  fi
}

run_case success 0 0
mapfile -t success_events < <(grep -E '^(root-preflight|cleanup|run phases=)' "$tmp/success/trace")
expected_success_events=(
  'root-preflight'
  'run phases=kexec,disko target=rona@rescue-test extra=none'
  'cleanup'
  "run phases=install,reboot target=root@rescue-test extra=$stage"
)
if [[ "${success_events[*]}" != "${expected_success_events[*]}" ]]; then
  printf 'Unexpected success event order:\n%s\n' "$(cat "$tmp/success/trace")" >&2
  exit 1
fi

run_case cleanup-failure 1 1
mapfile -t failed_events < <(grep -E '^(root-preflight|cleanup|run phases=)' "$tmp/cleanup-failure/trace")
expected_failed_events=(
  'root-preflight'
  'run phases=kexec,disko target=rona@rescue-test extra=none'
  'cleanup'
)
if [[ "${failed_events[*]}" != "${expected_failed_events[*]}" ]]; then
  printf 'Installer did not fail closed after store cleanup failure:\n%s\n' "$(cat "$tmp/cleanup-failure/trace")" >&2
  exit 1
fi

printf 'install-rescue-host phase orchestration mock test passed\n'
