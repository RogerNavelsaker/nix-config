{
  config,
  pkgs,
  ...
}:
let
  inherit (config.appliance) rootVersion storeClosureToplevels storeName;
  toplevels = [ config.system.build.toplevel ] ++ storeClosureToplevels;
  closureInfo = pkgs.closureInfo { rootPaths = toplevels; };
  storeTarball =
    pkgs.runCommand "${storeName}_${rootVersion}-payload"
      {
        nativeBuildInputs = [
          pkgs.coreutils
          pkgs.gnutar
          pkgs.xz
        ];
      }
      ''
        set -euo pipefail
        payload="$TMPDIR/store"
        mkdir -p "$payload" "$out"

        while IFS= read -r store_path; do
          cp -a "$store_path" "$payload/"
        done < ${closureInfo}/store-paths

        tar --sort=name --mtime='@1' --owner=0 --group=0 --numeric-owner \
          -C "$payload" -cf - . \
          | xz --threads=0 -6 > "$out/${storeName}_${rootVersion}.tar.xz"
      '';
in
{
  config.system = {
    image = {
      id = config.networking.hostName;
      version = rootVersion;
    };

    build = {
      applianceStoreTarball = storeTarball;
      applianceStoreRegistration = "${closureInfo}/registration";
    };
  };
}
