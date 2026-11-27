{
  description = "Shared agent Devenv configuration installer";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      agents = [ "rowan" "jules" "mira" "avery" "mara" "alex" ];
      sharedConfig = ./shared-config/devenv.nix;
      sharedConfigHash = builtins.hashFile "sha256" sharedConfig;
      renderedYaml = builtins.replaceStrings
        [ "@SHARED_CONFIG_HASH@" ]
        [ sharedConfigHash ]
        (builtins.readFile ./devenv.yaml);
      yamlFile = pkgs.writeText "devenv-agent.yaml" renderedYaml;
      rootNixFile = pkgs.writeText "devenv-agent-root.nix" (builtins.readFile ./devenv.nix);
      yamlHash = builtins.hashString "sha256" renderedYaml;
      stubHash = builtins.hashString "sha256" (builtins.readFile ./devenv.nix);
      seedLockHash = builtins.hashFile "sha256" ./devenv.lock;

      installApp = username:
        let
          script = pkgs.writeShellScript "install-agent-devenv-${username}" ''
            set -euo pipefail

            if [ "''${HOME-}" != "/home/${username}" ]; then
              echo "Run this app as ${username} (HOME must be /home/${username})." >&2
              exit 1
            fi

            coreutils="${pkgs.coreutils}/bin"
            cp="$coreutils/cp"
            cut="$coreutils/cut"
            date="$coreutils/date"
            install="$coreutils/install"
            mkdir="$coreutils/mkdir"
            mktemp="$coreutils/mktemp"
            mv="$coreutils/mv"
            readlink="$coreutils/readlink"
            rm="$coreutils/rm"
            sha256sum="$coreutils/sha256sum"
            cmp="${pkgs.diffutils}/bin/cmp"
            chmod="$coreutils/chmod"

            file_hash() {
              "$sha256sum" "$1" | "$cut" -d ' ' -f 1
            }

            check_managed_file() {
              local name="$1" legacy_hashes="$2" desired_hash="$3" previous_hash="$4"
              local target="$HOME/$name" current_hash
              if [ -e "$target" ] || [ -L "$target" ]; then
                if [ ! -f "$target" ]; then
                  echo "Refusing to replace non-file: $target" >&2
                  exit 1
                fi
                current_hash="$(file_hash "$target")"
                if [ "$current_hash" != "$desired_hash" ] &&
                   [ "$current_hash" != "$previous_hash" ]; then
                  case " $legacy_hashes " in
                    *" $current_hash "*) ;;
                    *)
                      echo "Refusing to replace unexpected file: $target" >&2
                      exit 1
                      ;;
                  esac
                fi
              fi
            }

            state_dir="$HOME/.local/state/pi/devenv-central-import"
            state_file="$state_dir/managed-hashes"
            if [ -L "$state_dir" ]; then
              echo "Refusing symlinked state directory: $state_dir" >&2
              exit 1
            fi
            managed_yaml_hash=""
            managed_stub_hash=""
            if [ -e "$state_file" ] || [ -L "$state_file" ]; then
              if [ ! -f "$state_file" ] || [ -L "$state_file" ]; then
                echo "Refusing unexpected state file: $state_file" >&2
                exit 1
              fi
              while IFS='=' read -r key value; do
                case "$key" in
                  yaml) managed_yaml_hash="$value" ;;
                  stub) managed_stub_hash="$value" ;;
                esac
              done < "$state_file"
              if [ -z "$managed_yaml_hash" ] || [ -z "$managed_stub_hash" ]; then
                echo "Invalid managed manifest state: $state_file" >&2
                exit 1
              fi
            fi

            yaml_hash="${yamlHash}"
            stub_hash="${stubHash}"
            # Support the original Pi manifest, tools-only manifests, and the legacy Mira setup.
            legacy_yaml_hashes="cc78ef0bebfa9c138b62a0f6189af593e72ba65315db89f30a3c3d9e9026f9d4 ef033ff39613f0afae25a58a8baae7bc0f98c82fc12bf550c25fcf2b42b5367b"
            legacy_stub_hashes="e16d13f6d7316488d7b5608e919fdc7b1ee18fe29f8dda08d9ffe6cbd9f9fc47 de8adddd896dfc16e5aec927e05e4db876bfc98bf05880e3ac2cfa322c454ee7 d7e7dbd5c662691bb84d08812447974bbeb3fd7c7185d31b425c412f2061aabb"
            old_lock_hash="ca12986b220002028a887018d688186d80ec00d5eb28c5b66612192ef7cc89f0"

            check_managed_file devenv.yaml "$legacy_yaml_hashes" "$yaml_hash" "$managed_yaml_hash"
            check_managed_file devenv.nix "$legacy_stub_hashes" "$stub_hash" "$managed_stub_hash"

            lock_target="$HOME/devenv.lock"
            lock_action="preserve"
            if [ -L "$lock_target" ]; then
              if [ ! -f "$lock_target" ]; then
                echo "Refusing broken Devenv lock symlink: $lock_target" >&2
                exit 1
              fi
              current_lock_hash="$(file_hash "$lock_target")"
              if [ "$current_lock_hash" != "$old_lock_hash" ] &&
                 [ "$current_lock_hash" != "${seedLockHash}" ]; then
                echo "Refusing unexpected Devenv lock symlink: $lock_target" >&2
                exit 1
              fi
              lock_action="seed"
            elif [ -e "$lock_target" ] && [ ! -f "$lock_target" ]; then
              echo "Refusing non-file Devenv lock: $lock_target" >&2
              exit 1
            elif [ ! -e "$lock_target" ]; then
              lock_action="seed"
            fi

            share_root="$HOME/.local/share"
            nix_config_root="$share_root/nix-config"
            if [ -L "$share_root" ] || [ -L "$nix_config_root" ]; then
              echo "Refusing symlinked shared-data path: $nix_config_root" >&2
              exit 1
            elif [ -e "$nix_config_root" ]; then
              if [ ! -d "$nix_config_root" ] || [ ! -w "$nix_config_root" ]; then
                echo "Shared-data path is not a writable directory: $nix_config_root" >&2
                exit 1
              fi
            elif [ ! -d "$share_root" ] || [ ! -w "$share_root" ]; then
              echo "Cannot create shared-data path under: $share_root" >&2
              exit 1
            fi

            needs_backup=0
            for name in devenv.yaml devenv.nix; do
              target="$HOME/$name"
              if [ "$name" = devenv.yaml ]; then wanted="$yaml_hash"; else wanted="$stub_hash"; fi
              if [ -L "$target" ] || [ ! -f "$target" ] || [ "$(file_hash "$target")" != "$wanted" ]; then
                needs_backup=1
              fi
            done
            if [ "$lock_action" = seed ] && { [ -e "$lock_target" ] || [ -L "$lock_target" ]; }; then
              needs_backup=1
            fi

            if [ "$needs_backup" = 1 ]; then
              backup_root="$HOME/.local/state/pi/backups"
              "$mkdir" -p "$backup_root"
              backup_dir="$backup_root/devenv-import-pre-$("$date" -u +%Y%m%dT%H%M%SZ)"
              "$mkdir" -m 700 "$backup_dir"
              for name in devenv.yaml devenv.lock devenv.nix; do
                target="$HOME/$name"
                if [ -e "$target" ] || [ -L "$target" ]; then
                  "$cp" -L --preserve=mode,timestamps "$target" "$backup_dir/$name"
                  if [ -L "$target" ]; then
                    printf '%s -> %s\n' "$name" "$("$readlink" "$target")" >> "$backup_dir/symlinks.txt"
                  fi
                fi
              done
              echo "Backed up existing Devenv files to $backup_dir"
            fi

            "$mkdir" -p "$nix_config_root"
            shared_root="$nix_config_root/agent-devenv-shared"
            shared_dir="$shared_root/${sharedConfigHash}"
            if [ -L "$shared_root" ] || [ -L "$shared_dir" ]; then
              echo "Refusing symlink in shared-config path: $shared_dir" >&2
              exit 1
            fi
            "$mkdir" -p -m 755 "$shared_dir"
            shared_file="$shared_dir/devenv.nix"
            if [ -e "$shared_file" ]; then
              if [ -L "$shared_file" ] || ! "$cmp" -s "${sharedConfig}" "$shared_file"; then
                echo "Refusing unexpected shared config file: $shared_file" >&2
                exit 1
              fi
            else
              "$install" -m 644 "${sharedConfig}" "$shared_file"
            fi
            for entry in "$shared_dir"/*; do
              [ -e "$entry" ] || [ -L "$entry" ] || continue
              if [ "$entry" != "$shared_file" ]; then
                echo "Refusing unexpected file in shared config directory: $entry" >&2
                exit 1
              fi
            done

            tmp=""
            cleanup() {
              if [ -n "$tmp" ]; then "$rm" -f -- "$tmp"; fi
            }
            trap cleanup EXIT

            install_home_file() {
              local source="$1" target="$2" name="$3"
              tmp="$("$mktemp" "$HOME/.$name.XXXXXX")"
              "$install" -m 644 "$source" "$tmp"
              "$mv" -fT "$tmp" "$target"
              tmp=""
            }

            if [ -L "$HOME/devenv.yaml" ] || [ ! -f "$HOME/devenv.yaml" ] || [ "$(file_hash "$HOME/devenv.yaml")" != "$yaml_hash" ]; then
              install_home_file "${yamlFile}" "$HOME/devenv.yaml" devenv.yaml
            fi
            if [ -L "$HOME/devenv.nix" ] || [ ! -f "$HOME/devenv.nix" ] || [ "$(file_hash "$HOME/devenv.nix")" != "$stub_hash" ]; then
              install_home_file "${rootNixFile}" "$HOME/devenv.nix" devenv.nix
            fi
            if [ "$lock_action" = seed ]; then
              install_home_file "${./devenv.lock}" "$lock_target" devenv.lock
            fi

            "$mkdir" -p -m 700 "$state_dir"
            state_tmp="$("$mktemp" "$state_dir/.managed-hashes.XXXXXX")"
            tmp="$state_tmp"
            printf 'yaml=%s\nstub=%s\nconfig=%s\n' "$yaml_hash" "$stub_hash" "${sharedConfigHash}" > "$state_tmp"
            "$chmod" 600 "$state_tmp"
            "$mv" -fT "$state_tmp" "$state_file"
            tmp=""
            echo "Installed shared Devenv config ${sharedConfigHash}; local lock is writable."
          '';
        in
        {
          type = "app";
          program = "${script}";
          meta.description = "Install the shared Devenv defaults for ${username}.";
        };

      setupPiMemoryApp = username:
        let
          script = pkgs.writeShellScript "setup-agent-pi-memory-${username}" ''
            set -euo pipefail

            if [ "''${HOME-}" != "/home/${username}" ]; then
              echo "Run this app as ${username} (HOME must be /home/${username})." >&2
              exit 1
            fi

            exec "${pkgs.python3}/bin/python3" "${./scripts/setup-pi-memory.py}" \
              --expected-home "/home/${username}" \
              --pi-bin "/run/current-system/sw/bin/pi"
          '';
        in
        {
          type = "app";
          program = "${script}";
          meta.description = "Configure the pinned Pi memory stack for ${username}.";
        };

      setupPiOpenBaoAuthApp = username:
        let
          script = pkgs.writeShellScript "setup-agent-pi-openbao-auth-${username}" ''
            set -euo pipefail

            if [ "''${HOME-}" != "/home/${username}" ]; then
              echo "Run this app as ${username} (HOME must be /home/${username})." >&2
              exit 1
            fi

            exec "${pkgs.python3}/bin/python3" "${./scripts/configure-pi-openbao-auth.py}" \
              --expected-home "/home/${username}"
          '';
        in
        {
          type = "app";
          program = "${script}";
          meta.description = "Migrate LiteLLM auth to OpenBao env injection for ${username}.";
        };
    in
    {
      apps.${system} =
        builtins.listToAttrs (
          (map
            (username: {
              name = "devenv-${username}";
              value = installApp username;
            })
            agents
          )
          ++ (map
            (username: {
              name = "pi-memory-${username}";
              value = setupPiMemoryApp username;
            })
            agents
          )
          ++ (map
            (username: {
              name = "pi-openbao-auth-${username}";
              value = setupPiOpenBaoAuthApp username;
            })
            agents
          )
        );
    };
}
