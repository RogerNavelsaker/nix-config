# users/features/opt-in/yazi.nix
#
# Yazi terminal file manager
#
{ pkgs, ... }:
{
  programs.yazi = {
    enable = true;
    enableFishIntegration = true;

    settings = {
      manager = {
        show_hidden = true;
        sort_by = "natural";
        sort_dir_first = true;
        linemode = "size";
        show_symlink = true;
      };

      preview = {
        tab_size = 2;
        max_width = 600;
        max_height = 900;
      };

      opener = {
        edit = [
          {
            run = ''hx "$@"'';
            block = true;
            for = "unix";
          }
        ];
        open = [
          {
            run = ''xdg-open "$@"'';
            desc = "Open";
            for = "linux";
          }
        ];
      };
    };

    keymap = {
      manager.prepend_keymap = [
        {
          on = [
            "g"
            "h"
          ];
          run = "cd ~";
          desc = "Go to home";
        }
        {
          on = [
            "g"
            "r"
          ];
          run = "cd ~/Repositories";
          desc = "Go to Repositories";
        }
        {
          on = [
            "g"
            "d"
          ];
          run = "cd ~/Downloads";
          desc = "Go to Downloads";
        }
        {
          on = [
            "g"
            "c"
          ];
          run = "cd ~/.config";
          desc = "Go to config";
        }
      ];
    };
  };

  # Extra packages for preview support
  home.packages = with pkgs; [
    ffmpegthumbnailer # Video thumbnails
    unar # Archive extraction
    poppler # PDF preview
    fd # File search
    ripgrep # Content search
    fzf # Fuzzy finder
    imagemagick # Image operations
  ];
}
