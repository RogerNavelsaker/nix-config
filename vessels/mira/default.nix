{ config, ... }:
{
  imports = [ ../features/default/lxc-agent.nix ];
  _module.args.agentName = config.hostSpec.hostname;
}
