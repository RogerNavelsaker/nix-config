{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.openBaoClient;
  hostName = config.networking.hostName;
  agentName = lib.removePrefix "agent-" hostName;
  certName = "openbao-client-${agentName}";
  certGroup = "${certName}-certs";
  certDirectory = "/var/lib/acme/${certName}";
  challengeWebroot = "/var/lib/acme-challenges/${certName}";
  tailscaleInterface = config.services.tailscale.interfaceName;
  secretEnvSelectors = builtins.attrNames cfg.openBao.secrets;
  isHttpsUrl =
    value:
    value != null
    && lib.hasPrefix "https://" value
    && !(lib.hasInfix "\n" value)
    && !(lib.hasInfix " " value)
    && !(lib.hasInfix "\"" value);
  isAbsoluteSafePath =
    value:
    value != null
    && builtins.match "^/[A-Za-z0-9._/-]+$" value != null
    && !(lib.hasInfix "/../" value)
    && !(lib.hasSuffix "/.." value);
  isAgentHost = builtins.match "^agent-[a-z0-9][a-z0-9-]*$" hostName != null;
  isSafeSecretPath =
    value:
    value != ""
    && value != "."
    && value != ".."
    && builtins.match "^[A-Za-z0-9._/-]+$" value != null
    && !(lib.hasPrefix "/" value)
    && !(lib.hasPrefix "../" value)
    && !(lib.hasInfix "/../" value)
    && !(lib.hasSuffix "/.." value)
    && !(lib.hasInfix "/./" value)
    && !(lib.hasSuffix "/." value)
    && !(lib.hasSuffix "/" value)
    && !(lib.hasInfix "//" value);
  isSafeField = value: builtins.match "^[A-Za-z_][A-Za-z0-9_]*$" value != null;
  isSafeEnvName = value: builtins.match "^[A-Za-z_][A-Za-z0-9_]*$" value != null;
  isSafeEnvSelector =
    value:
    let
      parts = lib.splitString "." value;
    in
    if builtins.length parts == 1 then
      isSafeEnvName value
    else
      builtins.length parts == 2
      && builtins.match "^[A-Za-z0-9_-]+$" (builtins.elemAt parts 0) != null
      && isSafeEnvName (builtins.elemAt parts 1);
  profiledEnvNames = map (name: builtins.elemAt (lib.splitString "." name) 1) (
    lib.filter (name: lib.hasInfix "." name) secretEnvSelectors
  );
  profilelessEnvNames = lib.filter (name: !(lib.hasInfix "." name)) secretEnvSelectors;
  serverCa = builtins.toJSON cfg.openBao.serverCaFile;
  clientCert = builtins.toJSON "${certDirectory}/fullchain.pem";
  clientKey = builtins.toJSON "${certDirectory}/key.pem";
  secretMappingsValid =
    lib.all (
      name:
      let
        secret = cfg.openBao.secrets.${name};
      in
      isSafeEnvSelector name && isSafeSecretPath secret.path && isSafeField secret.field
    ) secretEnvSelectors
    && lib.all (name: !(builtins.elem name profiledEnvNames)) profilelessEnvNames;
  secretMappingsJSON = builtins.toJSON cfg.openBao.secrets;
  secretMappingsFile = pkgs.writeText "${certName}-graft-secret-mappings.json" secretMappingsJSON;
  secretRendererServices = builtins.attrNames cfg.openBao.secretRenderers;
  secretRenderersValid =
    lib.all (
      service:
      builtins.match "^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$" service != null
      && (
        let
          files = cfg.openBao.secretRenderers.${service};
          selectedNames = map (
            selector:
            let
              parts = lib.splitString "." selector;
            in
            if builtins.length parts == 1 then builtins.head parts else builtins.elemAt parts 1
          ) (builtins.attrValues files);
        in
        builtins.attrNames files != [ ]
        && builtins.length selectedNames == builtins.length (lib.unique selectedNames)
        && lib.all (
          credential:
          builtins.match "^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$" credential != null
          && isSafeEnvSelector files.${credential}
          && builtins.hasAttr files.${credential} cfg.openBao.secrets
        ) (builtins.attrNames files)
      )
    ) secretRendererServices
    && lib.all (
      service: !(builtins.elem "graft-render-${service}" secretRendererServices)
    ) secretRendererServices;
  baseConfig = ''
    vault {
      address = ${builtins.toJSON cfg.openBao.address}
      ca_cert = ${serverCa}
      client_cert = ${clientCert}
      client_key = ${clientKey}
    }

    auto_auth {
      method {
        type = "cert"
        mount_path = ${builtins.toJSON cfg.openBao.certAuthMount}
        min_backoff = "1s"
        max_backoff = "8s"
        config = {
          name = ${builtins.toJSON cfg.openBao.certAuthRole}
          ca_cert = ${serverCa}
          client_cert = ${clientCert}
          client_key = ${clientKey}
          reload = true
        }
      }
      # Graft replaces this with a private per-invocation token sink.
      # GRAFT_TOKEN_SINK
    }
  '';
  acmeEnvironmentFile = pkgs.writeText "${certName}-acme-environment" "SSL_CERT_FILE=${cfg.acme.caBundleFile}\n";
  launcher = pkgs.buildGoModule {
    pname = "graft";
    version = "0.1.0";
    src = ./openbao-secrets;
    vendorHash = null;
    ldflags = [
      "-s"
      "-w"
      "-X"
      "main.configPath=/etc/openbao-agent/${certName}.hcl"
      "-X"
      "main.baoPath=${pkgs.openbao}/bin/bao"
      "-X"
      "main.secretMappingsPath=/etc/openbao-agent/${certName}-secret-mappings.json"
      "-X"
      "main.touchPath=${pkgs.coreutils}/bin/touch"
      "-X"
      "main.baoAddress=${cfg.openBao.address}"
      "-X"
      "main.serverCaPath=${cfg.openBao.serverCaFile}"
      "-X"
      "main.clientCertPath=${certDirectory}/fullchain.pem"
      "-X"
      "main.clientKeyPath=${certDirectory}/key.pem"
    ];
  };
  rendererSystemdServices =
    let
      mkRenderer =
        service: files:
        let
          args = lib.concatStringsSep " " (
            lib.mapAttrsToList (
              credential: selector: "--file " + lib.escapeShellArg "${credential}=${selector}"
            ) files
          );
          renderScript = pkgs.writeShellScript "graft-render-${service}" ''
            exec ${launcher}/bin/graft render --service ${lib.escapeShellArg service} ${args}
          '';
        in
        {
          description = "Render OpenBao credentials for ${service}";
          partOf = [ "${service}.service" ];
          serviceConfig = {
            Type = "oneshot";
            User = "root";
            UMask = "0077";
            RemainAfterExit = true;
            RuntimeDirectory = "graft-${service}";
            RuntimeDirectoryMode = "0700";
            ExecStart = renderScript;
          };
        };
      renderers = lib.mapAttrs' (
        service: files: lib.nameValuePair "graft-render-${service}" (mkRenderer service files)
      ) cfg.openBao.secretRenderers;
      consumers = lib.mapAttrs' (
        service: files:
        lib.nameValuePair service {
          requires = [ "graft-render-${service}.service" ];
          after = [ "graft-render-${service}.service" ];
          serviceConfig.LoadCredential = lib.mapAttrsToList (
            credential: _: "${credential}:%t/graft-${service}/${credential}"
          ) files;
        }
      ) cfg.openBao.secretRenderers;
    in
    renderers // consumers;
in
{
  options.services.openBaoClient = {
    enable = lib.mkEnableOption "per-agent Smallstep ACME client identity issuance";

    acme = {
      directoryUrl = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "https://step-ca.naco.casa/acme/agent-clients/directory";
        description = "Smallstep ACME directory URL for this client's certificate.";
      };
      identityDnsName = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Exact DNS identity requested from ACME for this host.";
      };
      caBundleFile = lib.mkOption {
        type = lib.types.str;
        default = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
        description = "CA bundle that verifies the HTTPS Step ACME directory.";
      };
    };

    openBao = {
      enable = lib.mkEnableOption "OpenBao Agent-backed command secret injection";
      address = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Direct HTTPS endpoint where OpenBao terminates TLS.";
      };
      serverCaFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Runtime CA file that verifies OpenBao's server TLS certificate.";
      };
      certAuthMount = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Full OpenBao cert-auth mount path, such as auth/cert.";
      };
      certAuthRole = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "This client's exact OpenBao cert-auth role.";
      };
      secrets = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              path = lib.mkOption {
                type = lib.types.str;
                description = "OpenBao KV v2 API path, e.g. kv/data/agent-alex/app/dev.";
              };
              field = lib.mkOption {
                type = lib.types.str;
                description = "String field to expose as this environment variable; use a Go-template identifier.";
              };
            };
          }
        );
        default = { };
        description = "Map PROFILE.VARIABLE selectors (or unprofiled VARIABLE names) to an OpenBao KV v2 API path and field.";
      };
      secretRenderers = lib.mkOption {
        type = lib.types.attrsOf (lib.types.attrsOf lib.types.str);
        default = { };
        description = "Map systemd service names to credential-name/secret-selector pairs rendered before each service start.";
      };
    };
  };

  config = {
    assertions = [
      {
        assertion = !cfg.openBao.enable || cfg.enable;
        message = "openBaoClient.openBao.enable requires services.openBaoClient.enable.";
      }
      {
        assertion = cfg.openBao.enable || secretRendererServices == [ ];
        message = "openBaoClient.openBao.secretRenderers requires services.openBaoClient.openBao.enable.";
      }
      {
        assertion = !cfg.openBao.enable || secretRenderersValid;
        message = "openBaoClient.openBao.secretRenderers must use safe systemd/credential names and configured secret selectors, with no generated-unit name collisions.";
      }
    ]
    ++ lib.optionals cfg.enable [
      {
        assertion = isAgentHost;
        message = "openBaoClient requires a host name of the form agent-<name>.";
      }
      {
        assertion = isHttpsUrl cfg.acme.directoryUrl;
        message = "openBaoClient.acme.directoryUrl must be an HTTPS ACME directory URL.";
      }
      {
        assertion =
          cfg.acme.identityDnsName != null
          &&
            builtins.match "^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$" cfg.acme.identityDnsName
            != null;
        message = "openBaoClient.acme.identityDnsName must be an exact multi-label DNS name.";
      }
      {
        assertion = isAbsoluteSafePath cfg.acme.caBundleFile;
        message = "openBaoClient.acme.caBundleFile must be an absolute runtime PEM bundle path.";
      }
      {
        assertion =
          config.services.tailscale.enable
          && config.networking.firewall.enable
          && !(lib.elem 80 config.networking.firewall.allowedTCPPorts)
          && lib.all (
            interface:
            interface == tailscaleInterface
            || !(lib.elem 80 (config.networking.firewall.interfaces.${interface}.allowedTCPPorts or [ ]))
          ) (builtins.attrNames config.networking.firewall.interfaces);
        message = "HTTP-01 requires an enabled firewall and must not open TCP 80 globally or on non-Tailscale interfaces.";
      }
    ]
    ++ lib.optionals (cfg.enable && cfg.openBao.enable) [
      {
        assertion = isHttpsUrl cfg.openBao.address;
        message = "openBaoClient.openBao.address must be the direct HTTPS OpenBao endpoint.";
      }
      {
        assertion = isAbsoluteSafePath cfg.openBao.serverCaFile;
        message = "openBaoClient.openBao.serverCaFile must be an absolute runtime PEM path.";
      }
      {
        assertion =
          cfg.openBao.certAuthMount != null
          && builtins.match "^auth/[A-Za-z0-9_-]+(/[A-Za-z0-9_-]+)*$" cfg.openBao.certAuthMount != null;
        message = "openBaoClient.openBao.certAuthMount must be a full auth/<mount> path.";
      }
      {
        assertion =
          cfg.openBao.certAuthRole != null
          && builtins.match "^[A-Za-z0-9._-]+$" cfg.openBao.certAuthRole != null;
        message = "openBaoClient.openBao.certAuthRole must be a non-empty role name.";
      }
      {
        assertion = secretMappingsValid;
        message = "openBaoClient.openBao.secrets must map valid selectors to safe KV API paths and fields; profiled variables cannot also have an unprofiled mapping.";
      }
    ];

    users.groups = lib.mkIf cfg.enable {
      "${certGroup}" = {
        members = [ agentName ];
      };
    };

    security.acme.acceptTerms = lib.mkIf cfg.enable true;
    security.acme.certs = lib.mkIf cfg.enable {
      "${certName}" = {
        # Smallstep has no ACME contact-email workflow; NixOS requires a value.
        email = "noemail@example.com";
        domain = cfg.acme.identityDnsName;
        extraDomainNames = [ ];
        server = cfg.acme.directoryUrl;
        webroot = challengeWebroot;
        keyType = "ec256";
        group = certGroup;
        extraLegoRenewFlags = [ "--reuse-key" ];
        environmentFile = acmeEnvironmentFile;
      };
    };

    services.caddy = lib.mkIf cfg.enable {
      enable = true;
      virtualHosts."http://${cfg.acme.identityDnsName}".extraConfig = ''
        handle /.well-known/acme-challenge/* {
          root * ${challengeWebroot}
          file_server
        }
        respond 404
      '';
    };

    networking.firewall.interfaces = lib.mkIf cfg.enable {
      "${tailscaleInterface}".allowedTCPPorts = [ 80 ];
    };

    systemd.services = lib.mkIf (cfg.enable && cfg.openBao.enable) rendererSystemdServices;

    environment.etc = lib.mkIf (cfg.enable && cfg.openBao.enable) {
      "openbao-agent/${certName}.hcl".text = baseConfig;
      "openbao-agent/${certName}-secret-mappings.json".source = secretMappingsFile;
    };
    environment.systemPackages =
      lib.optionals cfg.enable [
        pkgs.lego
        pkgs.openbao
        pkgs.step-cli
      ]
      ++ lib.optionals (cfg.enable && cfg.openBao.enable) [
        launcher
      ];
  };
}
