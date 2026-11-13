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

  # fzf-flags is now a single wildcard style (':fzf-tab:complete:*'), computed
  # with zstyle -e since the pinned-line count depends on $words (the command
  # being completed) — fzf-tab-help itself is stubbed here so the lookup
  # doesn't shell out. A git-specific context must still match the wildcard.
  (
    function fzf-tab-help { [[ $1 == usage-lines ]] && print 1 }
    local -a words=(git)
    local -a flags
    zstyle -a ':fzf-tab:complete:git:' fzf-flags flags || exit 1
    [[ ${(j: :)flags} == *' Completion (Tab) '* ]] || exit 1
    [[ ${(j: :)flags} == *' Usage '* ]] || exit 1
    [[ ${(j: :)flags} == *'~1'* ]] || exit 1
  ) || return 1

  [[ $BAT_STYLE == full && $MANPAGER == "sh -c 'col -bx | bat -lman --strip-ansi=auto'" ]] || return 1
  [[ ${aliases[bat]} != *--style* && ${functions[_bat_help_accept_line]} != *--style* ]] || return 1
  # col -bx strips macOS man's backspace-overstrike bold/underline before bat
  # renders a `cmd --help` that shelled out to man (e.g. `git commit --help`).
  [[ ${functions[_bat_help_accept_line]} == *'col -bx |'* ]] || return 1

  # Execute the configured preview with a stubbed fzf-tab-help: paths must stay
  # one argument, and a non-path candidate must never use an inherited stale
  # realpath. fzf-tab-help is stubbed (not the real script) because this
  # exercises the zstyle wiring/realdir branch, not the script's own logic —
  # that's covered separately below against the real script.
  (
    local fixture=$(mktemp -d) preview output context
    trap 'command rm -rf -- "$fixture"' EXIT
    mkdir "$fixture/a directory"
    print -r -- example > "$fixture/a file"
    function lsd { printf 'directory:%s' "${@[-1]}"; }
    function fzf-preview.sh { (( $# == 1 )) || return 1; printf 'file:%s' "$1"; }
    function file { printf 'metadata:%s' "${@[-1]}"; }
    function fzf-tab-help {
      [[ $1 == usage ]] && print USAGE
      [[ $1 == block ]] && print "block:$3"
    }
    local word=plain desc='x -- fixture desc'
    local -A ctxt=(realdir "$fixture/")
    local realpath
    local -a words=(cmd)
    for context in vim cd cp git; do
      zstyle -s ":fzf-tab:complete:$context:" fzf-preview preview || exit 1
      realpath="$fixture/a directory"
      [[ $(eval "$preview") == "USAGE"$'\n'"directory:$realpath" ]] || exit 1
      realpath="$fixture/a file"
      [[ $(eval "$preview") == "USAGE"$'\n'"file:$realpath" ]] || exit 1
      ctxt=()
      output=$(eval "$preview")
      [[ $output != *"$realpath"* ]] || exit 1
      [[ $output == *'fixture desc'* ]] || exit 1
      ctxt=(realdir "$fixture/")
    done
  ) || return 1

  # Real fzf-tab-help script, end to end: an obsidian stub on PATH records argv
  # so the help-form zstyle override (':fzf-tab-help:obsidian' help-form 'help
  # %s', set in zsh/zshrc) can be proven — obsidian-cli runs a subcommand's
  # ACTION instead of printing help when given "<sub> --help", so a focused
  # "aliases" candidate must ask via "help aliases", never "aliases --help".
  (
    local script_dir="${${(%):-%x}:A:h}"
    local fth="$script_dir/../zsh/bin/fzf-tab-help"
    [[ -x $fth ]] || exit 1
    local bindir=$(mktemp -d) cachedir=$(mktemp -d)
    trap 'command rm -rf -- "$bindir" "$cachedir"' EXIT
    cat >"$bindir/obsidian" <<'STUB'
#!/usr/bin/env zsh
print -r -- "$@" >> "$0:h/argv.log"
# Real obsidian-cli prints help fine for ITS OWN top-level --help/-h; the
# danger is only "<sub> --help", which it treats as running <sub>'s action.
if [[ $1 == help || $1 == --help || $1 == -h ]]; then
  cat <<'EOF'
Usage: obsidian [options] command

Options:
  --vault <name>   Vault to operate on

Commands:
  aliases   List aliases in the vault
EOF
else
  print "DANGER: ran default action for: $*"
fi
STUB
    chmod +x "$bindir/obsidian"
    export PATH="$bindir:$PATH"
    export FZF_TAB_HELP_CACHE_DIR="$cachedir"

    # zsh -f, not a plain "$fth" invocation: the script's own #!/usr/bin/env
    # zsh shebang always sources the REAL (live, non-repo) ~/.zshenv on every
    # invocation — and on this box that file's laptop-only PATH lines are a
    # wholesale overwrite, not an append, which silently drops $bindir and
    # makes obsidian "not found" (reproduced). -f skips rc files entirely
    # while still inheriting this subshell's exported PATH/env — irrelevant
    # to production (where the real ~/.zshenv's PATH already contains
    # wherever the real binaries live), but required for a deterministic test.
    local usage_out usage_lines_count usage_line_count
    usage_out=$(zsh -f "$fth" usage -- obsidian) || exit 1
    usage_line_count=$(print -rl -- "${(f)usage_out}" | wc -l | tr -d ' ')
    usage_lines_count=$(zsh -f "$fth" usage-lines -- obsidian) || exit 1
    [[ $usage_line_count == "$usage_lines_count" ]] || exit 1

    zsh -f "$fth" block aliases 'aliases -- List aliases in the vault' -- obsidian >/dev/null || exit 1
    [[ -f "$bindir/argv.log" ]] || exit 1
    grep -qxF 'help aliases' "$bindir/argv.log" || exit 1
    grep -qF 'aliases --help' "$bindir/argv.log" && exit 1
    grep -qF 'DANGER' "$bindir/argv.log" && exit 1
    exit 0
  ) || return 1

  print 'Shell shortcut checks passed'
}
