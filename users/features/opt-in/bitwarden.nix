# users/features/opt-in/bitwarden.nix
#
# Bitwarden password manager with autostart
# For non-NixOS: also enable nixgl feature for GPU acceleration
#
{
  pkgs,
  lib,
  config,
  ...
}:
{
  # Tell nixgl to wrap bitwarden if nixgl is enabled
  nixgl.wrapBitwarden = lib.mkIf (config.nixgl.enable or false) true;

  # Only install bitwarden directly if nixgl is not providing it
  home.packages = lib.optionals (!(config.nixgl.enable or false)) [ pkgs.bitwarden-desktop ];

  # Autostart on login
  xdg.configFile."autostart/bitwarden.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Bitwarden
    Comment=Bitwarden password manager
    Exec=bitwarden-desktop
    Icon=bitwarden
    Terminal=false
    StartupNotify=false
  '';
}
