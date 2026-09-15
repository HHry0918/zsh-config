command -v zoxide >/dev/null && eval "$(zoxide init --cmd cd zsh)"

command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"
_zcache pyenv-init pyenv init - --no-rehash zsh
_zcache pyenv-virtualenv-init pyenv virtualenv-init - zsh

# Change dircolors. GNU-only; macOS coreutils installs it as gdircolors unless the
# gnubin shim in zsh/zshenv already put GNU coreutils first on PATH.
if command -v dircolors >/dev/null; then
  eval "$(dircolors ~/.dircolors)"
elif command -v gdircolors >/dev/null; then
  eval "$(gdircolors ~/.dircolors)"
fi

# nvm: static PATH to the default node version (fast), lazy-load nvm.sh itself on first `nvm` use.
if [[ -n $NVM_DIR ]]; then
  _nvm_default_alias=$(<"$NVM_DIR/alias/default" 2>/dev/null)
  if [[ -d "$NVM_DIR/versions/node/$_nvm_default_alias" ]]; then
    _nvm_default_version=$_nvm_default_alias
  else
    _nvm_default_version=$(ls "$NVM_DIR/versions/node" 2>/dev/null | sort -V | tail -1)
  fi
  [[ -n $_nvm_default_version ]] && PATH="$NVM_DIR/versions/node/$_nvm_default_version/bin:$PATH"
  unset _nvm_default_alias _nvm_default_version

  nvm() {
    unfunction nvm
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
    nvm "$@"
  }
fi

# bun completions
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

command -v claude >/dev/null && alias claude-raw="$(command -v claude)"
alias claude-headroom="headroom wrap claude --1m"

# claude-mem worker: resolve the installed version rather than hardcoding it, since the
# plugin cache path is version-pinned and bumps on update.
_claude_mem_worker=("$HOME"/.claude/plugins/cache/thedotmack/claude-mem/*/scripts/worker-service.cjs(N))
[[ -n $_claude_mem_worker[1] ]] && alias claude-mem="$HOME/.bun/bin/bun \"$_claude_mem_worker[1]\""
unset _claude_mem_worker

find-child-mount() {
  findmnt -rn -o TARGET | awk -v p="$PWD" 'index($1, p "/") == 1 { sub("^" p "/", "", $1); print $1 }' | xargs
}

# Nix, if installed
[ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ] && . "$HOME/.nix-profile/etc/profile.d/nix.sh"

# Homebrew: linuxbrew, Apple Silicon, or Intel macOS — first one found wins.
for _brew in /home/linuxbrew/.linuxbrew/bin/brew /opt/homebrew/bin/brew /usr/local/bin/brew; do
  if [[ -x $_brew ]]; then
    eval "$($_brew shellenv zsh)"
    break
  fi
done
unset _brew
