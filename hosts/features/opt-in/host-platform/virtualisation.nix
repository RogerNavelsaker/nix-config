{ ... }:
{
  virtualisation.libvirtd = {
    enable = true;
    # QEMU guests run as the dedicated unprivileged qemu-libvirtd account.
    qemu.runAsRoot = false;
  };

  virtualisation.podman.enable = true;

  users.users.rona.extraGroups = [ "libvirtd" ];
}
