#!/usr/bin/env bash
# Installs the binaries these dotfiles assume, on a Debian/Ubuntu box (adjust the
# apt list if you're on a different distro). Run manually, not auto-invoked by install.sh.
set -euo pipefail

sudo apt-get update
sudo apt-get install -y zsh git tmux fzf ripgrep bat fd-find

# lsd, delta, zoxide, gitleaks aren't always current enough in apt; prefer the
# distro package if present, otherwise fall back to the upstream .deb/binary release.
for pkg in lsd git-delta zoxide; do
  sudo apt-get install -y "$pkg" 2>/dev/null || echo "bootstrap: '$pkg' not in apt, install manually from its GitHub releases"
done

command -v gitleaks >/dev/null || echo "bootstrap: gitleaks not found — install from https://github.com/gitleaks/gitleaks/releases for the pre-commit secret scan"

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

echo "bootstrap-linux: done. Re-run 'command -v lsd delta zoxide gitleaks' to confirm what's still missing."
