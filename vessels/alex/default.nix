{ ... }:
{
  imports = [
    ../../hosts/alex/configuration.nix
    ../features/default/agent-toolchain.nix
  ];

  users.groups.alex = { };
  users.users.alex.group = "alex";
}
