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
    ];
  };
in
{
  miniserver-01 = (base "miniserver-01") // {
    extraModules = [
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
  };
  miniserver-01-slot-b = (base "miniserver-01") // {
    extraModules = [ { appliance.rootSlot = "b"; } ];
  };

  miniserver-02 = (base "miniserver-02") // {
    extraModules = [
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
  };
  miniserver-02-slot-b = (base "miniserver-02") // {
    extraModules = [ { appliance.rootSlot = "b"; } ];
  };

  miniserver-03 = (base "miniserver-03") // {
    extraModules = [
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
  };
  miniserver-03-slot-b = (base "miniserver-03") // {
    extraModules = [ { appliance.rootSlot = "b"; } ];
  };
}
