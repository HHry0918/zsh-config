# zsh-config

Portable zsh + oh-my-zsh interactive shell setup. Installs onto a fresh Linux workstation
or macOS box via `./install.sh`.

## Layout

- `zsh/` — `.zshenv` (portable env only), `.zshrc` loader + `zshrc.d/` modules, oh-my-zsh
  custom aliases/theme, `.zfunc/` completions, `.dircolors`.
- `git/` — `.gitconfig`, commit message template, delta theming, global `.gitignore`.
- `bat/`, `ripgrep/`, `fd/`, `lsd/`, `tmux/`, `vim/`, `ghostty/` — per-tool config.
- `work/` — Morse Micro specific env, aliases, utilities, git identity. Installed only
  with `--with-work`. **This directory is why the repo stays private.**
- `bootstrap/` — installs the binaries these configs assume: `bootstrap/deps-linux.sh`
  (apt) or `bootstrap/deps-macos.sh` (Homebrew) — `fzf`, `delta`, `fd`, `rg`, `bat`,
  `lsd`, `zoxide`, `tmux`, and on macOS, `python3` + the Ghostty app itself.

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

## macOS / Ghostty

`./bootstrap/deps-macos.sh` installs Homebrew packages plus the Ghostty app itself
(skipped if already installed). Then `./install.sh --with-work` as usual.

- **`ghostty/config`** is tracked and symlinked to `~/.config/ghostty/config` — the same
  XDG path Ghostty reads on Linux, so one file covers both. For a per-machine override,
  drop settings in `~/Library/Application Support/com.mitchellh.ghostty/config`
  instead — Ghostty loads that *after* the XDG file, so it wins, matching the
  `~/.zshrc.local` pattern above.
- **`shell-integration-features = ...,ssh-env,ssh-terminfo`** in that config matters if
  you `ssh` from Ghostty into a Linux box: Ghostty sets `TERM=xterm-ghostty`, which a
  remote host without Ghostty's terminfo entry rejects as "missing or unsuitable
  terminal". `ssh-env` rewrites `TERM` for the remote session; `ssh-terminfo` also tries
  to install the real entry.
- **Homebrew zsh and `/etc/shells`**: if `/opt/homebrew/bin/zsh` isn't listed in
  `/etc/shells`, `install.sh` prints the exact `sudo tee -a` command rather than
  appending it for you — it's the one system-file edit the script won't make silently.
- **`--terminator-font` is Linux-only** (Terminator doesn't run on macOS); `install.sh`
  skips it there with a note pointing at `ghostty/config` instead.

## Per-machine escape hatches

Two files, neither tracked, both silently no-ops when absent:

- `~/.zshrc.local` — sourced last by `zsh/zshrc`, for shell config specific to one box.
- `~/.gitconfig.local` — included last by `git/gitconfig`, e.g. a `[user]` identity on a
  machine with no `~/work/` (so `git/gitconfig`'s `[includeIf "gitdir:~/work/"]` never fires).

## Why not stow/chezmoi

Plain symlinks via a shell script — one dependency (bash), fully readable, easy to undo
(`rm` the symlink, restore from `~/.zsh-config-backup/`).
