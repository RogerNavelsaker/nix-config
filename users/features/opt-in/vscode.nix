# users/features/opt-in/vscode.nix
#
# Visual Studio Code with declarative configuration
# All extensions from nix-vscode-extensions (daily updated from marketplace)
# For non-NixOS: also enable nixgl feature for GPU acceleration
#
{ pkgs, lib, ... }:
{
  # nixd LSP for Nix language support
  home.packages = [ pkgs.nixd ];
  programs.vscode = {
    enable = true;
    # Default package; nixgl feature overrides this with mkForce
    package = lib.mkDefault pkgs.vscode;

    # Fully declarative - no mutable extensions needed with nix-vscode-extensions
    mutableExtensionsDir = false;

    # Profile-based configuration (HM 25.05+)
    profiles.default = {
      extensions = with pkgs.vscode-marketplace; [
        # Nix
        arrterian.nix-env-selector
        bbenoist.nix
        jnoortheen.nix-ide
        mkhl.direnv
        pinage404.nix-extension-pack

        # Git
        donjayamanne.githistory
        eamodio.gitlens
        github.remotehub
        github.vscode-github-actions
        github.vscode-pull-request-github
        mhutchie.git-graph
        ms-vscode.azure-repos
        ms-vscode.remote-repositories
        rubbersheep.gi
        vivaxy.vscode-conventional-commits
        waderyan.gitblame

        # AI Assistants
        anthropic.claude-code
        block.vscode-goose
        saoudrizwan.claude-dev

        # Editor utilities
        aaron-bond.better-comments
        alefragnani.bookmarks
        alefragnani.project-manager
        britesnow.vscode-toggle-quotes
        chouzz.vscode-better-align
        editorconfig.editorconfig
        formulahendry.auto-close-tag
        formulahendry.auto-complete-tag
        formulahendry.auto-rename-tag
        gruntfuggly.todo-tree
        hoovercj.vscode-settings-cycler
        inu1255.easy-snippet
        jgclark.vscode-todo-highlight
        johnpapa.vscode-peacock
        lacroixdavid1.vscode-format-context-menu
        naumovs.color-highlight
        oderwat.indent-rainbow
        qcz.text-power-tools
        ryu1kn.partial-diff
        ryu1kn.text-marker
        slevesque.vscode-multiclip
        usernamehw.errorlens

        # File formats
        mikestead.dotenv
        nefrob.vscode-just-syntax
        redhat.vscode-xml
        redhat.vscode-yaml
        tomoki1207.pdf

        # Tools
        adpyke.codesnap
        christian-kohler.path-intellisense
        ibm.output-colorizer
        signageos.signageos-vscode-sops

        # Themes
        yummygum.city-lights-icon-vsc
        yummygum.city-lights-theme
      ];

      userSettings = {
        # Extensions - disable auto-update for Nix-managed extensions
        "extensions.autoUpdate" = false;

        # Telemetry
        "redhat.telemetry.enabled" = false;
        "chat.commandCenter.enabled" = false;
        "github.copilot.enable" = {
          "*" = false;
        };
        "github.copilot.chat.enabled" = false;

        # Nix LSP (nixd)
        "nix.enableLanguageServer" = true;
        "nix.serverPath" = "nixd";
        "nix.serverSettings" = {
          nixd = {
            formatting.command = [ "nixfmt" ];
            options = {
              nixos.expr = ''(builtins.getFlake "/home/rona/Repositories/nix-repos/nix-config").nixosConfigurations.aio.options'';
              home-manager.expr = ''(builtins.getFlake "/home/rona/Repositories/nix-repos/nix-config").homeConfigurations."rona@aio".options'';
            };
          };
        };

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

        # Claude Code
        "claudeCode.preferredLocation" = "sidebar";

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
