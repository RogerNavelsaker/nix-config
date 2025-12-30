# devshells/nix-lib.nix
# Base shell - local flake adds project-specific packages/commands
{
  mkProjectShell,
  ...
}:
mkProjectShell {
  name = "nix-lib";
  motd = ""; # Local flake provides MOTD
}
