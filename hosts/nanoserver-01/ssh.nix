_: {
  users.mutableUsers = false;
  users.groups.admin = { };
  users.users.admin = {
    isNormalUser = true;
    group = "admin";
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keyFiles = [ ./rona.pub ];
  };

  services.openssh = {
    enable = true;
    openFirewall = true;
    hostKeys = [
      {
        path = "/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      AllowUsers = [ "admin" ];
    };
  };
}
