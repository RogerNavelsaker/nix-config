{
  config,
  lib,
  pkgs,
  ...
}:
let
  mode = config.rescueIso.networkMode;
  rescueLan = mode == "rescue-lan";

  rescueHostname = pkgs.writeShellScript "rescue-runtime-hostname" ''
    set -eu
    identity=""
    for path in /sys/class/dmi/id/product_uuid /etc/machine-id; do
      if [ -r "$path" ]; then
        identity=$(cat "$path")
        [ -n "$identity" ] && break
      fi
    done
    if [ -z "$identity" ]; then
      for path in /sys/class/net/*/address; do
        [ "$(basename "$(dirname "$path")")" = lo ] && continue
        identity=$(cat "$path")
        [ -n "$identity" ] && break
      done
    fi
    [ -n "$identity" ] || exit 1
    suffix=$(printf '%s' "$identity" | ${pkgs.coreutils}/bin/sha256sum | cut -c1-10)
    printf 'rescue-%s\n' "$suffix" > /proc/sys/kernel/hostname
  '';
in
{
  options.rescueIso.networkMode = lib.mkOption {
    type = lib.types.enum [
      "wan"
      "lan"
      "rescue-lan"
    ];
    default = "wan";
    description = "Explicit GRUB-selected networking and SSH mode for the rescue ISO.";
  };

  config = {
    rescueWifi.autoConnect = mode == "wan";

    networking = {
      networkmanager.enable = lib.mkForce false;
      useNetworkd = true;
      useDHCP = false;
      wireless.enable = false;
      firewall.allowedUDPPorts = lib.optionals rescueLan [ 67 ];
    };

    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = lib.mkForce 0;
      "net.ipv6.conf.all.forwarding" = lib.mkForce 0;
    };

    systemd = {
      network = {
        enable = true;
        wait-online.enable = false;
        networks = {
          "10-wired-client" = lib.mkIf (!rescueLan) {
            matchConfig.Name = "en*";
            networkConfig.DHCP = "ipv4";
            dhcpV4Config.RouteMetric = 100;
          };

          "10-wired-rescue" = lib.mkIf rescueLan {
            matchConfig.Name = "en*";
            networkConfig = {
              Address = "192.168.77.1/29";
              DHCPServer = true;
              IPv6AcceptRA = false;
              IPv4Forwarding = false;
              IPv6Forwarding = false;
            };
            dhcpServerConfig = {
              PoolOffset = 2;
              PoolSize = 5;
              EmitDNS = false;
              EmitRouter = false;
            };
          };

          "20-wlan-client" = {
            matchConfig.Name = "wl*";
            networkConfig.DHCP = "ipv4";
            dhcpV4Config.RouteMetric = 200;
          };
        };
      };

      services = {
        rescue-runtime-hostname = {
          description = "Set unique headless rescue hostname before networking";
          wantedBy = [ "network-pre.target" ];
          before = [
            "network-pre.target"
            "systemd-networkd.service"
            "avahi-daemon.service"
          ];
          after = [ "systemd-udevd.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = rescueHostname;
          };
        };

        avahi-daemon = {
          after = [
            "rescue-runtime-hostname.service"
            "systemd-networkd.service"
          ];
          wants = [ "rescue-runtime-hostname.service" ];
        };
      };
    };

    services.avahi = {
      enable = true;
      hostName = "";
      publish = {
        addresses = true;
        workstation = true;
      };
    };
  };
}
