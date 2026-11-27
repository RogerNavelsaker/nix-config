{ inputs, pkgs, ... }:
let
  herdr = inputs.herdr.packages.${pkgs.system}.default;
in
{
  environment.systemPackages = [ herdr ];

  users.users.rona.linger = true;
  environment.persistence."/persist".users.rona.directories = [ ".config/herdr" ];

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
