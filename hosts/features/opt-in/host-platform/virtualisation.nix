{ pkgs, ... }:
{
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm.override {
        alsaSupport = false;
        enableDocs = false;
        gtkSupport = false;
        jackSupport = false;
        openGLSupport = false;
        pipewireSupport = false;
        pulseSupport = false;
        rutabagaSupport = false;
        sdlSupport = false;
        spiceSupport = false;
        usbredirSupport = false;
        vncSupport = false;
        virglSupport = false;
      };
      # Guests use serial consoles; don't ship desktop display/audio backends.
      runAsRoot = false;
    };
  };

  virtualisation.podman.enable = true;

  users.users.rona.extraGroups = [ "libvirtd" ];
}
