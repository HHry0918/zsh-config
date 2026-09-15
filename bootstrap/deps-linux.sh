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

# This script's own job is to populate ~/.local/bin — probe it, not just the inherited
# PATH, so a non-interactive session (e.g. `ssh host cmd`, which never sources
# ~/.zshenv) doesn't report a fresh install as still missing.
export PATH="$HOME/.local/bin:$PATH"

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
#
# Each "X --help | grep -q Y" is wrapped in ( set +o pipefail; ... ): grep -q closes its
# input the instant it finds a match, and if the producer is still writing when that
# happens it gets SIGPIPE'd — which, under pipefail, makes the *pipeline's* exit status
# reflect that non-zero SIGPIPE death rather than grep's success. --help output is small
# enough that this rarely fires in practice, but install.sh's near-identical fc-list
# probe hit it reproducibly (900+ lines), so these are hardened the same way rather than
# left to depend on today's output happening to fit in one pipe buffer.
probe() {
  case "$1" in
    bat)    command -v bat    >/dev/null 2>&1 && ( set +o pipefail; bat --help    2>/dev/null | grep -q -- '--strip-ansi' ) ;;
    fd)     command -v fd     >/dev/null 2>&1 && ( set +o pipefail; fd  --help    2>/dev/null | grep -q -- '--strip-cwd-prefix' ) ;;
    lsd)    command -v lsd    >/dev/null 2>&1 && ( set +o pipefail; lsd --help    2>/dev/null | grep -q -- '--git' ) ;;
    delta)  command -v delta  >/dev/null 2>&1 && ( set +o pipefail; delta --help  2>/dev/null | grep -q -- '--grep-output-type' ) ;;
    zoxide) command -v zoxide >/dev/null 2>&1 && zoxide init zsh >/dev/null 2>&1 ;;
  esac
}

# install_release TOOL REPO BINNAME — fetch the latest linux-x86_64 release tarball,
# find BINNAME inside it (wherever the archive's internal layout puts it), install to
# ~/.local/bin. Skipped entirely if `probe TOOL` already passes.
#
# musl is tried before gnu: musl builds are statically linked and run on any glibc,
# whereas a gnu build is linked against whatever glibc the project's CI happened to use
# — which can be newer than an older LTS's, in which case the binary resolves and
# downloads fine but refuses to *run* (found the hard way: delta's gnu release needs
# glibc >= 2.32; Ubuntu 20.04 ships 2.31). So each candidate is verified by actually
# executing it, not just by successfully downloading it.
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
  local urls
  urls=$(python3 - "$repo" <<'PY'
import json, sys, urllib.request
repo = sys.argv[1]
req = urllib.request.Request(
    f"https://api.github.com/repos/{repo}/releases/latest",
    headers={"User-Agent": "zsh-config-bootstrap"},
)
data = json.load(urllib.request.urlopen(req, timeout=15))
assets = {a["name"]: a["browser_download_url"] for a in data["assets"]}
for suffix in ("x86_64-unknown-linux-musl.tar.gz", "x86_64-unknown-linux-gnu.tar.gz"):
    for name, url in assets.items():
        if name.endswith(suffix):
            print(url)
PY
  )
  if [[ -z "$urls" ]]; then
    echo "bootstrap: couldn't resolve a linux-x86_64 release asset for $tool — install manually from https://github.com/$repo/releases" >&2
    return 1
  fi
  local url tmp found
  while IFS= read -r url; do
    [[ -z "$url" ]] && continue
    tmp=$(mktemp -d)
    curl -fsSL "$url" -o "$tmp/asset.tar.gz"
    tar -xzf "$tmp/asset.tar.gz" -C "$tmp"
    found=$(find "$tmp" -type f -name "$binname" | head -1)
    if [[ -n "$found" ]] && chmod +x "$found" && "$found" --help >/dev/null 2>&1; then
      mkdir -p "$HOME/.local/bin"
      install -m 755 "$found" "$HOME/.local/bin/$binname"
      rm -rf "$tmp"
      echo "bootstrap: installed $tool ($(basename "$url")) -> $HOME/.local/bin/$binname"
      return 0
    fi
    echo "bootstrap: $(basename "$url") didn't produce a runnable $binname, trying next candidate" >&2
    rm -rf "$tmp"
  done <<<"$urls"
  echo "bootstrap: no working release asset found for $tool — install manually from https://github.com/$repo/releases" >&2
  return 1
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
