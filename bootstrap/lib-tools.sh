#!/usr/bin/env bash
# Shared capability-probe + best-effort-release-fetch helpers. Sourced by
# deps-linux.sh, deps-macos.sh, and install.sh — not run directly.
#
# Philosophy (see deps-linux.sh's own header for the full rationale): never compare
# version numbers. Check whether the installed binary supports the flag this repo
# actually needs, and only fetch a replacement if that probe fails.

# probe TOOL — does the installed binary support the flag this config actually needs?
#
# Each "X --help | grep -q Y" is wrapped in ( set +o pipefail; ... ): grep -q closes its
# input the instant it finds a match, and if the producer is still writing when that
# happens it gets SIGPIPE'd — which, under pipefail, makes the *pipeline's* exit status
# reflect that non-zero SIGPIPE death rather than grep's success. --help output is small
# enough that this rarely fires in practice, but install.sh's fc-list probe hit it
# reproducibly (900+ lines), so every probe here is hardened the same way.
probe() {
  case "$1" in
    bat)    command -v bat    >/dev/null 2>&1 && ( set +o pipefail; bat --help    2>/dev/null | grep -q -- '--strip-ansi' ) ;;
    fd)     command -v fd     >/dev/null 2>&1 && ( set +o pipefail; fd  --help    2>/dev/null | grep -q -- '--strip-cwd-prefix' ) ;;
    lsd)    command -v lsd    >/dev/null 2>&1 && ( set +o pipefail; lsd --help    2>/dev/null | grep -q -- '--git' ) ;;
    delta)  command -v delta  >/dev/null 2>&1 && ( set +o pipefail; delta --help  2>/dev/null | grep -q -- '--grep-output-type' ) ;;
    zoxide) command -v zoxide >/dev/null 2>&1 && zoxide init zsh >/dev/null 2>&1 ;;
    procs)  command -v procs  >/dev/null 2>&1 && ( procs --gen-completion-out zsh >/dev/null 2>&1 || procs --completion-out zsh >/dev/null 2>&1 ) ;;
    fzf)    command -v fzf    >/dev/null 2>&1 && fzf --zsh >/dev/null 2>&1 ;;
  esac
}

# tool_version TOOL — best-effort one-line version string for the report/inventory.
# Never fails the caller: prints "-" if the tool is missing or neither flag has output.
# tmux has no --version (it dumps a usage line instead) — -V is its actual flag.
tool_version() {
  local t="$1" out
  command -v "$t" >/dev/null 2>&1 || { echo "-"; return; }
  if [[ "$t" == tmux ]]; then
    out=$(tmux -V 2>&1 | head -1) || true
  else
    out=$("$t" --version 2>&1 | head -1) || true
  fi
  [[ -n "$out" ]] && echo "$out" || echo "-"
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
