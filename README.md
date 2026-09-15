# zsh-config

Portable zsh + oh-my-zsh interactive shell setup. Installs onto a fresh Linux workstation
or macOS box via `./install.sh`.

## Layout

- `zsh/` — `.zshenv` (portable env only), `.zshrc` loader + `zshrc.d/` modules, oh-my-zsh
  custom aliases/theme, `.zfunc/` completions, `.dircolors`.
- `git/` — `.gitconfig`, commit message template, delta theming, global `.gitignore`.
- `bat/`, `ripgrep/`, `fd/`, `lsd/`, `tmux/`, `vim/` — per-tool config.
- `work/` — Morse Micro specific env, aliases, utilities, git identity. Installed only
  with `--with-work`. **This directory is why the repo stays private.**
- `bootstrap/` — installs the binaries these configs assume (`fzf`, `delta`, `fd`, `rg`,
  `bat`, `lsd`, `zoxide`, `tmux`).

## Install

```sh
./install.sh --dry-run --with-work   # preview
./install.sh --with-work             # actually link
```

Existing real files at any symlink target are backed up to
`~/.zsh-config-backup/<UTC timestamp>/` before being replaced — nothing is silently overwritten.

## Secrets

`~/.zshenv` traditionally held plaintext credentials (TestRail, DigitalOcean, New Relic,
Atlassian, Jenkins, Slack tokens, a DB password). None of that is in this repo. Instead:

- `zsh/zshenv` (tracked) holds only portable exports (`PATH`, `EDITOR`, `BAT_THEME`, tool
  roots, telemetry opt-outs) and sources two files if present:
  - `~/.zshenv.secrets` (untracked, mode 0600) — copy `zsh/zshenv.secrets.template` and fill
    in real values.
  - `~/.work-env.zsh` (untracked when installed without `--with-work`; otherwise a symlink
    to `work/work-env.zsh`) — non-secret work URLs/paths.

To migrate an existing machine's live `~/.zshenv` into this split, run
`./install.sh --migrate-zshenv` (see script for the backup-first sequence).

## Per-machine escape hatches

Two files, neither tracked, both silently no-ops when absent:

- `~/.zshrc.local` — sourced last by `zsh/zshrc`, for shell config specific to one box.
- `~/.gitconfig.local` — included last by `git/gitconfig`, e.g. a `[user]` identity on a
  machine with no `~/work/` (so `git/gitconfig`'s `[includeIf "gitdir:~/work/"]` never fires).

## Why not stow/chezmoi

Plain symlinks via a shell script — one dependency (bash), fully readable, easy to undo
(`rm` the symlink, restore from `~/.zsh-config-backup/`).
