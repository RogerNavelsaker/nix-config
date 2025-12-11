{ lib, ... }:
let
  inherit (lib) types mkOption;
in
{
  options.hostSpec = {
    hostname = mkOption {
      type = types.str;
      description = "The hostname of the system";
    };

    users = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "List of user accounts for this host";
    };

    stateVersion = mkOption {
      type = types.str;
      default = "25.05";
      description = "NixOS state version";
    };

    domain = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Network domain for the host";
    };

    enabledFeatures = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "List of enabled feature names";
    };
  };
}
