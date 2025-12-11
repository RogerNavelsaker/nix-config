# This file defines the "non-hardware dependent" part of opt-in persistence
# It imports impermanence, defines the basic persisted dirs, and ensures each
# users' home persist dir exists and has the right permissions
#
# It works even if / is tmpfs, btrfs snapshot, or even not ephemeral at all.
{
  lib,
  inputs,
  config,
  ...
}:
{
  imports = [ inputs.impermanence.nixosModules.impermanence ];

  environment.persistence = {
    "/persist" = {
      # Essential system files that must persist across reboots
      files = [
        "/etc/machine-id"
      ];

      # Essential system directories that must persist
      directories = [
        # Systemd state and timers
        "/var/lib/systemd"
        # NixOS state (profiles, generations, etc.)
        "/var/lib/nixos"
        # System logs
        "/var/log"
        # Services data
        "/srv"
        # Fingerprint reader data (if using fprintd)
        "/var/lib/fprint"
      ];
    };
  };

  # Allow user-space programs to use FUSE for bind mounts
  programs.fuse.userAllowOther = true;

  # Automatically create and configure home persistence directories
  # This ensures /persist/home/<user> exists with correct permissions
  system.activationScripts.persistent-dirs.text =
    let
      mkHomePersist =
        user:
        lib.optionalString user.createHome ''
          mkdir -p /persist/${user.home}
          chown ${user.name}:${user.group} /persist/${user.home}
          chmod ${user.homeMode} /persist/${user.home}
        '';
      users = lib.attrValues config.users.users;
    in
    lib.concatLines (map mkHomePersist users);
}
