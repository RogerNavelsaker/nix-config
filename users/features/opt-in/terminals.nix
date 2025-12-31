# users/features/opt-in/terminals.nix
#
# Terminal emulators: Alacritty, Kitty, Zellij
#
_: {
  programs = {
    # Alacritty - GPU-accelerated terminal
    alacritty = {
      enable = true;
      settings = {
        env = {
          TERM = "xterm-256color";
          WINIT_X11_SCALE_FACTOR = "1";
        };

        window = {
          dynamic_padding = true;
          decorations = "full";
          title = "Alacritty";
          opacity = 0.8;
          decorations_theme_variant = "Dark";
          dimensions = {
            columns = 100;
            lines = 30;
          };
          class = {
            instance = "Alacritty";
            general = "Alacritty";
          };
        };

        scrolling = {
          history = 10000;
          multiplier = 3;
        };

        # Nord theme
        colors = {
          draw_bold_text_with_bright_colors = true;
          primary = {
            background = "0x2E3440";
            foreground = "0xD8DEE9";
          };
          normal = {
            black = "0x3B4252";
            red = "0xBF616A";
            green = "0xA3BE8C";
            yellow = "0xEBCB8B";
            blue = "0x81A1C1";
            magenta = "0xB48EAD";
            cyan = "0x88C0D0";
            white = "0xE5E9F0";
          };
          bright = {
            black = "0x4C566A";
            red = "0xBF616A";
            green = "0xA3BE8C";
            yellow = "0xEBCB8B";
            blue = "0x81A1C1";
            magenta = "0xB48EAD";
            cyan = "0x8FBCBB";
            white = "0xECEFF4";
          };
        };

        font = {
          size = 12;
          normal = {
            family = "monospace";
            style = "Regular";
          };
          bold = {
            family = "monospace";
            style = "Bold";
          };
          italic = {
            family = "monospace";
            style = "Italic";
          };
          bold_italic = {
            family = "monospace";
            style = "Bold Italic";
          };
        };

        selection = {
          semantic_escape_chars = '',│`|:"' ()[]{}<>\t'';
          save_to_clipboard = true;
        };

        cursor = {
          style = "Underline";
          vi_mode_style = "None";
          unfocused_hollow = true;
          thickness = 0.15;
        };

        mouse.hide_when_typing = true;

        general = {
          live_config_reload = true;
        };

        keyboard.bindings = [
          {
            key = "V";
            mods = "Control|Shift";
            action = "Paste";
          }
          {
            key = "C";
            mods = "Control|Shift";
            action = "Copy";
          }
          {
            key = "F";
            mods = "Control|Shift";
            action = "SearchForward";
          }
          {
            key = "Key0";
            mods = "Control";
            action = "ResetFontSize";
          }
          {
            key = "PageUp";
            mods = "Shift";
            action = "ScrollPageUp";
          }
          {
            key = "PageDown";
            mods = "Shift";
            action = "ScrollPageDown";
          }
        ];
      };
    };

    # Kitty - feature-rich terminal
    kitty = {
      enable = true;
      settings = {
        # Font
        font_family = "monospace";
        font_size = 12;

        # Window
        background_opacity = "0.9";
        window_padding_width = 4;

        # Cursor
        cursor_shape = "beam";
        cursor_blink_interval = 0;

        # Scrollback
        scrollback_lines = 10000;

        # URLs
        url_style = "curly";
        open_url_with = "default";

        # Bell
        enable_audio_bell = false;
        visual_bell_duration = "0.0";

        # Tab bar
        tab_bar_style = "powerline";
        tab_powerline_style = "slanted";
      };
    };

    # Zellij - terminal multiplexer
    zellij = {
      enable = true;
      enableFishIntegration = false; # Don't auto-attach
    };
  };
}
