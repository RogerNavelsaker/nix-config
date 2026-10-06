{ pkgs, self }:
{
  nanoserver-01-update-bundle = pkgs.runCommand "nanoserver-01-update-bundle" { } ''
    set -euo pipefail
    mkdir -p "$out"
    cp ${self.nixosConfigurations.nanoserver-01-update-v3-a.config.system.build.applianceStoreTarball}/nanoserver-store_3.tar.xz \
      "$out/nanoserver-store_3.tar.xz"
    cp ${self.nixosConfigurations.nanoserver-01-update-v3-a.config.system.build.applianceStoreRegistration} \
      "$out/nanoserver-store_3.registration"
    cp ${self.nixosConfigurations.nanoserver-01-update-v3-a.config.system.build.uki}/${self.nixosConfigurations.nanoserver-01-update-v3-a.config.system.boot.loader.ukiFile} \
      "$out/nanoserver-root_3+3-slot-a.efi"
    cp ${self.nixosConfigurations.nanoserver-01-update-v3-b.config.system.build.uki}/${self.nixosConfigurations.nanoserver-01-update-v3-b.config.system.boot.loader.ukiFile} \
      "$out/nanoserver-root_3+3-slot-b.efi"
    cd "$out"
    sha256sum nanoserver-store_3.tar.xz nanoserver-store_3.registration nanoserver-root_3+3-slot-a.efi nanoserver-root_3+3-slot-b.efi > SHA256SUMS
  '';

  nanoserver-01-update-v4-bundle = pkgs.runCommand "nanoserver-01-update-v4-bundle" { } ''
    set -euo pipefail
    mkdir -p "$out"
    cp ${self.nixosConfigurations.nanoserver-01-update-v4-a.config.system.build.applianceStoreTarball}/nanoserver-store_4.tar.xz \
      "$out/nanoserver-store_4.tar.xz"
    cp ${self.nixosConfigurations.nanoserver-01-update-v4-a.config.system.build.applianceStoreRegistration} \
      "$out/nanoserver-store_4.registration"
    cp ${self.nixosConfigurations.nanoserver-01-update-v4-a.config.system.build.uki}/${self.nixosConfigurations.nanoserver-01-update-v4-a.config.system.boot.loader.ukiFile} \
      "$out/nanoserver-root_4+4-slot-a.efi"
    cp ${self.nixosConfigurations.nanoserver-01-update-v4-b.config.system.build.uki}/${self.nixosConfigurations.nanoserver-01-update-v4-b.config.system.boot.loader.ukiFile} \
      "$out/nanoserver-root_4+4-slot-b.efi"
    cd "$out"
    sha256sum nanoserver-store_4.tar.xz nanoserver-store_4.registration nanoserver-root_4+4-slot-a.efi nanoserver-root_4+4-slot-b.efi > SHA256SUMS
  '';

}
