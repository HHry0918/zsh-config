#!/usr/bin/env bash
# Installs the binaries these dotfiles assume, via Homebrew. Run manually, not
# auto-invoked by install.sh.
set -euo pipefail

command -v brew >/dev/null || {
  echo "bootstrap-macos: Homebrew not found. Install it first: https://brew.sh" >&2
  exit 1
}

brew install zsh git tmux fzf ripgrep bat fd lsd git-delta zoxide gitleaks coreutils python3

# --cask exits non-zero if the app is already installed, which set -euo pipefail above
# would otherwise turn into a hard abort — check first instead.
[[ -d /Applications/Ghostty.app ]] || brew install --cask ghostty

echo "bootstrap-macos: done. 'coreutils' provides gdircolors etc — zsh/zshenv already"
echo "prepends the brew gnubin shim to PATH so GNU tools shadow the BSD ones."
echo "bootstrap-macos: 'python3' is needed by install.sh's Nerd Font auto-install."
echo "bootstrap-macos: Ghostty ships its own Nerd Font glyphs, but VS Code/iTerm don't —"
echo "  'brew install --cask font-jetbrains-mono-nerd-font' is an alternative to letting"
echo "  install.sh download it directly."
