{ inputs, self, ... }:
let
  base = hostname: {
    inherit hostname;
    users = [ "rona" ];
    system = "x86_64-linux";
    stateVersion = "25.11";
    secrets = inputs.nix-secrets;
    features.opt-in = [
      "appliance"
      "appliance-disko"
      "wifi/NaCo"
      "host-platform"
    ];
  };

  final =
    hostname: extraModules:
    (base hostname)
    // {
      extraModules = [
        {
          appliance.bootstrapStoreSubvolume = "${hostname}-bootstrap-store_bootstrap";
        }
      ]
      ++ extraModules;
    };

  bootstrap =
    hostname:
    let
      finalA = self.nixosConfigurations.${hostname}.config;
      finalB = self.nixosConfigurations."${hostname}-slot-b".config;
    in
    (base hostname)
    // {
      extraModules = [
        ({ lib, ... }: {
          appliance = {
            rootSlot = "a";
            rootVersion = "bootstrap";
            storeName = "${hostname}-bootstrap-store";
            storeReadOnly = false;
            bootstrap = {
              enable = true;
              finalStoreName = finalA.appliance.storeName;
              finalRootVersion = finalA.appliance.rootVersion;
              finalToplevelName = builtins.baseNameOf (toString finalA.system.build.toplevel);
              finalStoreTarball = "${finalA.system.build.applianceStoreTarball}/${finalA.appliance.storeName}_${finalA.appliance.rootVersion}.tar.xz";
              finalStoreRegistration = toString finalA.system.build.applianceStoreRegistration;
              finalSlotAuki = "${finalA.system.build.uki}/${finalA.system.boot.loader.ukiFile}";
              finalSlotAukiFile = finalA.system.boot.loader.ukiFile;
              finalSlotBuki = "${finalB.system.build.uki}/${finalB.system.boot.loader.ukiFile}";
              finalSlotBukiFile = finalB.system.boot.loader.ukiFile;
            };
          };
          nix.enable = lib.mkForce true;
          system.switch.enable = lib.mkForce true;
        })
      ];
    };
in
{
  miniserver-01 = final "miniserver-01" [
    {
      appliance = {
        rootSlot = "a";
        storeClosureToplevels = [
          self.nixosConfigurations.miniserver-01-slot-b.config.system.build.toplevel
        ];
        peerUki = self.nixosConfigurations.miniserver-01-slot-b.config.system.build.uki;
      };
    }
  ];
  miniserver-01-slot-b = final "miniserver-01" [ { appliance.rootSlot = "b"; } ];
  miniserver-01-bootstrap = bootstrap "miniserver-01";

  miniserver-02 = final "miniserver-02" [
    {
      appliance = {
        rootSlot = "a";
        storeClosureToplevels = [
          self.nixosConfigurations.miniserver-02-slot-b.config.system.build.toplevel
        ];
        peerUki = self.nixosConfigurations.miniserver-02-slot-b.config.system.build.uki;
      };
    }
  ];
  miniserver-02-slot-b = final "miniserver-02" [ { appliance.rootSlot = "b"; } ];
  miniserver-02-bootstrap = bootstrap "miniserver-02";

  miniserver-03 = final "miniserver-03" [
    {
      appliance = {
        rootSlot = "a";
        storeClosureToplevels = [
          self.nixosConfigurations.miniserver-03-slot-b.config.system.build.toplevel
        ];
        peerUki = self.nixosConfigurations.miniserver-03-slot-b.config.system.build.uki;
      };
    }
  ];
  miniserver-03-slot-b = final "miniserver-03" [ { appliance.rootSlot = "b"; } ];
  miniserver-03-bootstrap = bootstrap "miniserver-03";
}
