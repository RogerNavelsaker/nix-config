# users/features/opt-in/yubikey.nix
#
# YubiKey support with GPG agent for SSH authentication
# Requires system-level: services.pcscd.enable = true
#
{ pkgs, ... }:
{
  home = {
    packages = with pkgs; [
      yubikey-manager # ykman CLI
      yubikey-personalization # ykpersonalize
      yubico-piv-tool # PIV operations
    ];

    # Ensure SSH uses GPG agent
    sessionVariables = {
      SSH_AUTH_SOCK = "$(gpgconf --list-dirs agent-ssh-socket)";
    };
  };

  programs = {
    # GPG with SSH support via YubiKey
    gpg = {
      enable = true;
      settings = {
        # Use agent for passphrase
        use-agent = true;
        # Default key preferences
        personal-cipher-preferences = "AES256 AES192 AES";
        personal-digest-preferences = "SHA512 SHA384 SHA256";
        personal-compress-preferences = "ZLIB BZIP2 ZIP Uncompressed";
        default-preference-list = "SHA512 SHA384 SHA256 AES256 AES192 AES ZLIB BZIP2 ZIP Uncompressed";
        # Security
        cert-digest-algo = "SHA512";
        s2k-digest-algo = "SHA512";
        s2k-cipher-algo = "AES256";
        # Disable recipient key ID in messages
        throw-keyids = true;
        # Display preferences
        keyid-format = "0xlong";
        with-fingerprint = true;
        list-options = "show-uid-validity";
        verify-options = "show-uid-validity";
      };
      # scdaemon config for YubiKey
      scdaemonSettings = {
        pcsc-driver = "${pkgs.pcsclite}/lib/libpcsclite.so";
        card-timeout = "5";
        disable-ccid = true;
      };
    };

    # Shell integration for GPG agent socket
    fish.interactiveShellInit = ''
      set -gx SSH_AUTH_SOCK (gpgconf --list-dirs agent-ssh-socket)
      set -gx GPG_TTY (tty)
    '';

    bash.initExtra = ''
      export SSH_AUTH_SOCK="$(gpgconf --list-dirs agent-ssh-socket)"
      export GPG_TTY="$(tty)"
    '';
  };

  # GPG agent with SSH support
  services.gpg-agent = {
    enable = true;
    enableSshSupport = true;
    enableExtraSocket = true;
    # Qt pinentry for KDE Plasma
    pinentry.package = pkgs.pinentry-qt;
    # Cache settings (8 hours default, 24 hours max)
    defaultCacheTtl = 28800;
    maxCacheTtl = 86400;
    defaultCacheTtlSsh = 28800;
    maxCacheTtlSsh = 86400;
    extraConfig = ''
      allow-loopback-pinentry
    '';
  };
}
