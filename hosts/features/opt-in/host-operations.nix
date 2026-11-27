{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    btop
    btrfs-progs
    ethtool
    nvme-cli
    podman-tui
    smartmontools
    tcpdump
    virt-top
  ];
}
