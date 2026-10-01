#!/usr/bin/env zsh
# Run after installing: zsh -ic 'source tests/shell-shortcuts.zsh'
# Also works in an interactive shell that sourced a candidate configuration.
() {
  local keymap key widget
  for keymap in emacs viins; do
    if (( $+commands[atuin] )); then
      widget=atuin-search
      [[ $keymap == viins ]] && widget=atuin-search-viins
      [[ $(bindkey -M "$keymap" '^R') == *" $widget" ]] || return 1
    else
      [[ $(bindkey -M "$keymap" '^R') == *' fzf-history-widget' ]] || return 1
    fi
    [[ $(bindkey -M "$keymap" '^T') == *' fzf-file-widget' ]] || return 1
    [[ $(bindkey -M "$keymap" '^[c') == *' fzf-cd-widget' ]] || return 1
    [[ $(bindkey -M "$keymap" '^I') == *' fzf-tab-complete' ]] || return 1
  done
  for keymap in emacs viins vicmd; do
    for key in '^[[A' '^[OA'; do
      [[ $(bindkey -M "$keymap" "$key") == *' up-line-or-history' ]] || return 1
    done
  done
  [[ $FZF_CTRL_T_OPTS == *' Files (Ctrl+T) '* ]] || return 1
  [[ $FZF_ALT_C_OPTS == *' Directories (Alt+C) '* ]] || return 1
  [[ $FZF_CTRL_R_OPTS == *' History (Ctrl+R) '* ]] || return 1
  local -a flags
  zstyle -a ':fzf-tab:complete:git:' fzf-flags flags || return 1
  [[ ${(j: :)flags} == *' Completion (Tab) '* ]] || return 1
  [[ $BAT_STYLE == full && $MANPAGER == 'bat -lman --strip-ansi=auto' ]] || return 1
  [[ ${aliases[bat]} != *--style* && ${functions[_bat_help_accept_line]} != *--style* ]] || return 1

  # Execute the configured preview/actions with stubs: paths must stay one argument,
  # and a non-path candidate must never use an inherited stale realpath.
  (
    local fixture=$(mktemp -d) preview binding action output context
    trap 'command rm -rf -- "$fixture"' EXIT
    mkdir "$fixture/a directory"
    print -r -- example > "$fixture/a file"
    function lsd { printf 'directory:%s' "${@[-1]}"; }
    function fzf-preview.sh { (( $# == 1 )) || return 1; printf 'file:%s' "$1"; }
    function file { printf 'metadata:%s' "${@[-1]}"; }
    local -A ctxt=(realdir "$fixture/")
    local realpath
    local -a bindings
    for context in vim cd cp git; do
      zstyle -s ":fzf-tab:complete:$context:" fzf-preview preview || exit 1
      realpath="$fixture/a directory"
      [[ $(eval "$preview") == "directory:$realpath" ]] || exit 1
      realpath="$fixture/a file"
      [[ $(eval "$preview") == "file:$realpath" ]] || exit 1
      ctxt=()
      [[ -z $(eval "$preview") ]] || exit 1
      ctxt=(realdir "$fixture/")
    done
    zstyle -a ':fzf-tab:complete:vim:' fzf-bindings bindings || exit 1
    (( $#bindings == 1 )) || exit 1
    local -a actions=("${(@s:@:)bindings[1]}")
    for binding in "$actions[2]" "$actions[4]"; do
      [[ $binding == *'{_FTB_INIT_}'* ]] || exit 1
      action=${binding#*\{_FTB_INIT_\}}
      output=$(eval "$action")
      [[ $output == *"$realpath"* ]] || exit 1
      ctxt=()
      [[ $(eval "$action") == ' ' ]] || exit 1
      ctxt=(realdir "$fixture/")
    done
  ) || return 1
  print 'Shell shortcut checks passed'
}
