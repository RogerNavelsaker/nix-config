{ pkgs, ... }:

{
  packages = with pkgs; [
    fish
    age
    git
    curl
    gnupg
    jq
    ripgrep
    sops
    go
  ];

  scripts.install-rescue-host.exec = ''exec fish "$PWD/scripts/install-rescue-host.fish" "$@"'';
}
