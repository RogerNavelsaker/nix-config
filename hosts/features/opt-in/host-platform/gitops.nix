{
  config,
  lib,
  pkgs,
  ...
}:
let
  bootstrap = config.networking.hostName == "miniserver-01";
  fluxInstallManifest =
    pkgs.runCommand "flux-install.yaml"
      {
        nativeBuildInputs = [ pkgs.fluxcd ];
      }
      ''
        flux install \
          --export \
          --components=source-controller,kustomize-controller,helm-controller,notification-controller \
          > "$out"
      '';
in
{
  services.k3s.manifests = lib.mkIf bootstrap {
    "00-flux-install".source = fluxInstallManifest;
    "10-flux-source".content = [
      {
        apiVersion = "source.toolkit.fluxcd.io/v1";
        kind = "GitRepository";
        metadata = {
          name = "nix-config";
          namespace = "flux-system";
        };
        spec = {
          interval = "5m";
          ref.branch = "main";
          url = "https://github.com/RogerNavelsaker/nix-config.git";
        };
      }
      {
        apiVersion = "kustomize.toolkit.fluxcd.io/v1";
        kind = "Kustomization";
        metadata = {
          name = "cluster-baseline";
          namespace = "flux-system";
        };
        spec = {
          interval = "10m";
          path = "./clusters/nanoserver-miniservers";
          prune = true;
          sourceRef = {
            kind = "GitRepository";
            name = "nix-config";
          };
        };
      }
    ];
  };
}
