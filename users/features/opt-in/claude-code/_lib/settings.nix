# users/features/opt-in/claude-code/settings.nix
#
# settings.json - permissions and hooks configuration
#
{ config }:
{
  settings = {
    permissions = {
      allow = [
        "mcp__Thinking__*"
        "mcp__Nixos__*"
        "mcp__Memory__*"
      ];
    };
    hooks = {
      PreToolUse = [
        {
          matcher = "Edit|Write";
          hooks = [
            {
              type = "command";
              command = "${config.home.homeDirectory}/.claude/hooks/pre-implement.fish";
              timeout = 15;
            }
          ];
        }
      ];
      PostToolUse = [
        {
          matcher = "Edit|Write";
          hooks = [
            {
              type = "command";
              command = "${config.home.homeDirectory}/.claude/hooks/post-task.fish";
              timeout = 10;
            }
          ];
        }
      ];
      Stop = [
        {
          matcher = "";
          hooks = [
            {
              type = "command";
              command = "${config.home.homeDirectory}/.claude/hooks/stop.fish";
              timeout = 10;
            }
          ];
        }
      ];
    };
  };
}
