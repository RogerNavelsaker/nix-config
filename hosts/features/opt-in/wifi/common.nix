{
  lib,
  pkgs,
  ...
}:
let
  rescueWifiUp = pkgs.writeShellScriptBin "rescue-wifi-up" ''
    set -eu
    if [ "$EUID" -ne 0 ]; then
      echo "Run with sudo after YubiKey/SOPS unlock." >&2
      exit 1
    fi
    if [ "$#" -gt 1 ]; then
      echo "Usage: rescue-wifi-up [wireless-interface]" >&2
      exit 2
    fi

    profile=/var/lib/iwd/NaCo.psk
    test -s "$profile" || {
      echo "Wi-Fi profile is unavailable; unlock SOPS secrets first." >&2
      exit 1
    }

    interface=''${1:-}
    if [ -z "$interface" ]; then
      for path in /sys/class/net/wl*; do
        [ -e "$path" ] || continue
        interface=''${path##*/}
        break
      done
    fi
    case "$interface" in
      wl*) ;;
      *)
        echo "No wireless interface found; optionally specify one: rescue-wifi-up wlan0" >&2
        exit 1
        ;;
    esac
    test -e "/sys/class/net/$interface" || {
      echo "Wireless interface not found: $interface" >&2
      exit 1
    }

    exec ${pkgs.iwd}/bin/iwctl station "$interface" connect NaCo
  '';
in
{
  options.rescueWifi.autoConnect = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether the SOPS-provisioned iwd profile may auto-connect after unlock.";
  };

  config = {
    # Enable iwd daemon; per-network autoconnect is set in the SOPS profile.
    networking.wireless.iwd = {
      enable = true;
      settings.General.EnableNetworkConfiguration = false; # Using systemd-networkd
    };

    environment.systemPackages = [ rescueWifiUp ];

    # Ensure /var/lib/iwd exists before secrets activation runs
    # This handles first boot before impermanence has restored the directory
    systemd.tmpfiles.rules = [
      "d /var/lib/iwd 0700 root root -"
    ];
  };
}
