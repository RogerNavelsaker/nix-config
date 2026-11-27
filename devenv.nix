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

}
