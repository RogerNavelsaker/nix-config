# Enable nh (nix-community/nh) for improved NixOS and Home Manager CLI experience
# Provides: colored output, diffs before activation, better garbage collection
{ lib, ... }:
{
  programs.nh = {
    enable = lib.mkDefault true;
    clean = {
      enable = true;
      extraArgs = "--keep-since 7d --keep 3";
    };
  };
}
