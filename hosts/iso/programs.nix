{ pkgs, ... }:
{
  # Shell and tools
  programs.fish.enable = true;
  programs.mosh.enable = true;

  # Installation and system tools
  environment.systemPackages = with pkgs; [
    vim
    git
    wget
    curl
    parted
    gptfdisk
    cryptsetup
    jq
  ];
}
