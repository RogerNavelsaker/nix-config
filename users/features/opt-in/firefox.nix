# users/features/opt-in/firefox.nix
#
# Firefox with declarative configuration
# Supports PKCS#11 modules for smart card/YubiKey certificate auth
#
{ pkgs, ... }:
{
  programs.firefox = {
    enable = true;

    # PKCS#11 modules for smart card/YubiKey support
    pkcs11Modules = [ pkgs.opensc ];

    # Enterprise policies
    policies = {
      # Disable telemetry
      DisableTelemetry = true;
      DisableFirefoxStudies = true;

      # Disable annoying features
      DisablePocket = true;
      OfferToSaveLogins = false;

      # Security
      EnableTrackingProtection = {
        Value = true;
        Locked = true;
        Cryptomining = true;
        Fingerprinting = true;
      };

      # Allow extensions
      ExtensionSettings = {
        # Block all by default except explicitly allowed
        "*" = {
          blocked_install_message = "Extensions must be installed via Nix";
          installation_mode = "blocked";
        };
      };

      # Hardware acceleration
      HardwareAcceleration = true;

      # DNS over HTTPS
      DNSOverHTTPS = {
        Enabled = true;
        Locked = false;
      };

      # Search settings
      SearchBar = "unified";
    };

    # Default profile
    profiles.default = {
      id = 0;
      isDefault = true;

      # Extensions (from NUR or nixpkgs)
      extensions.packages = [
        # Add extensions here when firefox-addons is available
        # ublock-origin
        # bitwarden
      ];

      # Search engines
      search = {
        force = true;
        default = "ddg";
        order = [
          "ddg"
          "google"
          "Nix Packages"
        ];
        engines = {
          "Nix Packages" = {
            urls = [
              {
                template = "https://search.nixos.org/packages";
                params = [
                  {
                    name = "type";
                    value = "packages";
                  }
                  {
                    name = "channel";
                    value = "unstable";
                  }
                  {
                    name = "query";
                    value = "{searchTerms}";
                  }
                ];
              }
            ];
            icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
            definedAliases = [ "@np" ];
          };
          "NixOS Options" = {
            urls = [
              {
                template = "https://search.nixos.org/options";
                params = [
                  {
                    name = "channel";
                    value = "unstable";
                  }
                  {
                    name = "query";
                    value = "{searchTerms}";
                  }
                ];
              }
            ];
            icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
            definedAliases = [ "@no" ];
          };
          "Home Manager" = {
            urls = [
              {
                template = "https://home-manager-options.extranix.com";
                params = [
                  {
                    name = "query";
                    value = "{searchTerms}";
                  }
                  {
                    name = "release";
                    value = "master";
                  }
                ];
              }
            ];
            icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
            definedAliases = [ "@hm" ];
          };
          # Disable built-in engines (use id, not display name)
          bing.metaData.hidden = true;
          amazondotcom-us.metaData.hidden = true;
          ebay.metaData.hidden = true;
          wikipedia.metaData.alias = "@wiki";
        };
      };

      # User preferences (about:config)
      settings = {
        # Privacy
        "privacy.trackingprotection.enabled" = true;
        "privacy.trackingprotection.socialtracking.enabled" = true;
        "privacy.donottrackheader.enabled" = true;
        "privacy.firstparty.isolate" = true;

        # Security
        "security.ssl.require_safe_negotiation" = true;
        "security.tls.version.min" = 3;
        "dom.security.https_only_mode" = true;
        "dom.security.https_only_mode_ever_enabled" = true;

        # Disable telemetry
        "toolkit.telemetry.enabled" = false;
        "toolkit.telemetry.unified" = false;
        "toolkit.telemetry.archive.enabled" = false;
        "datareporting.healthreport.uploadEnabled" = false;
        "browser.ping-centre.telemetry" = false;

        # Disable Pocket
        "extensions.pocket.enabled" = false;

        # Disable experiments
        "app.normandy.enabled" = false;
        "app.shield.optoutstudies.enabled" = false;

        # UI preferences
        "browser.newtabpage.activity-stream.feeds.telemetry" = false;
        "browser.newtabpage.activity-stream.telemetry" = false;
        "browser.newtabpage.activity-stream.showSponsored" = false;
        "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;

        # Smart card / PKCS#11
        "security.osclientcerts.autoload" = true;

        # Performance
        "gfx.webrender.all" = true;
        "media.ffmpeg.vaapi.enabled" = true;
        "media.hardware-video-decoding.force-enabled" = true;

        # Disable autofill
        "signon.rememberSignons" = false;
        "signon.autofillForms" = false;

        # Developer tools
        "devtools.theme" = "dark";
      };

      # Custom CSS (optional)
      # userChrome = '''';
      # userContent = '''';
    };
  };
}
