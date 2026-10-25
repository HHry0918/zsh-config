# zsh-config

Portable zsh + oh-my-zsh interactive shell setup, with Powerlevel10k as the default
theme (agnoster kept as a fallback). Installs onto a fresh Ubuntu or macOS box via
`./install.sh`.

## Layout

- `zsh/` — `zshenv` (portable env only), single-file `zshrc` (no more `zshrc.d/`
  modules — flattened into one file), `p10k.zsh` (tracked Powerlevel10k config),
  oh-my-zsh custom aliases/theme, `zfunc/` completions, `dircolors`, `utils.sh`
  (personal shell helpers — VPN wrappers, `multi_rsync`; per-machine values like
  `VPN_PROFILE` go in `~/.zshrc.local`, not here).
- `git/` — `gitconfig` (no `[user]` — see Identity below), commit message template,
  delta theming, global `.gitignore`, an optional `hooks/pre-commit` (gitleaks-backed
  secret-commit guard, tracked but never wired up automatically by `install.sh`).
- `bat/`, `ripgrep/`, `fd/`, `lsd/`, `tmux/`, `vim/`, `ghostty/` — per-tool config.
- `terminator/wslg-wrapper`, `gtk/gtk.css` — WSL-only Terminator window-snapping fix
  (see "WSL / Terminator snapping" below).
- `bootstrap/` — `lib-tools.sh` (shared capability probes + best-effort GitHub-release
  fetcher, used by both scripts below and by `install.sh`'s tool inventory),
  `deps-linux.sh` (apt) and `deps-macos.sh` (Homebrew) — installs `fzf`, `delta`, `fd`,
  `rg`, `bat`, `lsd`, `zoxide`, `tmux`, and on macOS, `python3`, `gitleaks`, and the
  Ghostty app itself.

## Install

```sh
./install.sh --dry-run   # preview: prints the tool inventory, changes nothing
./install.sh             # install
```

`install.sh`:

1. Detects the OS (Ubuntu or macOS only — anything else exits with a message) and the
   terminal app in use (Terminator / Ghostty / other).
2. Prints an inventory of 18 tools/frameworks/fonts on Linux or 17 on macOS — Atuin
   (`>=18.23.0`), `zoxide`, `zsh`, oh-my-zsh, `fzf`, `lsd`, `fd`, `ripgrep`, `delta`,
   `procs`, `tmux`, powerlevel10k, MesloLGS NF, `bat`, `jq`, `git`, `vim`, and the
   Linux-only `xsel/xclip` check. Missing or outdated Atuin is reported with a link to
   [its installation guide](https://docs.atuin.sh/latest/guide/installation/); install.sh
   does not install Atuin automatically. When Atuin is present, it owns Ctrl+R history
   search (fzf keeps Ctrl+T / Alt+C / Tab); without it, Ctrl+R falls back to fzf.
3. Waits for you to confirm. It never auto-proceeds without a real TTY — if there's no
   terminal to confirm on, it stops and says so rather than guessing.
4. Best-effort installs other missing tools, then **copies** every dotfile (not
   symlinks — see below), clones the oh-my-zsh/fzf-tab/powerlevel10k frameworks,
   installs the MesloLGS NF font, and — on Terminator only — writes a font stanza if no
   config exists yet, or appends one if a config exists with no `[profiles]` section.
   It never edits an existing `[profiles]` section.
5. Switches the login shell to zsh if it isn't already (needs zsh listed in
   `/etc/shells`; never auto-appends to that file — prints the exact command instead).

Existing files that differ from the repo are backed up to
`~/.zsh-config-backup/<UTC timestamp>/` before being overwritten — nothing is silently
lost. Every run is logged to `/tmp/zsh-config-install-<UTC-timestamp>.log`.

### Copy, not symlink

Dotfiles are **copied** into `$HOME`, not symlinked. Re-running `./install.sh` is how
you apply repo updates to a box — a copy that's identical to the intended installed
version is a silent no-op (fast re-runs), one that differs gets backed up then
overwritten. This replaced an earlier symlink-based design: live-editing a symlinked
dotfile meant
editing the repo by accident, and every box had detached into real, independent files
anyway. `zsh/zfunc/` is the one directory case — `install.sh` also writes a manifest
next to `~/.zfunc/` so a completion file deleted from the repo is removed on the next
run instead of lingering forever.

On macOS, the installer sets `RIPGREP_CONFIG_PATH` in `~/.zshenv` to the installed
`~/.config/ripgrep/ripgreprc`; Linux keeps the repo's export line.

### `--backout`

Destructive, full undo: restores every file from the most recent backup, switches the
login shell back to whatever it was before `install.sh` last switched it (recorded at
switch time, not guessed), and removes the frameworks `install.sh` clones
(`~/.oh-my-zsh`, `~/.fzf`, `~/.local/share/zinit`). It requires typing `backout` — a
plain `[y/N]` is too weak for the `rm -rf` half. Combine with `--dry-run` to preview
exactly what would be restored/removed without doing it.

### `--display-host`

Both themes hide the `user@host` segment by default (a single workstation doesn't need
it). `--display-host` un-hides it by writing `ZSH_CONFIG_DISPLAY_HOST=1` into
`~/.zshrc.local` — useful on a fleet of similarly-named shared boxes.

## Secrets

`~/.zshenv` traditionally held plaintext credentials (TestRail, DigitalOcean, New
Relic, Atlassian, Jenkins, Slack tokens, DB passwords, internal hostnames). None of
that is in this repo:

- `zsh/zshenv` (tracked) holds only portable exports (`PATH`, `EDITOR`, `BAT_THEME`,
  tool roots, telemetry opt-outs, the macOS Homebrew/gnubin PATH shim) and sources
  `~/.zshenv.secrets` if present, in `if … fi` form (see the "return code 1" note
  below for why that matters).
- `~/.zshenv.secrets` (untracked, mode 0600) — create it yourself, fill in real
  values, `chmod 600` it. No template ships — the exact variable names are up to you.
  `.gitignore` covers this file; `install.sh` never writes to it.

## Identity

Two files this repo never writes to automatically, and never asks `install.sh` to
guess your identity for — you own them:

- **`git/gitconfig`** ships with `[core]`, `[alias]`, `[color]`, `[delta]`, `[diff]`,
  etc. tracked, but deliberately **no `[user]` section** — your name/email are never
  in this repo. `install.sh` prints a pointer if `~/.gitconfig.local` doesn't already
  set them:
  ```sh
  git config -f ~/.gitconfig.local user.name  "Your Name"
  git config -f ~/.gitconfig.local user.email "you@example.com"
  ```
  A commit attempted before that's set fails with git's own "Author identity unknown"
  rather than silently attributing to a stale identity.
- **`~/.zshenv.secrets`** — see Secrets above.

## Per-machine escape hatches

Two more files, neither tracked, both silently no-ops when absent:

- `~/.zshrc.local` — sourced last by `zsh/zshrc`, for shell config specific to one box
  (including `--display-host`'s toggle, above).
- `~/.gitconfig.local` — included last by `git/gitconfig` — your `[user]` identity, or
  anything else specific to one box.

## macOS / Ghostty

`./bootstrap/deps-macos.sh` installs Homebrew packages plus the Ghostty app itself
(skipped if already installed). Then `./install.sh` as usual.

- **`ghostty/config`** is tracked and copied to `~/.config/ghostty/config` — the same
  XDG path Ghostty reads on Linux, so one file covers both. For a per-machine override,
  drop settings in `~/Library/Application Support/com.mitchellh.ghostty/config`
  instead — Ghostty loads that *after* the XDG file, so it wins, matching the
  `~/.zshrc.local` pattern above. Already pinned to `MesloLGS NF` —
  not touched by the Terminator-only font logic below.
- **`shell-integration-features = ...,ssh-env,ssh-terminfo`** in that config matters if
  you `ssh` from Ghostty into a Linux box: Ghostty sets `TERM=xterm-ghostty`, which a
  remote host without Ghostty's terminfo entry rejects as "missing or unsuitable
  terminal". `ssh-env` rewrites `TERM` for the remote session; `ssh-terminfo` also
  tries to install the real entry.
- **Homebrew zsh and `/etc/shells`**: if `/opt/homebrew/bin/zsh` isn't listed in
  `/etc/shells`, `install.sh` prints the exact `sudo tee -a` command rather than
  appending it for you — it's the one system-file edit the script won't make silently.
- **Terminator font auto-config is Linux-only** (Terminator doesn't run on macOS);
  `install.sh` skips it there automatically — no flag needed.

## Fonts

**MesloLGS NF** (Powerlevel10k's own recommended font, per its README) is installed
unconditionally by `install.sh` — no flag needed.
`POWERLEVEL9K_MODE=nerdfont-v3` in `zsh/p10k.zsh` is tuned for it.

## The "return code 1 on a new terminal" bug

A bare `[[ -f X ]] && source X` as the *last* statement of a sourced startup file
leaves `$? = 1` whenever X is absent — zsh doesn't reset it afterward, so it's still
sitting there at your very first prompt. Both `zsh/zshenv` (sourcing
`~/.zshenv.secrets`) and `zsh/zshrc` (sourcing `~/.zshrc.local`) use `if … fi` instead,
and `zsh/zshrc` ends with a literal `true` as a final safety net.

## WSL / Terminator snapping

On WSL (WSLg), GTK picks the Wayland backend and draws client-side decorations with an
invisible shadow margin. WSLg hands each window to Windows as an RDP-RAIL window whose
rectangle includes that shadow, so PowerToys FancyZones and Win+Arrow snap the shadow
box — gaps at zone edges, and content that doesn't reflow. Forcing X11 (XWayland) gets
server-side decorations whose frame matches the real window.

Only when `is_wsl` (in `bootstrap/lib-tools.sh`) is true — plain Ubuntu and macOS are
untouched:

- `install.sh` (Terminator detected) copies `gtk/gtk.css` to `~/.config/gtk-3.0/`
  (strips the CSD shadow — a fallback for anything still on Wayland), and prints the
  sudo command to install `terminator/wslg-wrapper` as `/usr/local/bin/terminator`
  (sets `GDK_BACKEND=x11`; ahead of `/usr/bin` on PATH, so the Start-menu shortcut uses
  it too). It's a system path, so install.sh prints the command rather than running it.
- `bootstrap/deps-linux.sh` generates the `en_AU.UTF-8` locale `zsh/zshenv` exports
  (fresh WSL images have none, and GTK warns "Locale not supported by C library").

After installing the wrapper, close **every** Terminator window — it reuses a single
process, so a new window would otherwise still be on Wayland. Undo: delete
`/usr/local/bin/terminator`.

## Why not stow/chezmoi

A copy-based install via a shell script — one dependency (bash), fully readable, easy
to undo (`./install.sh --backout`, or restore by hand from `~/.zsh-config-backup/`).
