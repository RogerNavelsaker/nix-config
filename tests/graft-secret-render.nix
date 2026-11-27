{ pkgs }:
let
  fakeAgent = pkgs.writeText "graft-fake-agent.py" ''
    import json
    import os
    from pathlib import Path
    import re
    import subprocess
    import sys

    config = Path(sys.argv[1].split("=", 1)[1]).read_text()
    env_names = re.findall(r"^\s*env_template \"?([A-Za-z_][A-Za-z0-9_]*)\"? \{", config, re.M)
    commands = re.findall(r"^\s*command = (\[.*\])$", config, re.M)
    token_paths = re.findall(r"^\s*path = (\".*\")$", config, re.M)
    assert env_names and len(commands) == len(token_paths) == 1, (env_names, len(commands), len(token_paths))
    token_path = json.loads(token_paths[0])
    Path(token_path).write_text("fixture-token\n")
    os.chmod(token_path, 0o600)
    env = os.environ.copy()
    env.update({name: "harmless-canary" for name in env_names})
    raise SystemExit(subprocess.run(json.loads(commands[0]), env=env).returncode)
  '';
  fakeOpenBao = pkgs.writeShellScriptBin "bao" ''
    if test "$1" = token; then
      test "$BAO_TOKEN" = fixture-token || exit 1
      if test -n "$XDG_RUNTIME_DIR"; then : > "$XDG_RUNTIME_DIR/graft-fake-token-revoke.ok"; fi
      exit 0
    fi
    if test -e /run/fail-graft-render; then exit 42; fi
    config="$2"
    config_file="$(printf '%s' "$config" | sed 's/^-config=//')"
    if grep -q '^[[:space:]]*env_template ' "$config_file"; then
      exec ${pkgs.python3}/bin/python3 ${fakeAgent} "$config"
    fi
    printf 'rendered\n' >> /run/graft-render-count
    ${pkgs.python3}/bin/python3 -c 'import json,re,sys,os,subprocess; text=open(sys.argv[1].split("=",1)[1]).read(); destinations=[json.loads(x) for x in re.findall(r"^\s*destination = (\".*\")$",text,re.M)]; commands=[json.loads(x) for x in re.findall(r"^\s*command = (\[.*\])$",text,re.M)]; tokens=[json.loads(x) for x in re.findall(r"^\s*path = (\".*\")$",text,re.M)]; assert destinations and len(destinations)==len(commands) and len(tokens)==1; [(open(d,"w").write("fixture-secret"),os.chmod(d,0o400),subprocess.run(c,check=True)) for d,c in zip(destinations,commands)]; open(tokens[0],"w").write("fixture-token\n"); os.chmod(tokens[0],0o600)' "$config"
    exec ${pkgs.coreutils}/bin/sleep 30
  '';
  consumerImage = pkgs.dockerTools.buildImage {
    name = "graft-systemd-consumer";
    tag = "test";
    copyToRoot = pkgs.buildEnv {
      name = "graft-systemd-consumer-root";
      paths = [ pkgs.busybox ];
      pathsToLink = [ "/bin" ];
    };
    config.Cmd = [
      "/bin/busybox"
      "sh"
      "-c"
      ''
        test -r /run/secrets/test-token && test -s /run/secrets/test-token
        echo started >> /state/start-count
        trap 'exit 0' TERM INT
        while :; do /bin/busybox sleep 1; done
      ''
    ];
  };
  userRunProbe = pkgs.writeShellScript "graft-user-run-probe" ''
    test -n "$TOKEN"
    : > "$XDG_RUNTIME_DIR/graft-user-run-probe.ok"
  '';
  testPkgs = pkgs.extend (_final: _prev: { openbao = fakeOpenBao; });
in
testPkgs.testers.runNixOSTest {
  name = "graft-systemd-secret-render";

  nodes.machine = { lib, ... }: {
    imports = [ ../hosts/features/opt-in/openbao-client/openbao-client.nix ];
    networking.hostName = "agent-test";
    services.tailscale.enable = true;
    systemd.services.tailscaled.wantedBy = lib.mkForce [ ];
    services.caddy.enable = lib.mkForce false;
    virtualisation.podman.enable = true;
    virtualisation.oci-containers.backend = "podman";
    virtualisation.oci-containers.containers.test-consumer = {
      image = "graft-systemd-consumer:test";
      imageFile = consumerImage;
      autoStart = false;
      pull = "never";
      networks = [ "none" ];
      volumes = [
        "/run/credentials/podman-test-consumer.service/test-token:/run/secrets/test-token:ro"
        "/var/lib/test-consumer:/state:rw"
      ];
    };
    systemd.services.podman-test-consumer.serviceConfig.StateDirectory = "test-consumer";
    services.openBaoClient = {
      enable = true;
      acme.identityDnsName = "agent-test.example.test";
      openBao = {
        enable = true;
        address = "https://openbao.example.test";
        serverCaFile = "/run/openbao-ca.pem";
        certAuthMount = "auth/cert";
        certAuthRole = "agent-test";
        secrets."test.TOKEN" = {
          path = "kv/data/test";
          field = "token";
        };
        secretRenderers.podman-test-consumer.test-token = "test.TOKEN";
      };
    };

    users.users.alice = {
      isNormalUser = true;
      uid = 1001;
      createHome = true;
      linger = true;
    };
    systemd.user.services.graft-run-probe = {
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "/run/current-system/sw/bin/graft --env test.TOKEN run -- ${userRunProbe}";
      };
    };
    system.stateVersion = "25.11";
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("user@1001.service")
    user_systemctl = (
        "runuser -u alice -- env XDG_RUNTIME_DIR=/run/user/1001 "
        "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1001/bus systemctl --user "
    )
    machine.succeed(user_systemctl + "start graft-run-probe.service")
    machine.succeed("test -f /run/user/1001/graft-user-run-probe.ok")
    machine.succeed("test -f /run/user/1001/graft-fake-token-revoke.ok")
    machine.succeed("systemctl start podman-test-consumer.service")
    machine.wait_until_succeeds("test -f /var/lib/test-consumer/start-count", timeout=30)
    machine.succeed("test $(wc -l < /run/graft-render-count) -eq 1")
    machine.succeed("test $(wc -l < /var/lib/test-consumer/start-count) -eq 1")
    machine.succeed("runuser -u nobody -- test ! -r /run/graft-podman-test-consumer/test-token")
    machine.succeed("runuser -u alice -- test ! -r /run/credentials/podman-test-consumer.service/test-token")

    machine.succeed("systemctl restart podman-test-consumer.service")
    machine.wait_until_succeeds("test $(wc -l < /run/graft-render-count) -eq 2", timeout=20)
    machine.wait_until_succeeds("test $(wc -l < /var/lib/test-consumer/start-count) -eq 2", timeout=20)

    machine.succeed("systemctl stop podman-test-consumer.service")
    machine.succeed("touch /run/fail-graft-render")
    machine.fail("systemctl start podman-test-consumer.service")
    machine.succeed("test $(wc -l < /var/lib/test-consumer/start-count) -eq 2")
  '';
}
