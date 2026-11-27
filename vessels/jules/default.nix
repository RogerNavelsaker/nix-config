{ config, ... }:
{
  imports = [ ../features/default/lxc-agent.nix ];
  _module.args.agentName = builtins.head config.hostSpec.users;
}
