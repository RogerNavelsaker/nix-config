{
  config,
  secrets,
  ...
}:
let
  ssid = "NaCo";
  inherit (config.rescueWifi) autoConnect;
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
      Passphrase=${config.sops.placeholder."wifi-${ssid}"}

      [Settings]
      AutoConnect=${if autoConnect then "true" else "false"}
    '';
    path = "/var/lib/iwd/${ssid}.psk";
    mode = "0600";
    restartUnits = [ "iwd.service" ];
  };
}
