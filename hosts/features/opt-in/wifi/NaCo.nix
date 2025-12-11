{
  config,
  secrets,
  ...
}:
let
  ssid = "NaCo";
in
{
  imports = [ ./common.nix ];

  # Define SOPS secret for WiFi PSK
  sops.secrets."wifi-${ssid}" = {
    sopsFile = secrets + "/hosts/common/secrets.yaml";
    key = "wifi/${ssid}";
  };

  # Use SOPS templates to create properly formatted PSK file
  sops.templates."${ssid}.psk" = {
    content = ''
      [Security]
      PreSharedKey=${config.sops.placeholder."wifi-${ssid}"}
    '';
    path = "/var/lib/iwd/${ssid}.psk";
    mode = "0600";
    restartUnits = [ "iwd.service" ];
  };
}
