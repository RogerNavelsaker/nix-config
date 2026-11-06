{ inputs, pkgs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  packageSets = pkgs.inputs.nixpkgs-packages;
in
{
  imports = [
    inputs.nixos-wsl.nixosModules.default
    ./configuration.nix
  ];

  _module.args = {
    devenvPackage = inputs.devenv.packages.${system}.devenv;
    herdrPackage = inputs.herdr.packages.${system}.default;
    agentToolPackages = [
      inputs.headroom.packages.${system}.headroom
      packageSets.nixpkg-caveman.caveman-cli
      packageSets.nixpkg-pi-coding-agent.default
      packageSets.nixpkg-pi-coding-agent.default.pi
      packageSets.nixpkg-mnemosyne.mnemosyne-memory
      packageSets.nixpkg-seeds.default
      packageSets.nixpkg-mulch.default
      packageSets.nixpkg-terrarium.default
    ];
  };
}
