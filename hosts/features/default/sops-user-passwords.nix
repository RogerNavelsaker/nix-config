{
  config,
  lib,
  options,
  pkgs,
  ...
}:
let
  passwordSuffix = "-password";
  sopsSecrets = if options ? sops && options.sops ? secrets then config.sops.secrets else { };
  # nix-lib names plaintext account secrets <username>-password and marks them neededForUsers.
  passwordSecrets = lib.filterAttrs (
    secretName: secret:
    lib.hasSuffix passwordSuffix secretName
    && builtins.stringLength secretName > builtins.stringLength passwordSuffix
    && secret.neededForUsers
  ) sopsSecrets;

  userForSecret = secretName: lib.removeSuffix passwordSuffix secretName;
  hashPathForUser = username: "/run/nixos-user-password-hashes/${username}";
  activationNameForUser = username: "hash-sops-user-password-${username}";

  hashScripts = lib.mapAttrs' (
    secretName: secret:
    let
      username = userForSecret secretName;
      hashPath = hashPathForUser username;
      hashDirectory = "/run/nixos-user-password-hashes";
      temporaryTemplate = "${hashDirectory}/${username}.XXXXXXXXXX";
    in
    lib.nameValuePair (activationNameForUser username) {
      deps = [ "setupSecretsForUsers" ];
      text = ''
        set -euo pipefail
        secret_file=${lib.escapeShellArg secret.path}
        hash_file=${lib.escapeShellArg hashPath}
        hash_directory=${lib.escapeShellArg hashDirectory}

        ${pkgs.coreutils}/bin/install -d -m 0700 "$hash_directory"
        ${pkgs.coreutils}/bin/chmod 0700 "$hash_directory"
        if ! ${pkgs.coreutils}/bin/test -s "$secret_file"; then
          echo "SOPS account password secret is empty" >&2
          exit 1
        fi

        temporary_file="$(${pkgs.coreutils}/bin/mktemp ${lib.escapeShellArg temporaryTemplate})"
        trap '${pkgs.coreutils}/bin/rm -f -- "$temporary_file"' EXIT
        ${pkgs.mkpasswd}/bin/mkpasswd --method=yescrypt --stdin < "$secret_file" > "$temporary_file"
        ${pkgs.coreutils}/bin/test -s "$temporary_file"
        ${pkgs.coreutils}/bin/chmod 0400 "$temporary_file"
        ${pkgs.coreutils}/bin/mv -f -- "$temporary_file" "$hash_file"
        trap - EXIT
      '';
    }
  ) passwordSecrets;

  userPasswordFiles = lib.mapAttrs' (
    secretName: _:
    let
      username = userForSecret secretName;
    in
    lib.nameValuePair username {
      hashedPasswordFile = lib.mkForce (hashPathForUser username);
    }
  ) passwordSecrets;
in
{
  users.users = userPasswordFiles;

  system.activationScripts = hashScripts // {
    users.deps = lib.mapAttrsToList (
      secretName: _: activationNameForUser (userForSecret secretName)
    ) passwordSecrets;
  };
}
