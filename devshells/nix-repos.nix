# devshells/nix-repos.nix
# Base shell - local flake adds scripts/commands
{
  mkProjectShell,
  ...
}:
mkProjectShell {
  name = "nix-repos";
  motd = ""; # Local flake provides MOTD
}
