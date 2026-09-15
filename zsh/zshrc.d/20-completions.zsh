# usage: _zcache <name> <cmd...>  — evals cached output, regenerates if binary is newer
_zcache() {
  local name=$1; shift
  local f=~/.cache/zsh/$name.zsh bin=${commands[$1]}
  [[ -n $bin ]] || return
  [[ -s $f && $f -nt $bin ]] || { mkdir -p ~/.cache/zsh; "$@" >| $f }
  source $f
}

# Completion styling
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' menu no
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'lsd --color=always --icon=always --group-directories-first $realpath'
zstyle ':fzf-tab:complete:__zoxide_z:*' fzf-preview 'lsd --color=always --icon=always --group-directories-first $realpath'

_zcache uv uv generate-shell-completion zsh
_zcache uvx uvx --generate-shell-completion zsh

_jiratui_completion() {
    local -a completions
    local -a completions_with_descriptions
    local -a response
    (( ! $+commands )) && return 1

    response=("${(@f)$(env COMP_WORDS="${words[*]}" COMP_CWORD=$((CURRENT-1)) _JIRATUI_COMPLETE=zsh_complete jiratui)}")

    for type key descr in ${response}; do
        if [[ "$type" == "plain" ]]; then
            if [[ "$descr" == "_" ]]; then
                completions+=("$key")
            else
                completions_with_descriptions+=("$key":"$descr")
            fi
        elif [[ "$type" == "dir" ]]; then
            _path_files -/
        elif [[ "$type" == "file" ]]; then
            _path_files -f
        fi
    done

    if [ -n "$completions_with_descriptions" ]; then
        _describe -V unsorted completions_with_descriptions -U
    fi

    if [ -n "$completions" ]; then
        compadd -U -V unsorted -a completions
    fi
}

if [[ $zsh_eval_context[-1] == loadautofunc ]]; then
    # autoload from fpath, call function directly
    _jiratui_completion "$@"
else
    # eval/source/. command, register function for later
    compdef _jiratui_completion jiratui
fi

# alias-finder
zstyle ':omz:plugins:alias-finder' autoload yes # disabled by default
zstyle ':omz:plugins:alias-finder' longer yes # disabled by default
zstyle ':omz:plugins:alias-finder' exact yes # disabled by default
zstyle ':omz:plugins:alias-finder' cheaper yes # disabled by default

# procs
if command -v procs >/dev/null; then
  _procs_f=~/.cache/zsh/procs.zsh
  [[ -s $_procs_f && $_procs_f -nt ${commands[procs]} ]] || {
    mkdir -p ~/.cache/zsh
    procs --completion-out zsh | command sed '$s/^_procs "\$@"$/compdef _procs procs/' >| $_procs_f
  }
  source $_procs_f
  unset _procs_f
fi
