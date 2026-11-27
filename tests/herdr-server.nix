{ pkgs, herdr }:
pkgs.testers.runNixOSTest {
  name = "herdr-server-service";

  nodes.machine = {
    environment.systemPackages = [ herdr ];

    users.users.rona = {
      isNormalUser = true;
      createHome = true;
      uid = 1000;
      linger = true;
    };

    systemd.user.services.herdr-server = {
      description = "Herdr headless server";
      wantedBy = [ "default.target" ];
      serviceConfig = {
        ExecStart = "${herdr}/bin/herdr server";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };

    system.stateVersion = "25.11";
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("user@1000.service")
    machine.wait_until_succeeds("test -S /home/rona/.config/herdr/herdr.sock")

    status = machine.succeed(
        "runuser -u rona -- env HOME=/home/rona herdr status server --json"
    )
    assert '"running":true' in status, status

    api = machine.succeed(
        "runuser -u rona -- env HOME=/home/rona herdr workspace list"
    )
    assert '"type":"workspace_list"' in api, api
  '';
}
