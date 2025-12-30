# devshells/nix-keys.nix
# Base shell - local flake adds project-specific packages/commands
{
  mkProjectShell,
  ...
}:
mkProjectShell {
  name = "nix-keys";
  motd = ""; # Local flake provides MOTD
}
