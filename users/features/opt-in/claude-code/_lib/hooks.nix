# users/features/opt-in/claude-code/_lib/hooks.nix
{
  "pre-implement.fish" = builtins.readFile ./hooks/pre-implement.fish;
  "post-task.fish" = builtins.readFile ./hooks/post-task.fish;
  "stop.fish" = builtins.readFile ./hooks/stop.fish;
  "weekly-curation.fish" = builtins.readFile ./hooks/weekly-curation.fish;
}
