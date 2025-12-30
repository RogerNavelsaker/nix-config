# devshells/modern-cli-mcp.nix
# Base shell - local flake adds project-specific packages/commands
{
  mkProjectShell,
  ...
}:
mkProjectShell {
  name = "modern-cli-mcp";
  motd = ""; # Local flake provides MOTD
}
