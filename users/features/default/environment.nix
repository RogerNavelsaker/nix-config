# users/features/default/environment.nix
#
# Environment variables and session configuration
#
{ config, ... }:
let
  homeDir = config.home.homeDirectory;
in
{
  home.sessionVariables = {
    # Repositories location
    REPOSITORIES = "${homeDir}/Repositories";

    # Editor
    EDITOR = "hx";
    VISUAL = "hx";

    # Pager
    PAGER = "bat --paging=always";
    MANPAGER = "sh -c 'col -bx | bat -l man -p'";

    # FZF configuration
    FZF_DEFAULT_COMMAND = "fd --type f --hidden --follow --exclude .git";
    FZF_DEFAULT_OPTS = "--height 40% --layout=reverse --border";
    FZF_CTRL_T_COMMAND = "fd --type f --hidden --follow --exclude .git";
    FZF_ALT_C_COMMAND = "fd --type d --hidden --follow --exclude .git";

    # Ripgrep configuration file
    RIPGREP_CONFIG_PATH = "${config.xdg.configHome}/ripgrep/config";

    # Nix configuration
    NIX_PAGER = "bat --paging=always -l nix";
  };

  # XDG directories
  xdg = {
    enable = true;
    userDirs = {
      enable = true;
      createDirectories = true;
      documents = "${homeDir}/Documents";
      download = "${homeDir}/Downloads";
      music = "${homeDir}/Music";
      pictures = "${homeDir}/Pictures";
      videos = "${homeDir}/Videos";
      desktop = "${homeDir}/Desktop";
      publicShare = "${homeDir}/Public";
      templates = "${homeDir}/Templates";
    };
    # Force overwrite existing user-dirs.dirs (common on existing systems)
    configFile."user-dirs.dirs".force = true;
  };

  # Ripgrep config
  xdg.configFile."ripgrep/config".text = ''
    --smart-case
    --hidden
    --glob=!.git
    --glob=!node_modules
    --glob=!.direnv
    --glob=!result
    --glob=!target
    --max-columns=200
    --max-columns-preview
  '';

  # Enable fontconfig for Nix apps to find system fonts
  fonts.fontconfig.enable = true;
}
