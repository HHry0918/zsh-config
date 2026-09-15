# fzf environment only — set before ~/.fzf.zsh is sourced in zshrc.d/10-framework.zsh.
#
# Constraint: do NOT source ~/.fzf.zsh or call `fzf --zsh` here. It's already sourced
# once in 10-framework.zsh; re-sourcing it overrides zsh-interactive-cd's Tab binding
# (see the comment above _zic_complete in 40-keybinds.zsh and the original note this
# config carried at oh-my-zsh's fzf plugin boundary). This file only exports variables,
# which fzf reads at invocation time regardless of source order.

if command -v fd >/dev/null; then
  export FZF_DEFAULT_COMMAND='fd --type f --strip-cwd-prefix --hidden --follow --exclude .git'
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  export FZF_ALT_C_COMMAND='fd --type d --strip-cwd-prefix --hidden --follow --exclude .git'
fi

export FZF_DEFAULT_OPTS="--height 40% --reverse --border"

if command -v lsd >/dev/null; then
  export FZF_CTRL_T_OPTS="--preview 'lsd -la --header --color=always --icon=always --group-directories-first {}'"
  export FZF_ALT_C_OPTS="--preview 'lsd -la --header --tree --depth 2 --color=always --icon=always --group-directories-first {}'"
fi
