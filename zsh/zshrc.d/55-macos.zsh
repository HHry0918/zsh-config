# Re-promote Homebrew's GNU coreutils (gnubin) above the system BSD tools — undoes
# damage done between .zshenv and here on macOS login shells.
#
# Ghostty (like Terminal.app) starts every new window as a LOGIN shell on macOS, so the
# startup order is .zshenv -> /etc/zprofile -> .zprofile -> .zshrc -> zshrc.d/*.zsh
# (this file). /etc/zprofile runs Apple's `path_helper`, which rewrites PATH to put
# /usr/bin:/bin:/usr/sbin:/sbin first — *after* zsh/zshenv already prepended the gnubin
# shim, silently demoting it back behind the BSD `sed`, `dircolors`, etc. these dotfiles
# assume are GNU. This runs after 50-tools.zsh on purpose: that file's `brew shellenv`
# eval also rewrites PATH (re-prepending $prefix/bin/sbin), so gnubin must be
# re-promoted *after* it, not before.
#
# Re-running the exact same prepend as zsh/zshenv is safe and not a duplicate: PATH has
# `typeset -U` set there, which keeps only the leftmost occurrence of a path already
# present — so this promotes gnubin back to the front rather than adding a second copy.
#
# Known gap: a *non-interactive* login shell (e.g. some remote-exec paths) skips
# zshrc.d entirely, so this fix doesn't apply there. `ssh host cmd` is unaffected since
# it only runs .zshenv and never triggers path_helper in the first place.
if [[ "$OSTYPE" == darwin* ]]; then
  for _brew_prefix in /opt/homebrew /usr/local; do
    if [[ -x "$_brew_prefix/bin/brew" ]]; then
      for _gnubin in "$_brew_prefix"/opt/*/libexec/gnubin(N); do
        [[ -d "$_gnubin" ]] && export PATH="$_gnubin:$PATH"
      done
      break
    fi
  done
  unset _brew_prefix _gnubin
fi
