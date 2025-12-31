# users/features/opt-in/beeper.nix
#
# Beeper universal chat app
#
{ pkgs, ... }:
{
  home.packages = [ pkgs.beeper ];
}
