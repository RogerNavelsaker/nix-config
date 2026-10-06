{ inputs, self }:
{
  nanoserver-01 = {
    hostname = "nanoserver-01";
    users = [ "rona" ];
    system = "x86_64-linux";
    stateVersion = "25.11";
    secrets = inputs.nix-secrets;
    features.opt-in = [
      "appliance"
      "appliance-disko"
      "passwordless-sudo"
      "wifi/NaCo"
    ];
    extraModules = [
      {
        appliance = {
          rootSlot = "a";
          storeClosureToplevels = [
            self.nixosConfigurations.nanoserver-01-slot-b.config.system.build.toplevel
          ];
          peerUki = self.nixosConfigurations.nanoserver-01-slot-b.config.system.build.uki;
        };
      }
    ];
  };

  nanoserver-01-slot-b = {
    hostname = "nanoserver-01";
    users = [ "rona" ];
    system = "x86_64-linux";
    stateVersion = "25.11";
    secrets = inputs.nix-secrets;
    features.opt-in = [
      "appliance"
      "appliance-disko"
      "passwordless-sudo"
      "wifi/NaCo"
    ];
    extraModules = [ { appliance.rootSlot = "b"; } ];
  };

  nanoserver-01-update-v2-a = {
    hostname = "nanoserver-01";
    users = [ "rona" ];
    system = "x86_64-linux";
    stateVersion = "25.11";
    secrets = inputs.nix-secrets;
    features.opt-in = [
      "appliance"
      "appliance-disko"
      "passwordless-sudo"
      "wifi/NaCo"
    ];
    extraModules = [
      {
        appliance = {
          rootVersion = "2";
          rootSlot = "a";
          storeClosureToplevels = [
            self.nixosConfigurations.nanoserver-01-update-v2-b.config.system.build.toplevel
          ];
          peerUki = self.nixosConfigurations.nanoserver-01-update-v2-b.config.system.build.uki;
        };
      }
    ];
  };

  nanoserver-01-update-v2-b = {
    hostname = "nanoserver-01";
    users = [ "rona" ];
    system = "x86_64-linux";
    stateVersion = "25.11";
    secrets = inputs.nix-secrets;
    features.opt-in = [
      "appliance"
      "appliance-disko"
      "passwordless-sudo"
      "wifi/NaCo"
    ];
    extraModules = [
      {
        appliance = {
          rootVersion = "2";
          rootSlot = "b";
        };
      }
    ];
  };

}
