# users/features/opt-in/claude-code/_lib/agents.nix
{
  generator = builtins.readFile ./agents/generator.md;
  reflector = builtins.readFile ./agents/reflector.md;
  curator = builtins.readFile ./agents/curator.md;
  explore = builtins.readFile ./agents/explore.md;
  architect = builtins.readFile ./agents/architect.md;
  implement = builtins.readFile ./agents/implement.md;
  review = builtins.readFile ./agents/review.md;
  test = builtins.readFile ./agents/test.md;
}
