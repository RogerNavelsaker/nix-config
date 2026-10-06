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
  ];

  scripts.install-rescue-host.exec = ''exec fish "$PWD/scripts/install-rescue-host.fish" "$@"'';
}
