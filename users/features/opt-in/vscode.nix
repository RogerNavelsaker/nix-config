# users/features/opt-in/vscode.nix
#
# Visual Studio Code with declarative configuration
# Extensions managed via nixpkgs where available, mutable for marketplace-only
#
{ pkgs, ... }:
{
  programs.vscode = {
    enable = true;
    package = pkgs.vscode;

    # Allow manual extension installation for marketplace-only extensions
    mutableExtensionsDir = true;

    # Profile-based configuration (HM 25.05+)
    profiles.default = {
      # Extensions available in nixpkgs
      extensions = with pkgs.vscode-extensions; [
        # Nix
        jnoortheen.nix-ide
        mkhl.direnv

        # Git
        eamodio.gitlens
        github.vscode-pull-request-github
        github.vscode-github-actions

        # AI Assistants
        anthropic.claude-code
        github.copilot
        github.copilot-chat

        # Editor utilities
        alefragnani.bookmarks
        alefragnani.project-manager
        usernamehw.errorlens
        editorconfig.editorconfig

        # File formats
        redhat.vscode-yaml
        redhat.vscode-xml
      ];

      userSettings = {
        # Telemetry
        "amazonQ.telemetry" = false;
        "redhat.telemetry.enabled" = false;
        "chat.disableAIFeatures" = true;

        # Editor
        "workbench.startupEditor" = "none";
        "explorer.confirmDragAndDrop" = false;
        "terminal.integrated.stickyScroll.enabled" = false;
        "editor.autoIndentOnPaste" = true;
        "editor.bracketPairColorization.independentColorPoolPerBracketType" = true;

        # Theme
        "workbench.colorTheme" = "City Lights";
        "workbench.iconTheme" = "city-lights-icons-vsc";

        # Git
        "git.confirmSync" = false;
        "git.enableSmartCommit" = true;
        "GitHooks.hooksDirectory" = ".githooks";
        "GitHooks.logLevel" = "error";

        # GitLens
        "gitlens.ai.model" = "vscode";
        "gitlens.ai.vscode.model" = "copilot:gpt-4.1";

        # Claude Code
        "claudeCode.preferredLocation" = "sidebar";

        # Copilot - disable most features
        "github.copilot.chat.agent.currentEditorContext.enabled" = false;
        "github.copilot.chat.codeGeneration.useInstructionFiles" = false;
        "github.copilot.chat.copilotDebugCommand.enabled" = false;
        "github.copilot.chat.customInstructionsInSystemMessage" = false;
        "github.copilot.chat.edits.suggestRelatedFilesForTests" = false;
        "github.copilot.chat.edits.suggestRelatedFilesFromGitHistory" = false;
        "github.copilot.chat.imageUpload.enabled" = false;
        "github.copilot.chat.newWorkspaceCreation.enabled" = false;
        "github.copilot.chat.reviewAgent.enabled" = false;
        "github.copilot.chat.reviewSelection.enabled" = false;
        "github.copilot.chat.setupTests.enabled" = false;
        "github.copilot.chat.summarizeAgentConversationHistory.enabled" = false;
        "github.copilot.chat.useResponsesApi" = false;
        "github.copilot.chat.useProjectTemplates" = false;
        "github.copilot.editor.enableCodeActions" = false;
        "github.copilot.nextEditSuggestions.allowWhitespaceOnlyChanges" = false;
        "github.copilot.nextEditSuggestions.fixes" = false;
        "github.copilot.renameSuggestions.triggerAutomatically" = false;
        "githubPullRequests.experimental.chat" = false;
        "githubPullRequests.codingAgent.enabled" = false;

        # SOPS
        "sops.creationEnabled" = true;

        # Project Manager
        "projectManager.git.baseFolders" = [ "~/Repositories" ];

        # File associations
        "files.associations" = {
          ".env*" = "dotenv";
        };
      };
    };
  };
}
