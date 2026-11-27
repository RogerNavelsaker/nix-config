{
  lib,
  pkgs,
  self,
}:
let
  hosts = [
    "miniserver-01"
    "miniserver-02"
    "miniserver-03"
  ];
  finalConfigurations = map (hostname: self.nixosConfigurations.${hostname}) hosts;
  bootstrapConfigurations = map (hostname: self.nixosConfigurations."${hostname}-bootstrap") hosts;
  storeMountOptions = config: config.config.fileSystems."/nix/store".options;
  hasSwitch = config: config.config.system.switch.enable;
  hasRuntimeNix = config: config.config.nix.enable;
  hasReadOnlyStore = config: builtins.elem "ro" (storeMountOptions config);
  hasWifi = config: config.config.networking.wireless.iwd.enable;
  hasWifiSecret = config: config.config.sops.secrets."wifi-NaCo".key == "wifi/NaCo";
  hasProfileRepair =
    config: builtins.hasAttr "fix-profile-permissions" config.config.system.activationScripts;
in
assert builtins.all hasSwitch bootstrapConfigurations;
assert builtins.all hasRuntimeNix bootstrapConfigurations;
assert builtins.all (config: !hasSwitch config) finalConfigurations;
assert builtins.all (config: !hasRuntimeNix config) finalConfigurations;
assert builtins.all (config: !hasReadOnlyStore config) bootstrapConfigurations;
assert builtins.all hasReadOnlyStore finalConfigurations;
assert builtins.all (
  hostname:
  let
    final = self.nixosConfigurations.${hostname}.config.appliance;
    bootstrap = self.nixosConfigurations."${hostname}-bootstrap".config.appliance;
  in
  final.storeName != bootstrap.storeName || final.rootVersion != bootstrap.rootVersion
) hosts;
assert builtins.all (hostname: hasWifi (self.nixosConfigurations.${hostname})) hosts;
assert builtins.all (hostname: hasWifiSecret (self.nixosConfigurations.${hostname})) hosts;
assert builtins.all (hostname: hasProfileRepair (self.nixosConfigurations.${hostname})) hosts;
pkgs.runCommand "miniserver-bootstrap-profile-check" { } ''
  ${lib.concatMapStringsSep "\n" (config: ''
    test -x ${config.config.system.build.toplevel}/bin/switch-to-configuration
  '') bootstrapConfigurations}
  ${lib.concatMapStringsSep "\n" (config: ''
    test ! -e ${config.config.system.build.toplevel}/bin/switch-to-configuration
  '') finalConfigurations}
  touch "$out"
''
