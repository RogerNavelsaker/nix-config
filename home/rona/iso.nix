# home/rona/iso.nix
{
  pkgs,
  ...
}:
{
  # Basic packages for installation environment
  home.packages = with pkgs; [
    eza
    bat
    sd
    ripgrep
    fd
    zoxide
  ];

  programs = {
    # Minimal shell setup for ISO installer
    fish = {
      enable = true;
      interactiveShellInit = ''
        # Disable the default greeting
        function fish_greeting; end

        # Ensure starship is initialized
        #if type -q starship
        #  starship init fish | source
        #end
      '';
      shellAliases = {
        ls = "eza";
        ll = "eza -l";
        la = "eza -la";
        cat = "bat";
        find = "fd";
        grep = "rg";
      };
    };

    # Helix for editing configuration files during installation
    helix = {
      enable = true;
      settings = {
        theme = "base16_transparent";
        editor = {
          line-number = "relative";
          cursorline = true;
          auto-save = true;
          idle-timeout = 0;
          completion-trigger-len = 1;
        };
        keys.normal = {
          space.w = ":w";
          space.q = ":q";
        };
      };
    };

    # Zellij terminal multiplexer
    zellij = {
      enable = true;
      settings = {
        theme = "default";
        on_force_close = "quit";
        simplified_ui = true;
        pane_frames = false;
        default_shell = "fish";
      };
    };

    # Starship prompt
    starship = {
      enable = true;
      enableFishIntegration = true;
    };
  };
}
