# Shared agent Devenv configuration

The single shared environment module is `shared-config/devenv.nix`. Each
agent's local `devenv.yaml` imports a content-hash-versioned copy of that file
as a `flake: false` path input. The import directory lives outside the
installer flake under `~/.local/share/nix-config/agent-devenv-shared/`; this
keeps Devenv's project files writable and avoids stale path-input caches on
Devenv 2.1.x without deleting `.devenv`.

The installer writes a local `~/devenv.yaml` and minimal `~/devenv.nix`
stub, and seeds `~/devenv.lock` as a regular writable file. The central seed
includes the same relative shared-config input for all six; Devenv may update
local copies. Each agent's Devenv state and caches remain local. The installer
backs up existing manifests and refuses unexpected local edits.

The shared module installs `seeds`, `mulch`, `terrarium`, OpenBao's `bao`
client, Smallstep's `step` client, `git`, and `worktrunk` into every common
Devenv shell. These CLIs do not install credentials or configure certificate
renewal. Worktrunk provides the `wt` command; use `git worktree` for Git's
built-in worktree command. Short convenience commands remain: `sd` calls
`seeds`, `ml` calls `mulch`, and `tr` calls `terrarium`. Nushell is already
available as `nu` from the system profile, so Devenv does not shadow it.

Pi is provided directly by each agent's NixOS profile; the shared Devenv
environment does not wrap or replace the system pi command.

Deploy this directory to each agent's
`~/.local/share/nix-config/agent-devenv-central`, then run:

```sh
nix --extra-experimental-features "nix-command flakes" run \
  path:$HOME/.local/share/nix-config/agent-devenv-central#devenv-$USER
```

Run the isolated installer smoke test from this directory:

```sh
nix build --no-link path:$PWD#apps.x86_64-linux.devenv-rowan.program
installer=$(nix eval --raw path:$PWD#apps.x86_64-linux.devenv-rowan.program)
bash tests/installer-smoke.sh "$installer" "$PWD" rowan
```

## Opt-in Pi OpenBao auth migration

Do not run this until OpenBao certificate login and process-scoped injection of
`LITELLM_API_KEY` have passed an end-to-end test for this agent. Stop Pi before
running it; the app refuses to run when the variable is unset.

After the shared configuration is deployed, the app is:

```sh
nix --extra-experimental-features "nix-command flakes" run path:$HOME/.local/share/nix-config/agent-devenv-central#pi-openbao-auth-$USER
```

It changes only `auth.json`'s `litellm.key` to the provider-supported
`$LITELLM_API_KEY` reference; it preserves OpenAI OAuth and all other entries.
The backup under `~/.local/state/pi/backups/` contains the prior API key and all
other auth fields, including OAuth tokens. Its file is mode 0600 inside a mode 0700
directory. Remove it after verification and the rollback window. The app is opt-in
and has not been run on an agent home.

Run its fixture tests without touching an agent home:

```sh
python3 tests/pi-openbao-auth-test.py
```

## Opt-in Pi memory setup

The NixOS profiles provide `mnemosyne-memory` 3.15.1 with local FastEmbed
support. They select `BAAI/bge-small-en-v1.5` and disable API embeddings and
LLM consolidation. Model weights download only when Mnemosyne first uses that
embedding model.

After deploying this directory to
`~/.local/share/nix-config/agent-devenv-central`, opt in for the current agent:

```sh
nix --extra-experimental-features "nix-command flakes" run \
  path:$HOME/.local/share/nix-config/agent-devenv-central#pi-memory-$USER
```

The app uses `pi install` for pinned `pi-lossless`, Pi Mnemosyne, and LLM Wiki
packages. It merges user Pi settings, removes Engram package/extension
references, disables Wiki ambient personal-vault behavior and trajectory
capture, and sets LCM swap/recut ratios to 70%/70%. Existing token-based LCM
threshold overrides are removed because they take precedence over ratios.
Existing JSON settings are backed up under
`~/.local/state/pi/backups/`; symlinked or invalid JSON targets are refused.
The app is explicit and was not run during configuration evaluation.

The 24,000-token allowance applies to an individual `lcm_expand_query` recall
call via its `max_tokens` argument; it does not change Pi's model context window
or compaction retention. LCM handles automatic compaction itself. Before
substantive work with relevant history, search Mnemosyne and LCM first, and use
`lcm_expand_query` to recover source messages when needed. Use Wiki tools only
in projects that contain their own `.llm-wiki/` vault; do not use the personal
vault as cross-project memory.

Run the Pi setup fixture test without touching an agent home:

```sh
python3 tests/pi-memory-setup-test.py
```

WSL/LXC/VPS differences belong in the NixOS system profiles, not in this
shared Devenv module. Herdr remains system-managed; do not configure Herdr
connections as part of this install.
