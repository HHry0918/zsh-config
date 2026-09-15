#!/usr/bin/env bash
# Symlinks this repo's config into $HOME. Idempotent, safe to re-run.
# Run './install.sh --help' for options.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.zsh-config-backup/$(date -u +%Y%m%dT%H%M%SZ)"
DRY_RUN=false
WITH_WORK=false
FORCE=false
MIGRATE_ZSHENV=false

usage() {
  cat <<'EOF'
Usage: ./install.sh [OPTIONS]

Symlinks this repo's zsh/oh-my-zsh/git/tool config into $HOME. Idempotent,
safe to re-run — existing real files are backed up before being replaced.

Options:
  -h, --help         Show this help and exit.
  --dry-run          Print every action, change nothing.
  --with-work        Also link work/ (Morse Micro specific env/aliases/utils).
  --force            Overwrite an existing symlink that points elsewhere,
                     without asking.
  --migrate-zshenv   One-time: back up a live ~/.zshenv, then hand off to
                     zsh/zshenv.secrets.template + work/work-env.zsh instead
                     of attempting an automatic secret/portable split.
                     See README.md.

Examples:
  ./install.sh --dry-run --with-work   # preview everything first
  ./install.sh --with-work             # install, including work module
EOF
}

for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    --dry-run) DRY_RUN=true ;;
    --with-work) WITH_WORK=true ;;
    --force) FORCE=true ;;
    --migrate-zshenv) MIGRATE_ZSHENV=true ;;
    *) echo "install.sh: unknown flag '$arg'" >&2; usage >&2; exit 1 ;;
  esac
done

run() {
  if $DRY_RUN; then
    echo "+ $*"
  else
    "$@"
  fi
}

# link SRC(repo-relative) DEST(absolute)
# Backs up an existing non-symlink target before replacing it. Leaves an existing
# symlink alone unless it points somewhere other than SRC (then --force is required).
link() {
  local src="$REPO_DIR/$1" dest="$2"
  if [[ -L "$dest" ]]; then
    if [[ "$(readlink "$dest")" == "$src" ]]; then
      return 0
    elif ! $FORCE; then
      echo "install.sh: $dest is a symlink to $(readlink "$dest"), not $src — skipping (use --force)" >&2
      return 0
    fi
  elif [[ -e "$dest" ]]; then
    echo "install.sh: backing up existing $dest -> $BACKUP_DIR/"
    local rel="${dest#"$HOME"/}"
    run mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
    run mv "$dest" "$BACKUP_DIR/$rel"
  fi
  run mkdir -p "$(dirname "$dest")"
  run ln -sfn "$src" "$dest"
  echo "install.sh: linked $dest -> $src"
}

clone_if_missing() {
  local url="$1" dest="$2"
  [[ -d "$dest" ]] && return 0
  run mkdir -p "$(dirname "$dest")"
  run git clone --depth 1 "$url" "$dest"
}

echo "== zsh-config install ($REPO_DIR) =="
$DRY_RUN && echo "(dry run — no changes will be made)"

### Framework clones (never vendored)
clone_if_missing https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh"
clone_if_missing https://github.com/Aloxaf/fzf-tab.git "$HOME/.oh-my-zsh/custom/plugins/fzf-tab"

# Only clone+build fzf from source if the system's fzf (apt/brew/etc) can't already do
# what 10-framework.zsh needs (`--zsh`). Found the hard way: cloning unconditionally
# creates two fzf installs, and if the system one (e.g. an old apt package) is earlier
# on PATH, its generated ~/.fzf.zsh ends up calling the OLD `fzf --zsh` — which doesn't
# support the flag — instead of the new one the clone just built.
if ! (command -v fzf >/dev/null && fzf --zsh >/dev/null 2>&1); then
  clone_if_missing https://github.com/junegunn/fzf.git "$HOME/.fzf"
  if ! $DRY_RUN && [[ -x "$HOME/.fzf/install" && ! -f "$HOME/.fzf.zsh" ]]; then
    "$HOME/.fzf/install" --key-bindings --completion --no-update-rc --no-bash --no-fish
  fi
else
  echo "install.sh: system fzf already supports --zsh, skipping the source build"
fi
# zinit self-bootstraps from zsh/zshrc.d/10-framework.zsh on first shell start —
# deliberately not duplicated here.

### .zshenv: handled specially — see --migrate-zshenv below. Only auto-linked if
### ~/.zshenv doesn't exist yet (fresh machine); an existing one is never touched
### without the flag, since it may hold real credentials.
if [[ -e ~/.zshenv || -L ~/.zshenv ]]; then
  if $MIGRATE_ZSHENV; then
    echo "== migrating existing ~/.zshenv =="
    if [[ -L ~/.zshenv ]]; then
      echo "install.sh: ~/.zshenv is already a symlink, nothing to migrate" >&2
    else
      run mkdir -p "$BACKUP_DIR"
      run cp -p ~/.zshenv "$BACKUP_DIR/.zshenv"
      if $DRY_RUN; then
        echo "+ verify backup, then split ~/.zshenv into secrets/work/portable and symlink"
      else
        cmp -s ~/.zshenv "$BACKUP_DIR/.zshenv" || { echo "install.sh: backup verification failed, aborting" >&2; exit 1; }
        echo "install.sh: backup verified at $BACKUP_DIR/.zshenv"
        echo "install.sh: automatic variable classification isn't attempted here — the"
        echo "  secret/work var lists already extracted into zsh/zshenv.secrets.template"
        echo "  and work/work-env.zsh were curated by hand from this machine's ~/.zshenv."
        echo "  Copy zsh/zshenv.secrets.template -> ~/.zshenv.secrets, fill in real values,"
        echo "  chmod 600 it, then re-run without --migrate-zshenv to link ~/.zshenv."
        echo "install.sh: env diff (old vs. what zsh/zshenv + templates cover) — review before proceeding:"
        grep -oE '^[[:space:]]*(export[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*=' "$BACKUP_DIR/.zshenv" \
          | tr -d ' ' | sed 's/^export//; s/=$//' | sort -u
      fi
    fi
  else
    echo "install.sh: ~/.zshenv already exists, leaving it alone (use --migrate-zshenv to split it)"
  fi
else
  link zsh/zshenv ~/.zshenv
fi

### Core links
link zsh/zshrc                                 ~/.zshrc
for f in "$REPO_DIR"/zsh/zshrc.d/*.zsh; do
  link "zsh/zshrc.d/$(basename "$f")"          ~/.zshrc.d/"$(basename "$f")"
done
link zsh/omz-custom/aliases-core.zsh           ~/.oh-my-zsh/custom/aliases-core.zsh
link zsh/omz-custom/themes/agnoster.zsh-theme  ~/.oh-my-zsh/custom/themes/agnoster.zsh-theme
link zsh/dircolors                             ~/.dircolors
link zsh/zfunc                                 ~/.zfunc

link git/gitconfig                             ~/.gitconfig
link git/gitmessage                            ~/.gitmessage
link git/delta-themes.gitconfig                ~/delta-themes.gitconfig
link git/ignore                                ~/.config/git/ignore

link bat/config                                ~/.config/bat/config
link ripgrep/ripgreprc                         ~/.config/ripgrep/ripgreprc
link fd/ignore                                 ~/.config/fd/ignore
link lsd/config.yaml                           ~/.config/lsd/config.yaml
link tmux/tmux.conf                            ~/.tmux.conf
link vim/vimrc                                 ~/.vimrc

run git -C "$REPO_DIR" config core.hooksPath "$REPO_DIR/git/hooks" 2>/dev/null || true

### Work module
if $WITH_WORK; then
  echo "== linking work module =="
  link work/work-env.zsh    ~/.work-env.zsh
  link work/utils.sh        ~/utils.sh
  link work/aliases-work.zsh ~/.oh-my-zsh/custom/aliases-work.zsh
  link work/gitconfig-work  ~/.gitconfig-work
else
  echo "install.sh: skipping work module (pass --with-work to include it)"
fi

echo "== done =="
[[ -d "$BACKUP_DIR" ]] && ! $DRY_RUN && echo "Originals backed up to: $BACKUP_DIR"
echo "Start a new shell (or 'exec zsh') to pick up the changes."
