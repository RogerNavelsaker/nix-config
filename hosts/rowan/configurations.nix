{ ... }:
let
  agents = [
    "rowan"
    "jules"
    "mira"
    "avery"
  ];
in
builtins.listToAttrs (
  map (agentName: {
    name = agentName;
    value = {
      hostname = agentName;
      users = [ agentName ];
      system = "x86_64-linux";
      stateVersion = "25.11";
      extraModules = [ ../features/opt-in/openbao-client/openbao-client.nix ];
      standaloneHM = true;
      features.opt-out = [
        "impermanence"
        "nh"
      ];
    };
  }) agents
)
