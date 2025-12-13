# home/rona/nanoserver.nix
{
  pkgs,
  ...
}:
{
  # Basic CLI tools
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
    vim
    neovim

    # System utilities
    htop
    curl
    wget
  ];

  programs = {
    # Shell configuration
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
      userName = "rona";
      userEmail = "rona@example.com";
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
