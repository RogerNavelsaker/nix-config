# users/features/default/shell.nix
#
# Fish shell configuration with modern CLI tool aliases
#
{ pkgs, ... }:
{
  programs = {
    fish = {
      enable = true;

      shellAliases = {
        # Modern CLI replacements
        ls = "eza";
        ll = "eza -l";
        la = "eza -la";
        lt = "eza --tree";
        cat = "bat";
        grep = "rg";
        find = "fd";
        sed = "sd";

        # Git shortcuts
        g = "git";
        gs = "git status";
        gd = "git diff";
        ga = "git add";
        gc = "git commit";
        gp = "git push";
        gl = "git log --oneline -20";
        gco = "git checkout";
        gb = "git branch";

        # Nix shortcuts
        nrs = "sudo nixos-rebuild switch --flake .";
        nrt = "sudo nixos-rebuild test --flake .";
        nfc = "nix flake check";
        nfu = "nix flake update";
        nfs = "nix flake show";

        # Directory navigation
        ".." = "cd ..";
        "..." = "cd ../..";
        "...." = "cd ../../..";
      };

      shellAbbrs = {
        # Abbreviations expand to full command when typed
        hms = "home-manager switch --flake .";
      };

      functions = {
        # Fish function to reload configuration
        fish_reload = ''
          source ~/.config/fish/config.fish
          echo "Fish configuration reloaded"
        '';

        # Quick directory creation and cd
        mkcd = ''
          mkdir -p $argv[1] && cd $argv[1]
        '';

        # Git commit with message
        gcm = ''
          git commit -m "$argv"
        '';

        # Search and replace in files
        replace = ''
          sd $argv[1] $argv[2] (rg -l $argv[1])
        '';
      };

      interactiveShellInit = ''
        # Disable greeting
        set -g fish_greeting

        # Set cursor style
        set -g fish_cursor_default block
        set -g fish_cursor_insert line
        set -g fish_cursor_replace_one underscore
        set -g fish_cursor_visual block

        # Keybindings for vi mode
        fish_vi_key_bindings
      '';

      plugins = [
        # Fish plugins managed via Home Manager
        {
          name = "fzf-fish";
          inherit (pkgs.fishPlugins.fzf-fish) src;
        }
        {
          name = "done";
          inherit (pkgs.fishPlugins.done) src;
        }
      ];
    };

    # Zoxide - smart cd replacement
    zoxide = {
      enable = true;
      enableFishIntegration = true;
    };

    # Starship prompt
    starship = {
      enable = true;
      enableFishIntegration = true;
    };
  };

  # Shell packages
  home.packages = with pkgs; [
    # Modern CLI tools (used by aliases above)
    eza # ls replacement
    bat # cat replacement
    fd # find replacement
    ripgrep # grep replacement
    sd # sed replacement
    fzf # fuzzy finder
    jq # JSON processor
    yq # YAML processor
    nushell # Alternative shell; Fish remains configured
  ];
}
