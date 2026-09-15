#!/usr/bin/env bash
# Installs the binaries these dotfiles assume, via Homebrew. Run manually, not
# auto-invoked by install.sh.
set -euo pipefail

command -v brew >/dev/null || {
  echo "bootstrap-macos: Homebrew not found. Install it first: https://brew.sh" >&2
  exit 1
}

brew install zsh git tmux fzf ripgrep bat fd lsd git-delta zoxide gitleaks coreutils

echo "bootstrap-macos: done. 'coreutils' provides gdircolors etc — zsh/zshenv already"
echo "prepends the brew gnubin shim to PATH so GNU tools shadow the BSD ones."
