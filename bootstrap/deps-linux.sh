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

# sudo is optional, not assumed: on a box without passwordless sudo `sudo apt-get
# update` would die under set -e on its very first command, so the whole apt block is
# skipped rather than attempted when the probe fails. install_release below (needs no
# privileges — installs to ~/.local/bin) is exactly the fallback for that case.
if sudo -n true 2>/dev/null; then
  sudo apt-get update
  sudo apt-get install -y zsh git tmux ripgrep bat fd-find xsel xclip

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
else
  echo "bootstrap: no passwordless sudo, skipping apt — falling back to GitHub releases for everything"
fi

# probe()/install_release() live in lib-tools.sh, shared with deps-macos.sh and
# install.sh's tool inventory — same probes everywhere, no drift between what the
# pre-install inventory checks and what actually gets fetched here.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-tools.sh"

# WSL only: fresh WSL Ubuntu images ship no generated locales, but zsh/zshenv exports
# LANG=en_AU.UTF-8 — GTK apps (Terminator) then warn "Locale not supported by C library".
if is_wsl && sudo -n true 2>/dev/null && ! locale -a 2>/dev/null | grep -qiE '^en_AU\.utf-?8$'; then
  sudo sed -i 's/^# *\(en_AU\.UTF-8 UTF-8\)/\1/' /etc/locale.gen
  sudo locale-gen en_AU.UTF-8
fi

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
