#!/usr/bin/env bash
# Installs the binaries these dotfiles assume, on a Debian/Ubuntu box (adjust the
# apt list if you're on a different distro). Run manually, not auto-invoked by install.sh.
#
# apt on an older LTS (e.g. Ubuntu 20.04) either lacks lsd/delta/zoxide entirely or ships
# a bat/fd too old for a flag this config actually uses. Rather than compare version
# numbers, each tool is checked with a capability probe — does the flag this repo needs
# exist — and only fetched from its GitHub releases if that probe fails. Idempotent:
# already-capable tools are left alone.
set -euo pipefail

sudo apt-get update
sudo apt-get install -y zsh git tmux fzf ripgrep bat fd-find

# Ubuntu's fd binary is fd-find/fdfind; alias it if fd isn't already on PATH.
if ! command -v fd >/dev/null && command -v fdfind >/dev/null; then
  mkdir -p "$HOME/.local/bin"
  ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
fi

# Ubuntu's bat binary is batcat; same treatment.
if ! command -v bat >/dev/null && command -v batcat >/dev/null; then
  mkdir -p "$HOME/.local/bin"
  ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"
fi

# apt-get install failing for a package that isn't in this distro's archive (lsd,
# git-delta, zoxide on 20.04) is expected — don't let set -e kill the script over it.
for pkg in lsd git-delta zoxide; do
  sudo apt-get install -y "$pkg" 2>/dev/null || true
done

# probe TOOL: does the installed binary support the flag this config actually needs?
# (not "is it new enough" — the flag is what matters, and this is what's testable.)
probe() {
  case "$1" in
    bat)    command -v bat    >/dev/null 2>&1 && bat --help    2>/dev/null | grep -q -- '--strip-ansi' ;;
    fd)     command -v fd     >/dev/null 2>&1 && fd  --help    2>/dev/null | grep -q -- '--strip-cwd-prefix' ;;
    lsd)    command -v lsd    >/dev/null 2>&1 && lsd --help    2>/dev/null | grep -q -- '--git' ;;
    delta)  command -v delta  >/dev/null 2>&1 && delta --help  2>/dev/null | grep -q -- '--grep-output-type' ;;
    zoxide) command -v zoxide >/dev/null 2>&1 && zoxide init zsh >/dev/null 2>&1 ;;
  esac
}

# install_release TOOL REPO BINNAME — fetch the latest linux-x86_64 release tarball,
# find BINNAME inside it (wherever the archive's internal layout puts it), install to
# ~/.local/bin. Skipped entirely if `probe TOOL` already passes.
install_release() {
  local tool="$1" repo="$2" binname="$3"
  if probe "$tool"; then
    echo "bootstrap: $tool already satisfies the required capability, skipping"
    return 0
  fi
  if ! command -v python3 >/dev/null; then
    echo "bootstrap: python3 not found, can't resolve $tool's release asset — install $tool manually from https://github.com/$repo/releases" >&2
    return 1
  fi
  echo "bootstrap: fetching $tool from github.com/$repo releases..."
  local tmp url
  tmp=$(mktemp -d)
  url=$(python3 - "$repo" <<'PY'
import json, sys, urllib.request
repo = sys.argv[1]
req = urllib.request.Request(
    f"https://api.github.com/repos/{repo}/releases/latest",
    headers={"User-Agent": "zsh-config-bootstrap"},
)
data = json.load(urllib.request.urlopen(req, timeout=15))
names = [a["browser_download_url"] for a in data["assets"]
         if a["name"].endswith("x86_64-unknown-linux-gnu.tar.gz")]
if not names:
    names = [a["browser_download_url"] for a in data["assets"]
             if a["name"].endswith("x86_64-unknown-linux-musl.tar.gz")]
print(names[0] if names else "")
PY
  )
  if [[ -z "$url" ]]; then
    echo "bootstrap: couldn't resolve a linux-x86_64 release asset for $tool — install manually from https://github.com/$repo/releases" >&2
    rm -rf "$tmp"
    return 1
  fi
  curl -fsSL "$url" -o "$tmp/asset.tar.gz"
  tar -xzf "$tmp/asset.tar.gz" -C "$tmp"
  local found
  found=$(find "$tmp" -type f -name "$binname" | head -1)
  if [[ -z "$found" ]]; then
    echo "bootstrap: downloaded $tool but couldn't find a '$binname' binary inside the archive" >&2
    rm -rf "$tmp"
    return 1
  fi
  mkdir -p "$HOME/.local/bin"
  install -m 755 "$found" "$HOME/.local/bin/$binname"
  rm -rf "$tmp"
  echo "bootstrap: installed $tool -> $HOME/.local/bin/$binname"
}

install_release bat    sharkdp/bat       bat
install_release fd     sharkdp/fd        fd
install_release lsd    lsd-rs/lsd        lsd
install_release delta  dandavison/delta  delta
install_release zoxide ajeetdsouza/zoxide zoxide

command -v gitleaks >/dev/null || echo "bootstrap: gitleaks not found — install from https://github.com/gitleaks/gitleaks/releases for the pre-commit secret scan"

echo "bootstrap-linux: done. Final capability check:"
for t in bat fd lsd delta zoxide; do
  if probe "$t"; then echo "  $t: OK"; else echo "  $t: MISSING / still failing its probe"; fi
done
