# users/features/opt-in/nixgl.nix
#
# nixGL wrapper for GL apps on non-NixOS systems
# Enable this feature for standalone home-manager on Arch/etc.
# NOT needed on NixOS hosts - they handle GL natively
#
# When enabled, this module:
# - Provides wrapped versions of GL apps
# - Other features check nixgl.enable to skip their packages
#
{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:
let
  nixgl = inputs.nixgl.packages.${pkgs.system};

  # OpenGL driver packages
  glPackages = {
    inherit (nixgl)
      nixGLDefault
      nixGLNvidia
      nixGLNvidiaBumblebee
      nixGLIntel
      ;
  };

  # Vulkan driver packages
  vulkanPackages = {
    inherit (nixgl) nixVulkanNvidia nixVulkanIntel;
  };

  glPkg = glPackages.${cfg.driver};
  glBin = "${glPkg}/bin/${cfg.driver}";

  vulkanBin = lib.optionalString (cfg.vulkan != null) (
    let
      pkg = vulkanPackages.${cfg.vulkan};
    in
    "${pkg}/bin/${cfg.vulkan}"
  );

  # Wrapper that runs GL apps through nixGL driver(s)
  # Chains Vulkan + OpenGL wrappers when both are configured
  # Preserves pname/version for home-manager module compatibility
  # Optional extraEnv for app-specific environment variables
  wrapGL =
    pkg:
    {
      extraEnv ? { },
      noVulkan ? false,
    }:
    let
      # Build env var exports from extraEnv attrset
      envExports = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (name: value: "export ${name}=${lib.escapeShellArg value}") extraEnv
      );
      # Chain: vulkan wrapper -> GL wrapper -> app (if vulkan set and not disabled)
      # Otherwise: GL wrapper -> app
      useVulkan = cfg.vulkan != null && !noVulkan;
      execCmd =
        if useVulkan then "exec ${vulkanBin} ${glBin} $bin \"\\$@\"" else "exec ${glBin} $bin \"\\$@\"";
    in
    pkgs.runCommand "${pkg.name}-nixgl"
      {
        inherit (pkg) pname version;
        nativeBuildInputs = [ pkgs.gnused ];
        meta = (pkg.meta or { }) // {
          mainProgram = pkg.meta.mainProgram or pkg.pname or (builtins.parseDrvName pkg.name).name;
        };
        passthru = pkg.passthru or { };
      }
      ''
        mkdir -p $out/bin
        for bin in ${pkg}/bin/*; do
          name=$(basename $bin)
          cat > $out/bin/$name << EOF
        #!${pkgs.bash}/bin/bash
        ${envExports}
        ${execCmd}
        EOF
          chmod +x $out/bin/$name
        done

        # Copy share directory, patching desktop files to use absolute paths
        if [ -d "${pkg}/share" ]; then
          mkdir -p $out/share
          for item in ${pkg}/share/*; do
            name=$(basename "$item")
            if [ "$name" = "applications" ] && [ -d "$item" ]; then
              mkdir -p $out/share/applications
              for desktop in "$item"/*.desktop; do
                [ -f "$desktop" ] || continue
                name=$(basename "$desktop")
                # Get the main program name from desktop file
                mainProg=$(grep -m1 "^Exec=" "$desktop" | sed 's/^Exec=//' | awk '{print $1}')
                if [ -x "$out/bin/$mainProg" ]; then
                  # Patch Exec= lines to use absolute path
                  sed "s|^Exec=$mainProg|Exec=$out/bin/$mainProg|g; s|^TryExec=$mainProg|TryExec=$out/bin/$mainProg|g" "$desktop" > "$out/share/applications/$name"
                else
                  cp "$desktop" "$out/share/applications/$name"
                fi
              done
            else
              ln -s "$item" "$out/share/$name"
            fi
          done
        fi
      '';

  cfg = config.nixgl;
in
{
  options.nixgl = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether nixGL is providing GL-wrapped packages";
    };

    driver = lib.mkOption {
      type = lib.types.enum [
        "nixGLDefault"
        "nixGLNvidia"
        "nixGLNvidiaBumblebee"
        "nixGLIntel"
      ];
      default = "nixGLIntel";
      description = ''
        OpenGL driver wrapper to use.

        Pure evaluation:
        - nixGLIntel: Mesa OpenGL (Intel, AMD, Nouveau) - default

        Require --impure:
        - nixGLDefault: Auto-detect Nvidia, fallback to Mesa
        - nixGLNvidia: Proprietary Nvidia driver (auto version detection)
        - nixGLNvidiaBumblebee: Proprietary Nvidia on hybrid hardware
      '';
    };

    vulkan = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [
          "nixVulkanIntel"
          "nixVulkanNvidia"
        ]
      );
      default = null;
      description = ''
        Optional Vulkan wrapper to chain with OpenGL driver.
        When set, apps are wrapped with: vulkan -> GL -> app

        - nixVulkanIntel: Mesa Vulkan (Intel, AMD)
        - nixVulkanNvidia: Proprietary Nvidia Vulkan (requires --impure)
      '';
    };

    # Apps to wrap (set by other feature modules)
    wrapBeeper = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to wrap beeper with nixGL";
    };
    wrapYubioath = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to wrap yubioath-flutter with nixGL";
    };
    wrapBitwarden = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to wrap bitwarden-desktop with nixGL";
    };
  };

  config = {
    # When this feature file is imported, enable nixgl
    nixgl.enable = lib.mkDefault true;

    # Wrap home.packages apps only if requested by other modules
    # Also install nixGL commands for manual use (e.g., nixGLIntel firefox)
    home.packages =
      lib.optionals cfg.enable [
        glPkg
      ]
      ++ lib.optionals (cfg.enable && cfg.vulkan != null) [
        vulkanPackages.${cfg.vulkan}
      ]
      ++ lib.optionals (cfg.enable && cfg.wrapBeeper) [
        (wrapGL pkgs.beeper {
          # Skip Vulkan - causes issues with Wayland
          noVulkan = true;
        })
      ]
      ++ lib.optionals (cfg.enable && cfg.wrapYubioath) [ (wrapGL pkgs.yubioath-flutter { }) ]
      ++ lib.optionals (cfg.enable && cfg.wrapBitwarden) [ (wrapGL pkgs.bitwarden-desktop { }) ];

    # Override programs.* packages with wrapped versions
    programs = {
      alacritty.package = lib.mkIf (cfg.enable && config.programs.alacritty.enable) (
        lib.mkForce (wrapGL pkgs.alacritty { })
      );
      kitty.package = lib.mkIf (cfg.enable && config.programs.kitty.enable) (
        lib.mkForce (wrapGL pkgs.kitty { })
      );
      vscode.package = lib.mkIf (cfg.enable && config.programs.vscode.enable) (
        lib.mkForce (wrapGL pkgs.vscode { })
      );
    };
  };
}
