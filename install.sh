#!/usr/bin/env bash
# Symlinks this repo's config into $HOME. Idempotent, safe to re-run.
# Run './install.sh --help' for options.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS="$(uname -s)"
BACKUP_DIR="$HOME/.zsh-config-backup/$(date -u +%Y%m%dT%H%M%SZ)"
DRY_RUN=false
WITH_WORK=false
FORCE=false
MIGRATE_ZSHENV=false
DISPLAY_HOST=false
TERMINATOR_FONT="JetBrainsMono Nerd Font Mono 11"
SET_TERMINATOR_FONT=false

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
  --display-host     Show "user@host" in the prompt (hidden by default — the
                     agnoster theme already renders it, this just un-hides
                     it). Useful on a fleet of similarly-named shared boxes.
                     Writes ZSH_CONFIG_DISPLAY_HOST=1 into ~/.zshrc.local.
  --terminator-font[=SPEC]
                     Write a Terminator profile selecting a Nerd Font (default
                     "JetBrainsMono Nerd Font Mono 11", or pass SPEC for a
                     different family/size) so glyphs don't render as boxes.
                     Only writes ~/.config/terminator/config if it doesn't
                     already exist; otherwise prints a manual pointer.

Note: the login shell is switched to zsh automatically (if zsh is installed
and listed in /etc/shells) unless it already is zsh — no flag needed.

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
    --display-host) DISPLAY_HOST=true ;;
    --terminator-font) SET_TERMINATOR_FONT=true ;;
    --terminator-font=*) SET_TERMINATOR_FONT=true; TERMINATOR_FONT="${arg#--terminator-font=}" ;;
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

# install_nerd_font — the agnoster theme needs Powerline glyphs (U+E0A0/U+E0B0) and
# lsd --icon=always needs the broader Nerd Font icon set; neither renders without one
# selected in whatever terminal is actually drawing the glyphs. Found the hard way on a
# box with no Nerd Font installed at all. Unconditional (not gated behind a flag) so
# every future install gets this without anyone having to remember to ask for it.
install_nerd_font() {
  # macOS has no fontconfig, so fc-list can't be used to probe for an existing install —
  # check the same directories the Darwin install branch below writes into instead. Glob
  # must match that branch's `JetBrainsMonoNerdFontMono-*.ttf` pattern or this breaks again.
  #
  # ( set +o pipefail; ... ) matters on Linux: fc-list's ~900 lines of output exceed one
  # pipe buffer, so grep -q (which closes its input the instant it finds a match) SIGPIPEs
  # fc-list mid-write. Under pipefail that makes the *pipeline's* exit status reflect
  # fc-list's SIGPIPE death, not grep's success — a false "not installed" every time,
  # caught by testing this against the font actually already on this workstation.
  if [[ "$OS" == Darwin ]]; then
    if compgen -G "$HOME/Library/Fonts/JetBrainsMonoNerdFontMono-*.ttf" >/dev/null \
    || compgen -G "/Library/Fonts/JetBrainsMonoNerdFontMono-*.ttf" >/dev/null; then
      echo "install.sh: JetBrainsMono Nerd Font already installed, skipping"
      return 0
    fi
  elif ( set +o pipefail; fc-list 2>/dev/null | grep -qi "JetBrainsMono Nerd Font Mono" ); then
    echo "install.sh: JetBrainsMono Nerd Font already installed, skipping"
    return 0
  fi
  if ! command -v python3 >/dev/null; then
    echo "install.sh: python3 not found, can't resolve the Nerd Font release — install manually from https://github.com/ryanoasis/nerd-fonts/releases (JetBrainsMono)" >&2
    return 0
  fi
  local url
  url=$(python3 - <<'PY'
import json, urllib.request
req = urllib.request.Request(
    "https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest",
    headers={"User-Agent": "zsh-config-bootstrap"},
)
data = json.load(urllib.request.urlopen(req, timeout=15))
for a in data["assets"]:
    if a["name"] == "JetBrainsMono.tar.xz":
        print(a["browser_download_url"])
        break
PY
  )
  if [[ -z "$url" ]]; then
    echo "install.sh: couldn't resolve the JetBrainsMono Nerd Font release — install manually from https://github.com/ryanoasis/nerd-fonts/releases" >&2
    return 0
  fi
  if $DRY_RUN; then
    echo "+ download and install JetBrainsMono Nerd Font from $url"
    return 0
  fi
  echo "install.sh: fetching JetBrainsMono Nerd Font..."
  local tmp; tmp=$(mktemp -d)
  curl -fsSL "$url" -o "$tmp/font.tar.xz"
  mkdir -p "$tmp/extract"
  tar -xf "$tmp/font.tar.xz" -C "$tmp/extract"
  # Only the fixed-width "Mono" variant (icon glyphs stay a fixed cell width, which is
  # what a terminal needs) — and not the ligature-free "NL" family, which is a separate
  # font name entirely.
  if [[ "$OS" == Darwin ]]; then
    mkdir -p "$HOME/Library/Fonts"
    find "$tmp/extract" -maxdepth 1 -name 'JetBrainsMonoNerdFontMono-*.ttf' -exec cp {} "$HOME/Library/Fonts/" \;
    echo "install.sh: installed JetBrainsMono Nerd Font -> ~/Library/Fonts (macOS picks it up automatically)"
  elif command -v fc-cache >/dev/null; then
    mkdir -p "$HOME/.local/share/fonts/NerdFonts/JetBrainsMono"
    find "$tmp/extract" -maxdepth 1 -name 'JetBrainsMonoNerdFontMono-*.ttf' -exec cp {} "$HOME/.local/share/fonts/NerdFonts/JetBrainsMono/" \;
    fc-cache -f "$HOME/.local/share/fonts" >/dev/null
    echo "install.sh: installed JetBrainsMono Nerd Font -> ~/.local/share/fonts/NerdFonts/JetBrainsMono"
  else
    echo "install.sh: no fontconfig and not macOS — install a Nerd Font manually for your terminal" >&2
  fi
  rm -rf "$tmp"
}

# ensure_zsh_shell — a repo whose entire job is a zsh config should leave you in zsh.
# Unconditional (not gated behind a flag), but every step is a check, so it's a no-op
# on a box that's already correct and never makes anything worse. sudo is optional,
# not assumed: each privileged path probes `sudo -n true` first and falls back to a
# TTY prompt or a manual pointer, so this behaves the same whether or not the box
# happens to have passwordless sudo at install time.
ensure_zsh_shell() {
  local current_shell
  if [[ "$OS" == Darwin ]]; then
    # getent doesn't exist on macOS. dscl's UserShell value can wrap onto a second
    # "line" of output for some odd usernames — tr collapses that before awk picks
    # the value field. `|| true`: pipefail (set -euo pipefail up top) would otherwise
    # abort this whole script if the UserShell key is ever missing.
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
  if ! grep -qxF "$zsh_path" /etc/shells 2>/dev/null; then
    # Never auto-append: this is the one system-file mutation install.sh could make
    # that isn't reversible via $BACKUP_DIR. On macOS, Homebrew zsh isn't listed in
    # /etc/shells by default (the bundled /bin/zsh is) — print the exact fix instead
    # of guessing which one the user wants.
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

echo "== zsh-config install ($REPO_DIR) =="
$DRY_RUN && echo "(dry run — no changes will be made)"

install_nerd_font

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
link ghostty/config                            ~/.config/ghostty/config
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

### --display-host: un-hide the theme's own "user@host" segment (see 30-prompt.zsh)
### via the existing ~/.zshrc.local per-machine escape hatch. Idempotent: never
### duplicates the line, never touches anything else that may already be there.
if $DISPLAY_HOST; then
  if ! grep -qs '^export ZSH_CONFIG_DISPLAY_HOST=' ~/.zshrc.local 2>/dev/null; then
    run bash -c 'printf "export ZSH_CONFIG_DISPLAY_HOST=1\n" >> ~/.zshrc.local'
    echo "install.sh: added ZSH_CONFIG_DISPLAY_HOST=1 to ~/.zshrc.local"
  else
    echo "install.sh: ~/.zshrc.local already sets ZSH_CONFIG_DISPLAY_HOST, leaving it alone"
  fi
fi

### --terminator-font: write a minimal Terminator profile selecting a Nerd Font, only
### if no config exists yet — never rewrite a real one (ConfigObj's nested format isn't
### worth risking a bad in-place edit over; a message is safer than a corrupted config).
if $SET_TERMINATOR_FONT && [[ "$OS" == Darwin ]]; then
  echo "install.sh: --terminator-font is Linux-only (Terminator doesn't run on macOS) — skipping. See ghostty/config for the macOS equivalent." >&2
elif $SET_TERMINATOR_FONT; then
  terminator_config="$HOME/.config/terminator/config"
  if [[ -e "$terminator_config" ]]; then
    if grep -qs '^[[:space:]]*font[[:space:]]*=' "$terminator_config"; then
      echo "install.sh: $terminator_config already exists and sets a font, leaving it alone"
    else
      echo "install.sh: $terminator_config already exists — add manually under [profiles][[default]]: use_system_font = False / font = $TERMINATOR_FONT"
    fi
  elif $DRY_RUN; then
    echo "+ write $terminator_config selecting font \"$TERMINATOR_FONT\""
  else
    run mkdir -p "$(dirname "$terminator_config")"
    cat >"$terminator_config" <<EOF
[profiles]
  [[default]]
    use_system_font = False
    font = $TERMINATOR_FONT
EOF
    echo "install.sh: wrote $terminator_config (font: $TERMINATOR_FONT) — restart Terminator to pick it up"
  fi
fi

ensure_zsh_shell

echo "== done =="
[[ -d "$BACKUP_DIR" ]] && ! $DRY_RUN && echo "Originals backed up to: $BACKUP_DIR"
echo "Start a new shell (or 'exec zsh') to pick up the changes."
