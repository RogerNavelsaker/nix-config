{ inputs, pkgs, ... }:
let
  agentPkgs = inputs.agentToolsNixpkgs.legacyPackages.${pkgs.system};
in
{
  packages = [
    inputs.seeds.packages.${pkgs.system}.default
    inputs.mulch.packages.${pkgs.system}.default
    inputs.terrarium.packages.${pkgs.system}.default
    pkgs.openbao
    pkgs.step-cli
    agentPkgs.git
    agentPkgs.worktrunk
  ];

  scripts.sd.exec = "exec seeds \"$@\"";
  scripts.ml.exec = "exec mulch \"$@\"";
  scripts.tr.exec = "exec terrarium \"$@\"";
  # Worktrunk supplies the wt command; Git's own worktree command remains git worktree.
}
