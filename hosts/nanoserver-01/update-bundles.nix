{ pkgs, self }:
{
  nanoserver-01-update-bundle = pkgs.runCommand "nanoserver-01-update-bundle" { } ''
    set -euo pipefail
    mkdir -p "$out"
    cp ${self.nixosConfigurations.nanoserver-01-update-v2-a.config.system.build.applianceStoreTarball}/nanoserver-store_2.tar.xz \
      "$out/nanoserver-store_2.tar.xz"
    cp ${self.nixosConfigurations.nanoserver-01-update-v2-a.config.system.build.applianceStoreRegistration} \
      "$out/nanoserver-store_2.registration"
    cp ${self.nixosConfigurations.nanoserver-01-update-v2-a.config.system.build.uki}/${self.nixosConfigurations.nanoserver-01-update-v2-a.config.system.boot.loader.ukiFile} \
      "$out/nanoserver-root_2+3-slot-a.efi"
    cp ${self.nixosConfigurations.nanoserver-01-update-v2-b.config.system.build.uki}/${self.nixosConfigurations.nanoserver-01-update-v2-b.config.system.boot.loader.ukiFile} \
      "$out/nanoserver-root_2+3-slot-b.efi"
    cd "$out"
    sha256sum nanoserver-store_2.tar.xz nanoserver-store_2.registration nanoserver-root_2+3-slot-a.efi nanoserver-root_2+3-slot-b.efi > SHA256SUMS
  '';

}
