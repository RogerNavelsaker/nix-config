# users/features/opt-in/theming.nix
#
# GTK and Qt theming for consistent appearance across Nix and system apps
# Mirrors current KDE Plasma settings
#
# On non-NixOS (detected by nixgl feature), Qt theming is disabled to avoid
# Nix KDE binaries conflicting with system Plasma installation.
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # nixgl feature indicates non-NixOS system (e.g., Arch, CachyOS)
  isNonNixOS = lib.elem "nixgl" config.userSpec.enabledFeatures;
in
{
  # GTK configuration
  gtk = {
    enable = true;

    # Theme
    theme = {
      name = "Breeze";
      package = pkgs.kdePackages.breeze-gtk;
    };

    # Icons
    iconTheme = {
      name = "breeze-dark";
      package = pkgs.kdePackages.breeze-icons;
    };

    # Cursor
    cursorTheme = {
      name = "capitaine-cursors";
      package = pkgs.capitaine-cursors;
      size = 24;
    };

    # Font
    font = {
      name = "Noto Sans";
      size = 10;
      package = pkgs.noto-fonts;
    };

    # GTK3 settings
    gtk3.extraConfig = {
      gtk-application-prefer-dark-theme = true;
      gtk-button-images = true;
      gtk-cursor-blink = true;
      gtk-cursor-blink-time = 1000;
      gtk-decoration-layout = "icon:minimize,maximize,close";
      gtk-enable-animations = true;
      gtk-menu-images = true;
      gtk-primary-button-warps-slider = true;
      gtk-sound-theme-name = "ocean";
      gtk-toolbar-style = 3;
      gtk-xft-dpi = 98304;
    };

    # GTK4 settings
    gtk4.extraConfig = {
      gtk-application-prefer-dark-theme = true;
      gtk-cursor-blink = true;
      gtk-cursor-blink-time = 1000;
      gtk-decoration-layout = "icon:minimize,maximize,close";
      gtk-enable-animations = true;
      gtk-primary-button-warps-slider = true;
      gtk-sound-theme-name = "ocean";
      gtk-xft-dpi = 98304;
    };
  };

  # Qt configuration
  # On NixOS: use kde platformTheme for proper integration
  # On non-NixOS: disable to avoid Nix KDE binaries conflicting with system Plasma
  qt = lib.mkIf (!isNonNixOS) {
    enable = true;
    platformTheme.name = "kde";
    style = {
      name = "breeze";
      package = pkgs.kdePackages.breeze;
    };
  };

  # Ensure cursor theme is available system-wide
  home.pointerCursor = {
    name = "capitaine-cursors";
    package = pkgs.capitaine-cursors;
    size = 24;
    gtk.enable = true;
    x11.enable = true;
  };
}
