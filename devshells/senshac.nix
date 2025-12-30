# devshells/senshac.nix
# Base shell - local flake adds project-specific packages/commands
{
  mkProjectShell,
  ...
}:
mkProjectShell {
  name = "senshac";
  motd = ""; # Local flake provides MOTD
}
