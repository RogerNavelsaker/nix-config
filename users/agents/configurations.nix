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
    name = "${agentName}@agent-${agentName}";
    value = {
      username = agentName;
      hostname = "agent-${agentName}";
      system = "x86_64-linux";
      stateVersion = "25.11";
      # Do not inherit the primary operator's Git identity or SSH key paths.
      features.opt-out = [
        "git"
        "ssh"
      ];
    };
  }) agents
)
