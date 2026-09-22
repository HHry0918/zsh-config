#!/usr/bin/env bash
# Copies this repo's zsh/oh-my-zsh/git/tool config into $HOME. Idempotent — re-running
# is how repo changes get applied to a box that already has this installed, since
# nothing here is a symlink any more (see copy() below). Run './install.sh --help'.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bootstrap/lib-tools.sh
source "$REPO_DIR/bootstrap/lib-tools.sh"

OS="$(uname -s)"
BACKUP_DIR="$HOME/.zsh-config-backup/$(date -u +%Y%m%dT%H%M%SZ)"
LOG_FILE="/tmp/zsh-config-install-$(date -u +%Y%m%dT%H%M%SZ).log"
DRY_RUN=false
BACKOUT=false
DISPLAY_HOST=false
TERM_APP=none

usage() {
  cat <<'EOF'
Usage: ./install.sh [OPTIONS]

Copies this repo's zsh/oh-my-zsh/git/tool config into $HOME — real files, not
symlinks, so a box can be tweaked locally without live-editing the repo. Detects
Ubuntu vs macOS and the terminal app in use, prints a full inventory of the tools
this config assumes, and waits for you to confirm before touching anything.
Re-running is how you apply repo updates; existing files that differ are backed
up under ~/.zsh-config-backup/<timestamp>/ before being overwritten.

Options:
  -h, --help       Show this help and exit.
  --dry-run        Print the tool inventory and every action that would be taken,
                    then stop before the confirmation prompt. Changes nothing.
  --backout        Destructive full undo: restores every file from the most recent
                    backup, switches the login shell back to what it was before
                    install.sh last ran, and removes the frameworks install.sh
                    clones (oh-my-zsh, fzf, zinit, powerlevel10k). Requires typing
                    "backout" to confirm. Combine with --dry-run to preview it.
  --display-host   Show "user@host" in the prompt (hidden by default — both themes
                    already render it, this just un-hides it). Useful on a fleet of
                    similarly-named shared boxes. Writes ZSH_CONFIG_DISPLAY_HOST=1
                    into ~/.zshrc.local.

What this script checks and installs, in order:
  1. Detects the OS (Ubuntu or macOS only — anything else exits with a message)
     and the terminal app in use (Terminator / Ghostty / other).
  2. Prints an inventory of 16 tools/frameworks/fonts this config assumes: zoxide,
     zsh, oh-my-zsh, fzf, lsd, fd, ripgrep, delta, procs, tmux, powerlevel10k,
     MesloLGS NF, bat, jq, git, vim — each marked present
     (with version) or MISSING, plus a summary of which dotfiles would change.
  3. Waits for you to type y to proceed. Never auto-proceeds without a real TTY.
  4. Best-effort installs whatever's missing (bootstrap/deps-linux.sh or
     deps-macos.sh), then copies every dotfile, clones the oh-my-zsh/fzf-tab/
     powerlevel10k frameworks, installs the MesloLGS NF font, and — on Terminator
     only — writes a font stanza if none exists yet (never edits an existing one).
  5. Switches the login shell to zsh if it isn't already (needs zsh listed in
     /etc/shells; never auto-appends to that file).

Two files this script never writes secrets/identity into automatically — you own
them: ~/.zshenv.secrets (create it yourself, chmod 600 — no template ships) and
~/.gitconfig.local (holds your `git config user.name`/`user.email`).

Every run is logged to /tmp/zsh-config-install-<UTC-timestamp>.log.

Examples:
  ./install.sh --dry-run             # see what would happen, change nothing
  ./install.sh                       # install
  ./install.sh --backout --dry-run   # preview a full undo
  ./install.sh --backout             # undo everything install.sh last did
EOF
}

for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    --dry-run) DRY_RUN=true ;;
    --backout) BACKOUT=true ;;
    --display-host) DISPLAY_HOST=true ;;
    *) echo "install.sh: unknown flag '$arg'" >&2; usage >&2; exit 1 ;;
  esac
done

# Log everything from here on, both to the terminal and to $LOG_FILE — this is the
# feedback channel for the scp-then-you-run-it-then-I-read-the-log deploy loop.
mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "install.sh: logging to $LOG_FILE"

run() {
  if $DRY_RUN; then
    echo "+ $*"
  else
    "$@"
  fi
}

# copy SRC(repo-relative) DEST(absolute)
#
# - dest is a symlink INTO this repo (the old install mechanism) -> remove the link,
#   then copy. Mandatory special case: `cp src dest` where dest resolves to src either
#   errors "same file" or writes the file back into the repo instead of $HOME.
# - dest is a symlink elsewhere -> back up the link itself, then copy.
# - dest is a regular file identical to src (cmp -s) -> no-op. This is what keeps
#   re-runs cheap now that symlinks no longer propagate every edit live.
# - dest is a regular file that differs -> back it up, then copy.
copy() {
  local src="$REPO_DIR/$1" dest="$2" rel
  rel="${dest#"$HOME"/}"
  if [[ -L "$dest" ]]; then
    local target; target="$(readlink "$dest")"
    if [[ "$target" == "$src" || "$target" == "$REPO_DIR"/* ]]; then
      echo "install.sh: $dest is a legacy symlink into the repo, converting to a real file"
      run rm -f "$dest"
    else
      echo "install.sh: backing up existing symlink $dest -> $BACKUP_DIR/"
      run mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
      run mv "$dest" "$BACKUP_DIR/$rel"
    fi
  elif [[ -e "$dest" ]]; then
    if cmp -s "$src" "$dest" 2>/dev/null; then
      return 0
    fi
    echo "install.sh: backing up existing $dest -> $BACKUP_DIR/"
    run mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
    run mv "$dest" "$BACKUP_DIR/$rel"
  fi
  run mkdir -p "$(dirname "$dest")"
  run cp -p "$src" "$dest"
  echo "install.sh: copied $dest <- $src"
}

# copy_dir SRC_DIR(repo-relative) DEST_DIR(absolute) — for zsh/zfunc -> ~/.zfunc, a
# directory that used to be one symlink. Writes a manifest of installed basenames next
# to it; on the next run, anything in the old manifest but no longer in the repo is
# backed up and removed (a deleted completion doesn't linger and shadow the real one),
# while files never in the manifest (your own) are left untouched.
copy_dir() {
  local src_dir="$REPO_DIR/$1" dest_dir="$2"
  local manifest="$dest_dir/.zsh-config-manifest"
  local old_manifest=""
  [[ -f "$manifest" ]] && old_manifest="$(cat "$manifest")"

  if [[ -L "$dest_dir" ]]; then
    echo "install.sh: $dest_dir is a legacy directory symlink, converting to real files"
    run rm -f "$dest_dir"
  fi
  run mkdir -p "$dest_dir"

  local new_manifest="" f base
  for f in "$src_dir"/*; do
    [[ -f "$f" ]] || continue
    base="$(basename "$f")"
    copy "$1/$base" "$dest_dir/$base"
    new_manifest+="$base"$'\n'
  done

  local name
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    if ! grep -qxF "$name" <<<"$new_manifest"; then
      echo "install.sh: $dest_dir/$name is no longer in the repo, backing up and removing"
      run mkdir -p "$BACKUP_DIR/$(dirname "${dest_dir#"$HOME"/}")"
      run mv "$dest_dir/$name" "$BACKUP_DIR/$(dirname "${dest_dir#"$HOME"/}")/$name"
    fi
  done <<<"$old_manifest"

  if ! $DRY_RUN; then
    printf '%s' "$new_manifest" > "$manifest"
  fi
}

clone_if_missing() {
  local url="$1" dest="$2"
  [[ -d "$dest" ]] && return 0
  run mkdir -p "$(dirname "$dest")"
  run git clone --depth 1 "$url" "$dest"
}

# install_meslo_font — MesloLGS NF is Powerlevel10k's own recommended font (see its
# README's "Recommended font" section), fetched as 4 individual pre-built .ttf files
# from romkatv/powerlevel10k-media — not the same artifact as nerd-fonts' generic
# Meslo.zip. It's the only Nerd Font this script installs — the agnoster theme's
# Powerline glyphs (U+E0A0/U+E0B0) and lsd --icon=always's broader icon set both come
# from it; neither renders without a Nerd Font selected in whatever terminal is
# actually drawing the glyphs.
install_meslo_font() {
  if [[ "$OS" == Darwin ]]; then
    if compgen -G "$HOME/Library/Fonts/MesloLGS NF*.ttf" >/dev/null 2>&1 \
    || compgen -G "/Library/Fonts/MesloLGS NF*.ttf" >/dev/null 2>&1; then
      echo "install.sh: MesloLGS NF already installed, skipping"
      return 0
    fi
  elif ( set +o pipefail; fc-list 2>/dev/null | grep -qi "MesloLGS NF" ); then
    echo "install.sh: MesloLGS NF already installed, skipping"
    return 0
  fi
  local base="https://github.com/romkatv/powerlevel10k-media/raw/master"
  local files=(
    "MesloLGS NF Regular.ttf"
    "MesloLGS NF Bold.ttf"
    "MesloLGS NF Italic.ttf"
    "MesloLGS NF Bold Italic.ttf"
  )
  if $DRY_RUN; then
    echo "+ download and install MesloLGS NF (4 files) from $base"
    return 0
  fi
  echo "install.sh: fetching MesloLGS NF..."
  local dest
  if [[ "$OS" == Darwin ]]; then
    dest="$HOME/Library/Fonts"
  else
    dest="$HOME/.local/share/fonts/NerdFonts/MesloLGS"
  fi
  mkdir -p "$dest"
  local f
  for f in "${files[@]}"; do
    curl -fsSL "$base/${f// /%20}" -o "$dest/$f"
  done
  if [[ "$OS" != Darwin ]] && command -v fc-cache >/dev/null; then
    fc-cache -f "$dest" >/dev/null
  fi
  echo "install.sh: installed MesloLGS NF -> $dest"
}

# ensure_zsh_shell — a repo whose entire job is a zsh config should leave you in zsh.
# Records the prior shell into $BACKUP_DIR/.install-state right before actually
# switching it, so --backout can revert to whatever it actually was (not a hardcoded
# /bin/bash). Deliberately not recorded on every run — only when a switch is about to
# happen — so a fully no-op re-run creates no $BACKUP_DIR at all (idempotency).
ensure_zsh_shell() {
  local current_shell
  if [[ "$OS" == Darwin ]]; then
    current_shell=$(dscl . -read "/Users/$USER" UserShell 2>/dev/null | tr '\n' ' ' | awk '{print $2}' || true)
  else
    current_shell=$(getent passwd "$USER" 2>/dev/null | cut -d: -f7 || true)
  fi

  local zsh_path; zsh_path=$(command -v zsh || true)
  if [[ -z "$zsh_path" ]]; then
    echo "install.sh: zsh not found on PATH, can't switch the login shell — install zsh first" >&2
    return 0
  fi
  if [[ "$current_shell" == "$zsh_path" ]]; then
    echo "install.sh: login shell is already $zsh_path, skipping chsh"
    return 0
  fi

  run mkdir -p "$BACKUP_DIR"
  if ! $DRY_RUN; then
    printf 'PRIOR_SHELL=%s\n' "$current_shell" >> "$BACKUP_DIR/.install-state"
  else
    echo "+ record prior login shell ($current_shell) to $BACKUP_DIR/.install-state"
  fi

  if ! grep -qxF "$zsh_path" /etc/shells 2>/dev/null; then
    if [[ "$OS" == Darwin ]]; then
      echo "install.sh: $zsh_path isn't in /etc/shells. Add it, then re-run:" >&2
      echo "  echo $zsh_path | sudo tee -a /etc/shells" >&2
      echo "  (or accept macOS's system zsh: chsh -s /bin/zsh)" >&2
    else
      echo "install.sh: $zsh_path isn't listed in /etc/shells, can't chsh to it as a non-root user — add it there first" >&2
    fi
    return 0
  fi
  if $DRY_RUN; then
    echo "+ switch login shell to $zsh_path (takes effect on next login)"
    return 0
  fi
  if sudo -n true 2>/dev/null; then
    if sudo -n chsh -s "$zsh_path" "$USER"; then
      echo "install.sh: switched login shell to $zsh_path (takes effect on next login)"
    else
      echo "install.sh: 'sudo chsh' failed — switch manually with: chsh -s $zsh_path" >&2
    fi
  elif [[ -t 0 ]]; then
    echo "install.sh: switching login shell to $zsh_path (may prompt for your password)"
    chsh -s "$zsh_path" || echo "install.sh: chsh failed — switch manually with: chsh -s $zsh_path" >&2
  else
    echo "install.sh: no passwordless sudo and no TTY to prompt on — switch manually with: chsh -s $zsh_path" >&2
  fi
}

# detect_os — Ubuntu (via /etc/os-release ID) or macOS only. Anything else exits with
# a clear message rather than guessing.
detect_os() {
  case "$OS" in
    Darwin) OS_LABEL="macOS" ;;
    Linux)
      if [[ -r /etc/os-release ]] && . /etc/os-release && [[ "${ID:-}" == ubuntu ]]; then
        OS_LABEL="Ubuntu ${VERSION_ID:-}"
      else
        echo "install.sh: this Linux isn't Ubuntu (checked /etc/os-release ID=) — this script only supports Ubuntu and macOS. Use bootstrap/*.sh + a manual copy on anything else." >&2
        exit 1
      fi
      ;;
    *)
      echo "install.sh: unsupported OS '$OS' — this script only supports Ubuntu and macOS." >&2
      exit 1
      ;;
  esac
}

# detect_terminal — best-effort, used only to decide whether the Terminator font
# stanza below applies. Never fails the run if it can't tell.
detect_terminal() {
  if [[ "$OS" != Darwin ]] && command -v terminator >/dev/null 2>&1; then
    TERM_APP=terminator
  elif [[ -n "${GHOSTTY_RESOURCES_DIR:-}" ]] || command -v ghostty >/dev/null 2>&1; then
    TERM_APP=ghostty
  else
    TERM_APP=none
  fi
}

# print_tool_inventory — the fixed, explicit 17-entry list. Every entry is checked and
# reported, not a subset. Re-used verbatim (same probes) by the post-install tool
# report in 4b.
print_tool_inventory() {
  echo "== zsh-config install plan ($OS_LABEL, terminal: $TERM_APP) =="
  printf '  %-18s %-10s %s\n' zoxide "$(tool_version zoxide)" "$(probe zoxide && echo OK || echo MISSING)"
  printf '  %-18s %-10s %s\n' zsh "$(tool_version zsh)" "$(command -v zsh >/dev/null && echo OK || echo MISSING)"
  printf '  %-18s %-10s %s\n' oh-my-zsh - "$([[ -d "$HOME/.oh-my-zsh" ]] && echo OK || echo "MISSING -> will clone")"
  printf '  %-18s %-10s %s\n' fzf "$(tool_version fzf)" "$(probe fzf && echo OK || echo "MISSING/OLD -> will build")"
  printf '  %-18s %-10s %s\n' lsd "$(tool_version lsd)" "$(probe lsd && echo OK || echo "MISSING/OLD -> will fetch")"
  if command -v fd >/dev/null; then
    printf '  %-18s %-10s %s\n' "fd" "$(tool_version fd)" "$(probe fd && echo OK || echo "OLD -> will fetch")"
  elif command -v fdfind >/dev/null; then
    printf '  %-18s %-10s %s\n' "fd (fdfind)" "$(tool_version fdfind)" OK
  else
    printf '  %-18s %-10s %s\n' fd - "MISSING -> will fetch"
  fi
  if command -v rg >/dev/null; then
    printf '  %-18s %-10s %s\n' "ripgrep (rg)" "$(tool_version rg)" OK
  else
    printf '  %-18s %-10s %s\n' ripgrep - MISSING
  fi
  printf '  %-18s %-10s %s\n' delta "$(tool_version delta)" "$(probe delta && echo OK || echo "MISSING/OLD -> will fetch")"
  if command -v procs >/dev/null; then
    local pflag; pflag=$(probe procs && echo "supports current flag" || echo "flag mismatch — see zsh/zshrc's dual-flag probe")
    printf '  %-18s %-10s %s\n' procs "$(tool_version procs)" "OK ($pflag)"
  else
    printf '  %-18s %-10s %s\n' procs - "MISSING (not installed by this repo — reported only)"
  fi
  printf '  %-18s %-10s %s\n' tmux "$(tool_version tmux)" "$(command -v tmux >/dev/null && echo OK || echo MISSING)"
  printf '  %-18s %-10s %s\n' powerlevel10k - "$([[ -d "$HOME/.oh-my-zsh/custom/themes/powerlevel10k" ]] && echo OK || echo "MISSING -> will clone")"
  if [[ "$OS" == Darwin ]]; then
    printf '  %-18s %-10s %s\n' "MesloLGS NF" - "$(compgen -G "$HOME/Library/Fonts/MesloLGS NF*.ttf" >/dev/null 2>&1 && echo OK || echo "MISSING -> will install")"
  else
    printf '  %-18s %-10s %s\n' "MesloLGS NF" - "$( (set +o pipefail; fc-list 2>/dev/null | grep -qi "MesloLGS NF") && echo OK || echo "MISSING -> will install")"
  fi
  printf '  %-18s %-10s %s\n' bat "$(tool_version bat)" "$(probe bat && echo OK || echo "MISSING/OLD -> will fetch")"
  printf '  %-18s %-10s %s\n' jq "$(tool_version jq)" "$(command -v jq >/dev/null && echo "OK (not used by this repo — reported only)" || echo "MISSING (not used by this repo — reported only)")"
  if [[ "$OS" != Darwin ]]; then
    printf '  %-18s %-10s %s\n' "xsel/xclip" - "$( { command -v xsel >/dev/null || command -v xclip >/dev/null; } && echo "OK (local-desktop clipboard; ssh sessions use OSC 52 instead)" || echo "MISSING -> will install (local-desktop clipboard only; ssh sessions use OSC 52 instead)")"
  fi
  printf '  %-18s %-10s %s\n' git "$(tool_version git)" "$(command -v git >/dev/null && echo OK || echo MISSING)"
  printf '  %-18s %-10s %s\n' vim "$(tool_version vim)" "$(command -v vim >/dev/null && echo OK || echo MISSING)"
  echo
  echo "Log: $LOG_FILE"
}

# do_backout — full destructive undo. Requires typing "backout", not a mere [y/N].
do_backout() {
  local latest
  latest=$(find "$HOME/.zsh-config-backup" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | tail -1) || true
  if [[ -z "$latest" ]]; then
    echo "install.sh: no backup found under ~/.zsh-config-backup/ — nothing to back out." >&2
    exit 1
  fi
  local prior_shell=""
  [[ -f "$latest/.install-state" ]] && prior_shell=$(grep '^PRIOR_SHELL=' "$latest/.install-state" | cut -d= -f2-)

  echo "== --backout: will restore from $latest =="
  echo "Files to restore:"
  find "$latest" -type f ! -name '.install-state' | sed "s|^$latest/|  ~/|"
  echo "Login shell to restore: ${prior_shell:-<not recorded>}"
  echo "Framework directories to remove:"
  echo "  ~/.oh-my-zsh"
  echo "  ~/.fzf"
  echo "  ~/.local/share/zinit"
  echo "  ~/.oh-my-zsh/custom/themes/powerlevel10k"

  if $DRY_RUN; then
    echo "(dry run — nothing changed)"
    return 0
  fi

  read -r -p 'Type "backout" to proceed: ' confirm
  if [[ "$confirm" != backout ]]; then
    echo "install.sh: confirmation not given, aborting backout." >&2
    exit 1
  fi

  local f rel
  while IFS= read -r -d '' f; do
    rel="${f#"$latest"/}"
    [[ "$rel" == .install-state ]] && continue
    mkdir -p "$HOME/$(dirname "$rel")"
    mv "$f" "$HOME/$rel"
    echo "install.sh: restored ~/$rel"
  done < <(find "$latest" -type f -print0)

  if [[ -n "$prior_shell" && -x "$prior_shell" ]]; then
    if sudo -n true 2>/dev/null; then
      sudo -n chsh -s "$prior_shell" "$USER" && echo "install.sh: login shell reverted to $prior_shell"
    elif [[ -t 0 ]]; then
      chsh -s "$prior_shell" && echo "install.sh: login shell reverted to $prior_shell"
    else
      echo "install.sh: no way to chsh non-interactively — revert manually: chsh -s $prior_shell" >&2
    fi
  fi

  rm -rf "$HOME/.oh-my-zsh" "$HOME/.fzf" "$HOME/.local/share/zinit"
  echo "install.sh: removed cloned frameworks"
  echo "== backout complete =="
}

echo "== zsh-config install ($REPO_DIR) =="
$DRY_RUN && echo "(dry run — no changes will be made)"

if $BACKOUT; then
  do_backout
  exit 0
fi

detect_os
detect_terminal
print_tool_inventory

if $DRY_RUN; then
  echo "(dry run — stopping before the confirmation prompt)"
  exit 0
fi

if [[ ! -t 0 ]]; then
  echo "install.sh: no TTY to confirm on — refusing to proceed unconfirmed. Run this interactively." >&2
  exit 1
fi
read -r -p "Proceed with install? [y/N] " confirm
case "$confirm" in
  y|Y|yes|YES) ;;
  *) echo "install.sh: aborted, nothing changed."; exit 0 ;;
esac

### Best-effort tool installs, dispatched by OS.
if [[ "$OS" == Darwin ]]; then
  bash "$REPO_DIR/bootstrap/deps-macos.sh" || echo "install.sh: deps-macos.sh reported problems — see the tool report at the end" >&2
else
  bash "$REPO_DIR/bootstrap/deps-linux.sh" || echo "install.sh: deps-linux.sh reported problems — see the tool report at the end" >&2
fi

install_meslo_font

### Framework clones (never vendored)
clone_if_missing https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh"
clone_if_missing https://github.com/Aloxaf/fzf-tab.git "$HOME/.oh-my-zsh/custom/plugins/fzf-tab"
clone_if_missing https://github.com/romkatv/powerlevel10k.git "$HOME/.oh-my-zsh/custom/themes/powerlevel10k"

# Only clone+build fzf from source if the system's fzf (apt/brew/etc) can't already do
# what zsh/zshrc needs (`--zsh`). Cloning unconditionally would create two fzf installs,
# and if the system one is earlier on PATH, its generated ~/.fzf.zsh would call the OLD
# `fzf --zsh` instead of the new one just built.
if ! probe fzf; then
  clone_if_missing https://github.com/junegunn/fzf.git "$HOME/.fzf"
  if ! $DRY_RUN && [[ -x "$HOME/.fzf/install" && ! -f "$HOME/.fzf.zsh" ]]; then
    "$HOME/.fzf/install" --key-bindings --completion --no-update-rc --no-bash --no-fish
  fi
else
  echo "install.sh: system fzf already supports --zsh, skipping the source build"
fi
# zinit self-bootstraps from zsh/zshrc on first shell start — deliberately not
# duplicated here.

### ~/.zshenv: copied like any other file now (no more migration special-case — the
### secrets/portable split already happened in the repo itself). An existing
### ~/.zshenv that differs is backed up first, same as everything else.
copy zsh/zshenv                                ~/.zshenv

### Core config
copy zsh/zshrc                                 ~/.zshrc
copy zsh/p10k.zsh                              ~/.p10k.zsh
copy zsh/omz-custom/aliases-core.zsh           ~/.oh-my-zsh/custom/aliases-core.zsh
copy zsh/omz-custom/themes/agnoster.zsh-theme  ~/.oh-my-zsh/custom/themes/agnoster.zsh-theme
copy zsh/dircolors                             ~/.dircolors
copy_dir zsh/zfunc                             ~/.zfunc

copy git/gitconfig                             ~/.gitconfig
copy git/gitmessage                            ~/.gitmessage
copy git/delta-themes.gitconfig                ~/delta-themes.gitconfig
copy git/ignore                                ~/.config/git/ignore

copy bat/config                                ~/.config/bat/config
copy ripgrep/ripgreprc                         ~/.config/ripgrep/ripgreprc
copy fd/ignore                                 ~/.config/fd/ignore
copy lsd/config.yaml                           ~/.config/lsd/config.yaml
copy ghostty/config                            ~/.config/ghostty/config
copy tmux/tmux.conf                            ~/.tmux.conf
copy vim/vimrc                                 ~/.vimrc

### --display-host: un-hide the theme's own "user@host" segment via the ~/.zshrc.local
### per-machine escape hatch. Idempotent: never duplicates the line.
if $DISPLAY_HOST; then
  if ! grep -qs '^export ZSH_CONFIG_DISPLAY_HOST=' ~/.zshrc.local 2>/dev/null; then
    run bash -c 'printf "export ZSH_CONFIG_DISPLAY_HOST=1\n" >> ~/.zshrc.local'
    echo "install.sh: added ZSH_CONFIG_DISPLAY_HOST=1 to ~/.zshrc.local"
  else
    echo "install.sh: ~/.zshrc.local already sets ZSH_CONFIG_DISPLAY_HOST, leaving it alone"
  fi
fi

### Terminator font — auto-detected (no flag), exact 4-case rule. Never risks an
### in-place edit of an existing [profiles] section; only appends when none exists at
### all, and only writes a whole new config when there's no config at all.
if [[ "$TERM_APP" == terminator ]]; then
  terminator_config="$HOME/.config/terminator/config"
  if [[ ! -e "$terminator_config" ]]; then
    if $DRY_RUN; then
      echo "+ write $terminator_config selecting font \"MesloLGS NF 11\""
    else
      run mkdir -p "$(dirname "$terminator_config")"
      cat >"$terminator_config" <<'EOF'
[profiles]
  [[default]]
    use_system_font = False
    font = MesloLGS NF 11
EOF
      echo "install.sh: wrote $terminator_config (font: MesloLGS NF 11) — restart Terminator to pick it up"
    fi
  elif ! grep -qs '^\[profiles\]' "$terminator_config"; then
    echo "install.sh: $terminator_config exists with no [profiles] section — appending one"
    if ! $DRY_RUN; then
      cat >>"$terminator_config" <<'EOF'

[profiles]
  [[default]]
    use_system_font = False
    font = MesloLGS NF 11
EOF
    else
      echo "+ append [profiles]/[[default]]/font = MesloLGS NF 11 to $terminator_config"
    fi
  elif ! grep -qs '^[[:space:]]*font[[:space:]]*=' "$terminator_config"; then
    echo "install.sh: $terminator_config already has [profiles] but no font — add manually under [[default]]: use_system_font = False / font = MesloLGS NF 11"
  else
    echo "install.sh: $terminator_config already sets a font, leaving it alone"
  fi
fi

### git identity — never written without asking. `~/.gitconfig` already `[include]`s
### ~/.gitconfig.local (see git/gitconfig), so a plain `--global` read here correctly
### reflects identity set via either file.
if $DRY_RUN; then
  echo "+ prompt for git identity (skipped in dry run)"
elif git config --global user.email >/dev/null 2>&1; then
  echo "install.sh: git identity already set ($(git config --global user.email)), skipping"
elif [[ ! -t 0 ]]; then
  echo "install.sh: no git user.name/email set yet, and no TTY to prompt on. Set it later:"
  echo "  git config -f ~/.gitconfig.local user.name  \"Your Name\""
  echo "  git config -f ~/.gitconfig.local user.email \"you@example.com\""
else
  read -r -p "install.sh: no git user.name/email set yet. Provide them now? [y/N] " want_id
  case "$want_id" in
    y|Y|yes|YES)
      read -r -p "  git user.name: " git_name
      [[ -z "$git_name" ]] && read -r -p "  git user.name (required): " git_name
      read -r -p "  git user.email: " git_email
      [[ -z "$git_email" ]] && read -r -p "  git user.email (required): " git_email
      if [[ -z "$git_name" || -z "$git_email" ]]; then
        echo "install.sh: no name/email given, skipping — set it later with:"
        echo "  git config -f ~/.gitconfig.local user.name  \"Your Name\""
        echo "  git config -f ~/.gitconfig.local user.email \"you@example.com\""
      else
        read -r -p "  Set it (1) globally in ~/.gitconfig, or (2) locally [recommended]? [1/2] " scope
        if [[ "$scope" == 1 ]]; then
          echo "install.sh: WARNING — install.sh manages ~/.gitconfig (copies it from git/gitconfig on every run). An identity written directly into it will look like a diff on your next re-run and get backed up + overwritten."
          read -r -p "  Really write into ~/.gitconfig anyway? [y/N] " confirm_global
          case "$confirm_global" in
            y|Y|yes|YES)
              git config --global user.name "$git_name"
              git config --global user.email "$git_email"
              echo "install.sh: wrote user.name/email to ~/.gitconfig"
              ;;
            *)
              echo "install.sh: cancelled — nothing written."
              ;;
          esac
        else
          read -r -p "  Path for the local identity file [~/.gitconfig.local]: " local_path
          local_path="${local_path:-~/.gitconfig.local}"
          local_path="${local_path/#\~/$HOME}"
          git config -f "$local_path" user.name "$git_name"
          git config -f "$local_path" user.email "$git_email"
          echo "install.sh: wrote user.name/email to $local_path"
          if ! grep -qsF "$local_path" ~/.gitconfig.local ~/.gitconfig 2>/dev/null && [[ "$local_path" != "$HOME/.gitconfig.local" ]]; then
            echo "install.sh: $local_path isn't included by anything yet — wire it in with:"
            echo "  git config --global include.path $local_path"
          fi
        fi
      fi
      ;;
    *)
      echo "install.sh: skipping — set it later with:"
      echo "  git config -f ~/.gitconfig.local user.name  \"Your Name\""
      echo "  git config -f ~/.gitconfig.local user.email \"you@example.com\""
      ;;
  esac
fi

ensure_zsh_shell

### Tool report (4b) — re-run the identical 17-entry probe, plus gitleaks (only
### relevant here since it's what would gate git/hooks/pre-commit if you opt into it —
### that hook is tracked but never wired up by this script).
echo "== tool report =="
{
  print_tool_inventory
  if command -v gitleaks >/dev/null; then
    printf '  %-18s %-10s %s\n' gitleaks "$(tool_version gitleaks)" OK
  else
    printf '  %-18s %-10s %s\n' gitleaks - "MISSING (optional — github.com/gitleaks/gitleaks/releases)"
  fi
} || true

echo "== done =="
[[ -d "$BACKUP_DIR" ]] && echo "Originals backed up to: $BACKUP_DIR"
echo "If you use ~/.zshenv.secrets for credentials, make sure it exists and is chmod 600."
echo "Log: $LOG_FILE"
echo "Start a new shell (or 'exec zsh') to pick up the changes."
