{ inputs, ... }:
{
  imports = [
    inputs.nixos-wsl.nixosModules.default
    ./configuration.nix
    ../features/default/agent-toolchain.nix
  ];
}
