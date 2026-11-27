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
  imports = [
    ./hardware-configuration.nix
  ];

  boot.kernelParams = [ "console=ttyS0,115200n8" ];
  boot.loader.grub = {
    enable = true;
    device = "nodev";
    forceInstall = true;
    extraConfig = ''
      serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1;
      terminal_input serial;
      terminal_output serial
    '';
  };
  boot.loader.timeout = 10;

  networking.hostName = "agent-alex";
  networking.networkmanager.enable = true;

  environment.variables = {
    MNEMOSYNE_EMBEDDING_MODEL = "BAAI/bge-small-en-v1.5";
    MNEMOSYNE_EMBEDDINGS_VIA_API = "false";
    MNEMOSYNE_LLM_ENABLED = "false";
  };

  environment.systemPackages = [
    devenvPackage
    pkgs.nushell
    pkgs.git
    pkgs.gh
    herdrPackage
  ]
  ++ agentToolPackages;
  environment.shells = with pkgs; [ nushell ];
  programs.direnv.enable = true;
  programs.starship.enable = true;

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };

  services.tailscale.enable = true;

  services.openBaoClient = {
    enable = true;
    acme.identityDnsName = "agent-alex.naco.casa";
    openBao = {
      address = "https://openbao-mtls.naco.casa";
      certAuthMount = "auth/cert";
      certAuthRole = "agent-alex.naco.casa";
    };
  };

  users.users.alex = {
    shell = pkgs.nushell;
    isNormalUser = true;
    extraGroups = [ "wheel" ];
  };

  security.sudo.wheelNeedsPassword = false;
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  system.stateVersion = "26.05";
}
