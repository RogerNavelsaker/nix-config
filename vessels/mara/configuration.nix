{
  config,
  devenvPackage,
  lib,
  pkgs,
  herdrPackage,
  agentToolPackages,
  ...
}:

{
  wsl.enable = true;
  wsl.defaultUser = "mara";

  wsl.wslConf.automount.enabled = false;
  wsl.wslConf.interop.enabled = false;
  wsl.wslConf.interop.appendWindowsPath = false;

  networking.hostName = "agent-mara";
  system.stateVersion = "26.05";

  users.groups.mara.gid = 1001;
  users.users.mara = {
    isNormalUser = true;
    uid = 1001;
    group = "mara";
    home = "/home/mara";
    createHome = true;
    extraGroups = [ "wheel" ];
    shell = pkgs.nushell;
  };

  programs.nix-ld.enable = true;
  programs.direnv.enable = true;
  programs.starship.enable = true;

  services.tailscale = {
    enable = true;
    interfaceName = "tailscale-mara0";
  };

  environment.shells = with pkgs; [ nushell ];
  environment.variables = {
    MNEMOSYNE_EMBEDDING_MODEL = "BAAI/bge-small-en-v1.5";
    MNEMOSYNE_EMBEDDINGS_VIA_API = "false";
    MNEMOSYNE_LLM_ENABLED = "false";
  };

  environment.systemPackages =
    (with pkgs; [
      curl
      devenvPackage
      fuse3
      git
      gh
      gnutar
      jq
      nushell
      openssh
      procps
      psmisc
      python3
      rsync
      sshfs
      tailscale
      unzip
      util-linux
    ])
    ++ [ herdrPackage ]
    ++ agentToolPackages;

  systemd.tmpfiles.rules = [
    "d /home/mara/host-windows 0755 mara mara -"
    "d /home/mara/host-windows/C 0755 mara mara -"
    "d /home/mara/host-windows/D 0755 mara mara -"
    "d /home/mara/host-windows/G 0755 mara mara -"
  ];
}
