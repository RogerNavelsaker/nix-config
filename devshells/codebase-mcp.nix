# devshells/codebase-mcp.nix
# Full shell - no local flake, central provides everything
{
  pkgs,
  mkProjectShell,
  ...
}:
mkProjectShell {
  name = "codebase-mcp";

  motd = ''
    ╔════════════════════════════════════════════╗
    ║  Codebase MCP Server Development          ║
    ╚════════════════════════════════════════════╝

    Commands: build, test, clippy, menu
  '';

  packages = with pkgs; [
    rustc
    cargo
    rust-analyzer
    clippy
    rustfmt
    pkg-config
    openssl
  ];

  commands = [
    {
      name = "build";
      category = "development";
      help = "Build the project";
      command = "cargo build";
    }
    {
      name = "test";
      category = "validation";
      help = "Run tests";
      command = "cargo test";
    }
    {
      name = "clippy";
      category = "validation";
      help = "Run clippy lints";
      command = "cargo clippy";
    }
  ];

  env = [
    {
      name = "RUST_BACKTRACE";
      value = "1";
    }
  ];
}
