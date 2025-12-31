# users/features/opt-in/bitwarden.nix
#
# Bitwarden password manager with autostart
#
{ pkgs, ... }:
{
  home.packages = [ pkgs.bitwarden-desktop ];

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
