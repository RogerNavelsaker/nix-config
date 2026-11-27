{
  description = "NixOS configuration for agent-alex";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  inputs.agentToolsNixpkgs.url = "github:NixOS/nixpkgs/331800de5053fcebacf6813adb5db9c9dca22a0c";
  inputs.herdr.url = "github:RogerNavelsaker/nixpkg-herdr?rev=cdbd9798b483255c7998adfa5b5d5b79d5c64198";
  # Keep Headroom on unstable; ast-grep-cli is absent from nixos-26.05.
  inputs.headroom.url = "github:RogerNavelsaker/nixpkg-headroom?rev=caadac5c404133b7d4b218582838ece6d8d33888";
  inputs.caveman.url = "github:RogerNavelsaker/nixpkg-caveman?rev=33dd88e76c3144aa2022aeadfbd832ac3165689c";
  inputs.caveman.inputs.nixpkgs.follows = "nixpkgs";
  inputs.piCodingAgent.url = "github:RogerNavelsaker/nixpkg-pi-coding-agent";
  inputs.piCodingAgent.inputs.nixpkgs.follows = "nixpkgs";
  inputs.devenv.url = "github:cachix/devenv/v2.4.0";
  inputs.mnemosyne.url = "github:RogerNavelsaker/nixpkg-mnemosyne?rev=9534d029ffaf7d6827b4b88a2fe890c93a16990a";
  inputs.seeds.url = "github:RogerNavelsaker/nixpkg-seeds/9bbf782b77488070e4f86f404f4b7b40af24d6a3";
  inputs.seeds.inputs.nixpkgs.follows = "agentToolsNixpkgs";
  inputs.mulch.url = "github:RogerNavelsaker/nixpkg-mulch/890deec46fbee6334ceffd022e7069ff19c69da7";
  inputs.mulch.inputs.nixpkgs.follows = "agentToolsNixpkgs";
  inputs.terrarium.url = "github:RogerNavelsaker/nixpkg-terrarium/76740f7f091c85b997bab7a11ff6ddb1c72ace0d";
  inputs.terrarium.inputs.nixpkgs.follows = "agentToolsNixpkgs";
  inputs.openBaoClient = {
    url = "path:../features/opt-in/openbao-client";
    flake = false;
  };

  outputs =
    {
      nixpkgs,
      herdr,
      headroom,
      caveman,
      piCodingAgent,
      devenv,
      mnemosyne,
      seeds,
      mulch,
      terrarium,
      openBaoClient,
      ...
    }:
    let
      system = "x86_64-linux";
    in
    {
      nixosConfigurations.agent-alex = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          herdrPackage = herdr.packages.${system}.default;
          devenvPackage = devenv.packages.${system}.devenv;
          agentToolPackages = [
            headroom.packages.${system}.headroom
            caveman.packages.${system}.caveman-cli
            piCodingAgent.packages.${system}.default
            piCodingAgent.packages.${system}.default.pi
            mnemosyne.packages.${system}.mnemosyne-memory
            seeds.packages.${system}.default
            mulch.packages.${system}.default
            terrarium.packages.${system}.default
          ];
        };
        modules = [
          ./configuration.nix
          (openBaoClient + "/openbao-client.nix")
        ];
      };
    };
}
