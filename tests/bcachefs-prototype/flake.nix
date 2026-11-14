{
  description = "Disposable Bcachefs storage prototype (plan Gate 2)";

  inputs.multiverse.url = "github:fzakaria/nixpkgs-multiverse/0e0b03cad7c24221d3e59b886bc74d1af5f71d3c";

  outputs = { multiverse, ... }:
    let
      system = "x86_64-linux";
      nixpkgsFlake = multiverse.multiverse.${system}.flakeAt "d4f25a3e562008648d45bcf2d70bcc7422cad84e";
      pkgs = import nixpkgsFlake.outPath { inherit system; };
    in
    {
      checks.${system} = {
        bcachefs-storage = import ./storage.nix { inherit pkgs; };
        bcachefs-root-boot = import ./root-boot.nix { inherit pkgs; };
        bcachefs-usb-boot = import ./usb-boot.nix { inherit pkgs; };
      };
    };
}
