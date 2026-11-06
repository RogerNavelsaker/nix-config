{
  agentName,
  config,
  inputs,
  lib,
  modulesPath,
  pkgs,
  utils,
  ...
}:
let
  agentPackages = pkgs.inputs.nixpkgs-packages;
  agentToolPackages = [
    (builtins.getAttr pkgs.system inputs.headroom.packages).headroom
    agentPackages.nixpkg-caveman.caveman-cli
    agentPackages.nixpkg-pi-coding-agent.default
    agentPackages.nixpkg-pi-coding-agent.default.pi
    agentPackages.nixpkg-mnemosyne.mnemosyne-memory
    agentPackages.nixpkg-seeds.default
    agentPackages.nixpkg-mulch.default
    agentPackages.nixpkg-terrarium.default
  ];
  devenvPackage = (builtins.getAttr pkgs.system inputs.devenv.packages).devenv;
  herdrPackage = (builtins.getAttr pkgs.system inputs.herdr.packages).default;
  logrotateConfig = "/run/logrotate.conf";
  logrotateConfigSource = config.services.logrotate.configFile;
  logrotateExtraArgs = utils.escapeSystemdExecArgs config.services.logrotate.extraArgs;
  logrotateMailOption = lib.optionalString (lib.foldr (
    setting: acc: acc || (setting.mail or false) != false
  ) false (lib.attrValues config.services.logrotate.settings)) "--mail=${pkgs.mailutils}/bin/mail";
  prepareLogrotateConfig = ''
    ${pkgs.coreutils}/bin/install -o root -g root -m 0644 ${logrotateConfigSource} ${logrotateConfig}
  '';
in
{
  imports = [
    "${modulesPath}/virtualisation/lxc-container.nix"
  ];

  # Unprivileged LXCs cannot mount kernel debugfs.
  systemd.suppressedSystemUnits = [ "sys-kernel-debug.mount" ];

  networking.hostName = lib.mkForce "agent-${agentName}";
  networking.useDHCP = true;

  users.groups.${agentName}.gid = 1000;
  users.users.${agentName} = {
    isNormalUser = true;
    uid = 1000;
    group = agentName;
    home = "/home/${agentName}";
    createHome = true;
    shell = pkgs.nushell;
    initialHashedPassword = lib.mkForce null;
  };

  # Scope NOPASSWD sudo to the named agent account.
  security.sudo.extraRules = [
    {
      users = [ agentName ];
      commands = [
        {
          command = "ALL";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  # The upstream LXC module permits empty-password root login; keep root locked.
  users.users.root.initialHashedPassword = lib.mkForce null;

  # Keep guest OpenSSH disabled; Tailscale SSH is governed by tailnet ACL policy.
  services.openssh.enable = false;
  services.tailscale.enable = true;
  services.tailscale.extraSetFlags = [ "--ssh" ];

  # Temporary Rowan canary override; move into its profile during the config-layout rebuild.
  services.openBaoClient = {
    enable = true;
    acme.identityDnsName =
      if agentName == "rowan" then "agent-rowan.wampus-cloud.ts.net" else "agent-${agentName}.naco.casa";
    openBao = {
      enable = agentName == "rowan";
      address = "https://openbao-mtls.naco.casa";
      serverCaFile = if agentName == "rowan" then "${./openbao-server-ca.pem}" else null;
      certAuthMount = "auth/cert";
      certAuthRole = if agentName == "rowan" then "agent-rowan" else "agent-${agentName}.naco.casa";
      secrets =
        if agentName == "rowan" then
          {
            ROWAN_OPENBAO_CANARY = {
              path = "kv/data/agents/rowan/openbao-mtls-canary-20261029";
              field = "integration_canary";
            };
          }
        else
          { };
    };
  };

  # The shared host store's root owner is unmapped inside the guest user namespace.
  # shortcut: current generated rules are self-contained; copy included configs if adding includes.
  systemd.services.logrotate = {
    preStart = prepareLogrotateConfig;
    serviceConfig.ExecStart = lib.mkForce "${lib.getExe pkgs.logrotate} ${logrotateExtraArgs} ${logrotateMailOption} ${logrotateConfig}";
  };
  systemd.services.logrotate-checkconf = {
    preStart = prepareLogrotateConfig;
    serviceConfig.ExecStart = lib.mkForce "${pkgs.logrotate}/sbin/logrotate ${logrotateExtraArgs} --debug ${logrotateConfig}";
  };

  # The LXC supplies the host socket; do not activate a guest Nix daemon.
  systemd.sockets.nix-daemon.enable = false;
  systemd.services.nix-daemon.enable = false;

  # Trust the public, signed Devenv cache without granting agents nix trusted-user rights.
  nix.settings.extra-substituters = [ "https://devenv.cachix.org" ];
  nix.settings.extra-trusted-public-keys = [
    "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
  ];

  # The shared NTFS workspace has host IDs outside the guest user namespace.
  environment.etc."gitconfig".text = ''
    [safe]
    directory = /workspace
    directory = /workspace/*
  '';

  environment.shells = [ pkgs.nushell ];

  environment.variables = {
    MNEMOSYNE_EMBEDDING_MODEL = "BAAI/bge-small-en-v1.5";
    MNEMOSYNE_EMBEDDINGS_VIA_API = "false";
    MNEMOSYNE_LLM_ENABLED = "false";
  };

  environment.systemPackages = [
    devenvPackage
    pkgs.direnv
    pkgs.git
    pkgs.gh
    herdrPackage
    pkgs.nushell
    pkgs.starship
  ]
  ++ agentToolPackages;
}
