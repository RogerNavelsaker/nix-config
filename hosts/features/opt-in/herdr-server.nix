{ inputs, pkgs, ... }:
let
  herdr = inputs.herdr.packages.${pkgs.system}.default;
in
{
  environment.systemPackages = [ herdr ];

  users.users.admin.linger = true;
  environment.persistence."/persist".users.admin.directories = [ ".config/herdr" ];

  systemd.user.services.herdr-server = {
    description = "Herdr headless server";
    wantedBy = [ "default.target" ];
    serviceConfig = {
      ExecStart = "${herdr}/bin/herdr server";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };
}
