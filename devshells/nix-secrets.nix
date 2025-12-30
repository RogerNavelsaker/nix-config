# devshells/nix-secrets.nix
# Base shell - local flake adds project-specific packages/commands
{
  mkProjectShell,
  ...
}:
mkProjectShell {
  name = "nix-secrets";
  motd = ""; # Local flake provides MOTD
}
