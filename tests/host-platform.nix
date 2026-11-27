{
  pkgs,
  lib,
  self,
}:
let
  expectedProfiles = [
    "miniserver-01"
    "miniserver-01-slot-b"
    "miniserver-02"
    "miniserver-02-slot-b"
    "miniserver-03"
    "miniserver-03-slot-b"
    "nanoserver-01-update-v4-a"
    "nanoserver-01-update-v4-b"
  ];

  persistedDirectories = [
    "/var/lib/containers"
    "/var/lib/libvirt"
  ];

  profilePasses =
    name:
    let
      cfg = self.nixosConfigurations.${name}.config;
      persistence = cfg.environment.persistence."/persist".directories;
      hasPersistentDirectory = directory: lib.any (entry: entry.directory == directory) persistence;
    in
    !cfg.services.k3s.enable
    && cfg.virtualisation.libvirtd.enable
    && cfg.virtualisation.podman.enable
    && builtins.elem "libvirtd" cfg.users.users.rona.extraGroups
    && builtins.all hasPersistentDirectory persistedDirectories
    && lib.any (
      entry: entry.directory == ".local/share/containers"
    ) cfg.environment.persistence."/persist".users.rona.directories;

  transferNames = [
    "sysupdate.nanoserver.d/10-store.transfer"
    "sysupdate.nanoserver.d/20-registration.transfer"
    "sysupdate.nanoserver.d/80-uki-boot-a.transfer"
    "sysupdate.nanoserver.d/81-uki-boot-b.transfer"
  ];
  v3 = self.nixosConfigurations.nanoserver-01-update-v3-a.config;
  v4 = self.nixosConfigurations.nanoserver-01-update-v4-a.config;
  operationalPackageNames = [
    "btop"
    "btrfs-progs"
    "ethtool"
    "nvme-cli"
    "podman-tui"
    "smartmontools"
    "tcpdump"
    "virt-top"
  ];
  systemPackageName = package: package.pname or package.name;
  operationalPackages = lib.filter (
    package: builtins.elem (systemPackageName package) operationalPackageNames
  ) v4.environment.systemPackages;
  hasSystemPackage =
    name: lib.any (package: systemPackageName package == name) v4.environment.systemPackages;
  operationalToolsClosure = pkgs.closureInfo { rootPaths = operationalPackages; };
  headlessQemuClosure = pkgs.closureInfo {
    rootPaths = [ v4.virtualisation.libvirtd.qemu.package ];
  };
  v3Transfers = map (name: v3.environment.etc.${name}.source) transferNames;
  v4Transfers = map (name: v4.environment.etc.${name}.source) transferNames;
in
assert builtins.all profilePasses expectedProfiles;
assert !v3.services.k3s.enable;
assert !v3.virtualisation.libvirtd.enable;
assert !v3.virtualisation.podman.enable;
assert !(v3.systemd.user.services.herdr-server.enable or false);
assert !v4.services.k3s.enable;
assert builtins.all hasSystemPackage operationalPackageNames;
assert !(hasSystemPackage "k9s");
assert !(hasSystemPackage "kubectl");
assert v4.users.users.rona.linger;
assert lib.any (
  entry: entry.directory == ".config/herdr"
) v4.environment.persistence."/persist".users.rona.directories;
assert v4.systemd.user.services.herdr-server.enable;
assert v4.systemd.user.services.herdr-server.serviceConfig.ExecStart != "";
assert builtins.all (
  name: !self.nixosConfigurations.${name}.config.documentation.enable
) expectedProfiles;
assert builtins.hasAttr "systemd/import-pubring.gpg" v4.environment.etc;
pkgs.runCommand "host-platform-check" { nativeBuildInputs = [ pkgs.gnugrep ]; } ''
  if grep -E '(sdl2|sdl3|gtk[234]|libpulse|pipewire|jack2|spice|virgl|libgbm|flite|freepats)' ${headlessQemuClosure}/store-paths; then
    echo "Headless libvirt QEMU closure contains desktop video/audio dependencies" >&2
    exit 1
  fi
  if grep -E '(gtk[234]|qt[56]|sdl[23])' ${operationalToolsClosure}/store-paths; then
    echo "Headless operational tools closure contains desktop dependencies" >&2
    exit 1
  fi
  for transfer in ${lib.concatMapStringsSep " " toString v3Transfers}; do
    grep -q '^[[:space:]]*Verify=yes$' "$transfer"
  done
  for transfer in ${lib.concatMapStringsSep " " toString v4Transfers}; do
    if grep -q '^[[:space:]]*Verify=yes$' "$transfer"; then
      echo "Nanoserver v4 must omit unsupported systemd-sysupdate Verify keys" >&2
      exit 1
    fi
  done
  touch "$out"
''
