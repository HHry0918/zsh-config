# Keep zsh-interactive-cd directory picker compact and preview nested paths correctly.
_zic_complete() {
  setopt localoptions nonomatch
  local l matches fzf fzf_bindings tokens base preview_base

  l=$(_zic_list_generator $@)

  if [ -z "$l" ]; then
    zle ${__zic_default_completion:-expand-or-complete}
    return
  fi

  preview_base="${(Q)@[-1]}"
  if [[ "$preview_base" != */ ]]; then
    if [[ "$preview_base" == */* ]]; then
      preview_base="$(dirname -- "$preview_base")"
      if [[ ${preview_base[-1]} != / ]]; then
        preview_base="$preview_base/"
      fi
    else
      preview_base=""
    fi
  fi

  fzf=$(FZF_TMUX_HEIGHT=40% __zic_fzf_prog)
  fzf_bindings=$(FZF_TMUX_HEIGHT=40% __zic_fzf_bindings)

  if [ $(echo $l | wc -l) -eq 1 ]; then
    matches=${(q)l}
  else
    matches=$(echo $l \
        | ZIC_PREVIEW_BASE="$preview_base" FZF_TMUX_HEIGHT=40% FZF_DEFAULT_OPTS="--height 40% \
          --reverse $FZF_DEFAULT_OPTS \
          --preview 'lsd -la --header --tree --depth 1 --color=always --icon=auto --group-directories-first --git -- \"\${ZIC_PREVIEW_BASE}\"{}' \
          --bind '${fzf_bindings}'" ${=fzf} \
        | while read -r item; do
      echo -n "${(q)item} "
    done)
  fi

  matches=${matches% }
  if [ -n "$matches" ]; then
    tokens=(${(z)LBUFFER})
    base="${(Q)@[-1]}"
    if [[ "$base" != */ ]]; then
      if [[ "$base" == */* ]]; then
        base="$(dirname -- "$base")"
        if [[ ${base[-1]} != / ]]; then
          base="$base/"
        fi
      else
        base=""
      fi
    fi
    LBUFFER="${tokens[1]} "
    if [ -n "$base" ]; then
      base="${(q)base}"
      if [ "${tokens[2][1]}" = "~" ]; then
        base="${base/#$HOME/~}"
      fi
      LBUFFER="${LBUFFER}${base}"
    fi
    LBUFFER="${LBUFFER}${matches}/"
  fi
  zle redisplay
  typeset -f zle-line-init >/dev/null && zle zle-line-init
}

# bat-help accept-line widget: pipe trailing -h/--help through bat without global aliases.
# - </dev/null matters: some CLIs (claude, node) snapshot their stdin tty's termios at
#   start and restore it on exit, which clobbers less's raw mode when they run concurrently
#   in the pipe and leaves the pager deaf to keys and wheel. No tty on stdin -> no snapshot.
# - Bare -h is left alone for tools where it means "human-readable sizes", not help.
# - Trailing whitespace/newlines (bracketed paste) are ignored when matching.
if [[ -o interactive ]]; then
  _bat_help_accept_line() {
    setopt localoptions extendedglob
    local line=${BUFFER%%[[:space:]]#}
    if [[ $line != *'| bat'* ]] && [[ $line =~ '(^|[[:space:]])(-h|--help)$' ]]; then
      local -a human_h=(ls du df free sort tree)
      local -a w=(${(z)${line##*[|;&]}})          # words of the last simple command
      while (( $#w )) && [[ $w[1] == (*=*|sudo|command|builtin|noglob|nocorrect|exec|time|env) ]]; do shift w; done
      if [[ $line == *--help ]] || (( ! $human_h[(Ie)${w[1]:t}] )); then
        BUFFER="${line} 2>&1 </dev/null | bat --language=help --style=plain"
      fi
    fi
    zle .accept-line
  }
  zle -N accept-line _bat_help_accept_line
fi
