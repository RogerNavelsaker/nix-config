# users/features/default/dev-tools.nix
#
# Essential development tools (non-language-specific)
# Language-specific tools come from devshells
#
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    # File operations
    tree
    duf # disk usage
    ncdu # disk usage analyzer
    file

    # Process management
    htop
    btop

    # Network utilities
    curl
    wget
    httpie

    # Text processing
    gawk
    gnused
    gnugrep

    # Compression
    unzip
    zip
    gzip
    p7zip

    # Misc utilities
    watch
    entr # run commands on file changes
    just # command runner
    tokei # code statistics
    hyperfine # benchmarking

    # Container tools
    lazydocker # Docker TUI

    # Remote access
    mosh # Mobile shell

    # Diff tools
    meld # Visual diff
  ];
}
