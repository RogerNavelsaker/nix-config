# Impermanence Guide

This repository includes comprehensive impermanence support for ephemeral root filesystems. The impermanence feature is enabled by default and provides automatic persistence management.

## Overview

The impermanence configuration is split into two parts:
- **NixOS-level**: [hosts/features/default/impermanence.nix](hosts/features/default/impermanence.nix) - System-wide persistence
- **Home Manager-level**: [home/features/default/impermanence.nix](home/features/default/impermanence.nix) - User home persistence

## Default Behavior

### System Persistence

By default, the following are persisted in `/persist`:

**Files:**
- `/etc/machine-id` - System identifier

**Directories:**
- `/var/lib/systemd` - Systemd state and timers
- `/var/lib/nixos` - NixOS state (profiles, generations)
- `/var/log` - System logs
- `/srv` - Service data
- `/var/lib/fprint` - Fingerprint reader data

Additionally, home directories are automatically created at `/persist/home/<username>` with correct permissions.

### Home Persistence

Each user gets a persistence directory at `/persist/home/<username>` with `allowOther = true` enabled for service integrations.

## Adding Persistence to Features

### Simple Directory Persistence

In any NixOS feature module:

```nix
{ ... }:
{
  # Your service configuration
  services.myservice.enable = true;

  # Persist the service's state directory
  environment.persistence."/persist".directories = [
    "/var/lib/myservice"
  ];
}
```

### Directory with Specific Permissions

Using the library helpers:

```nix
{ lib, ... }:
{
  services.myservice.enable = true;

  environment.persistence."/persist".directories = [
    (lib.nix-lib.impermanence.mkPersistDir "/var/lib/myservice" "myuser" "mygroup" "0700")
  ];
}
```

### Multiple Directories with Same Ownership

```nix
{ lib, ... }:
{
  environment.persistence."/persist".directories =
    lib.nix-lib.impermanence.mkPersistDirs "root" "root" "0755" [
      "/var/lib/service1"
      "/var/lib/service2"
      "/var/lib/service3"
    ];
}
```

## User-Specific Persistence

In your user's home configuration (e.g., `home/rona/nanoserver.nix`):

```nix
{ config, ... }:
{
  home.persistence."/persist/${config.home.homeDirectory}" = {
    directories = [
      # Application state
      ".config/Code"
      ".config/discord"
      ".local/share/Steam"

      # Development
      "Repositories"
      "Projects"

      # Documents
      "Documents"
      "Downloads"
      "Pictures"
    ];

    files = [
      # SSH keys
      ".ssh/id_ed25519"
      ".ssh/id_ed25519.pub"

      # GPG keys
      ".gnupg/pubring.kbx"
      ".gnupg/trustdb.gpg"
    ];
  };
}
```

## Library Helper Functions

The repository provides several helper functions under `lib.nix-lib.impermanence`:

### `mkPersistDir`
Create a directory persistence configuration with specific permissions.
```nix
mkPersistDir "/var/lib/foo" "root" "root" "0755"
```

### `mkPersistFile`
Create a file persistence configuration with parent directory permissions.
```nix
mkPersistFile "/etc/foo.conf" "root" "root" "0644"
```

### `mkPersistDirs`
Create multiple directory configurations with the same ownership.
```nix
mkPersistDirs "root" "root" "0755" [ "/var/lib/foo" "/var/lib/bar" ]
```

### `mkHomePersistence`
Create home persistence configuration for a user.
```nix
mkHomePersistence "username" [ ".ssh" ".gnupg" ]
```

## Real-World Examples

### WiFi Persistence (iwd)

From [hosts/features/opt-in/wifi/common.nix](hosts/features/opt-in/wifi/common.nix):

```nix
{ ... }:
{
  networking.wireless.iwd.enable = true;

  environment.persistence."/persist".directories = [
    { directory = "/var/lib/iwd"; }
  ];
}
```

### Tailscale Persistence

From [hosts/iso/tailscale.nix](hosts/iso/tailscale.nix):

```nix
{ ... }:
{
  services.tailscale.enable = true;

  environment.persistence."/persist".directories = [
    { directory = "/var/lib/tailscale"; }
  ];
}
```

## Disabling Impermanence

If you want to disable impermanence for a specific host, add it to the opt-out features:

```nix
# In flake.nix
nixosConfigurations.myhost = lib.mkSystem {
  hostname = "myhost";
  features = {
    opt-out = [ "impermanence" ];
  };
};
```

## Filesystem Setup

The impermanence configuration is filesystem-agnostic and works with:
- **tmpfs** - Truly ephemeral root
- **Btrfs snapshots** - Rollback on boot
- **ZFS snapshots** - Rollback on boot
- **Regular filesystems** - Still get the benefits of explicit persistence

For filesystem-specific setup, see the [disko](https://github.com/nix-community/disko) configurations in your host-specific hardware modules.

## Troubleshooting

### Missing Directories on Boot

If services fail due to missing directories, add them to `environment.persistence."/persist".directories`.

### Permission Issues

Use `mkPersistDir` to set correct ownership:
```nix
(lib.nix-lib.impermanence.mkPersistDir "/var/lib/service" "serviceuser" "servicegroup" "0700")
```

### Home Directory Not Created

The activation script automatically creates `/persist/home/<username>` for all users with `createHome = true`. Check that the user is properly configured.
