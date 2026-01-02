# users/rona/aio.nix
#
# Home Manager configuration for rona on Arch Linux (aio)
#
# Features loaded automatically by mkHome:
# - default/*: shell, dev-tools, editor, environment
# - opt-out/*: git, direnv, ssh (included by default)
# - opt-in: claude-code, goose (specified in flake.nix)
#
_: {
  # AIO-specific config only (features handled by mkHome)

  # Use Mesa drivers for AMD GPU
  # nixGLIntel = Mesa OpenGL (Intel/AMD/Nouveau)
  # nixVulkanIntel = Mesa Vulkan (Intel/AMD)
  nixgl.driver = "nixGLIntel";
  nixgl.vulkan = "nixVulkanIntel";
}
