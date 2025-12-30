# users/rona/aio/default.nix
#
# Home Manager configuration for rona on Arch Linux (aio)
# Primary interface: goose-cli, Backend: claude-code
#
{ pkgs, ... }:
{
  imports = [
    ./claude-code.nix
    ./goose.nix
  ];

  # CLI tools managed by Nix
  home.packages = with pkgs; [
    # File management
    eza
    bat
    fd
    ripgrep
    sd
    zoxide

    # Development
    git
    neovim

    # System utilities
    htop
    curl
    wget
  ];

  programs = {
    # Fish shell
    fish = {
      enable = true;
      shellAliases = {
        ls = "eza";
        ll = "eza -l";
        la = "eza -la";
        cat = "bat";
        grep = "rg";
      };
    };

    # Git configuration
    git = {
      enable = true;
      settings.user.name = "rona";
      # settings.user.email = "rona@example.com";
    };

    # Helix editor
    helix = {
      enable = true;
      settings = {
        theme = "base16_transparent";
        editor = {
          line-number = "relative";
          cursorline = true;
          auto-save = true;
        };
      };
    };
  };
}
