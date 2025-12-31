# users/features/opt-in/tailscale.nix
#
# Tailscale systray autostart
# Note: tailscaled service should be enabled at system level
#
{ pkgs, ... }:
{
  home.packages = [ pkgs.tailscale ];

  # Autostart systray on login
  xdg.configFile."autostart/tailscale.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Tailscale
    Exec=tailscale-systray
    Icon=tailscale
    Terminal=false
    StartupNotify=false
  '';
}
