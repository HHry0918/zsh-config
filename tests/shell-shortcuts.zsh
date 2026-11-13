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

  # _fth_options_candidate: pure string check of the _describe-ready
  # "flag:desc" format, including ':' escaping in the description.
  [[ $(_fth_options_candidate --color 'a: b') == '--color:a\: b' ]] || return 1
  [[ $(_fth_options_candidate -a 'no colon here') == '-a:no colon here' ]] || return 1

  # _fth_options_wrapper's own control flow: real completer always runs;
  # heuristic flags are added/skipped per case. compadd and _describe are
  # stubbed (real _describe/_tags need live completion-widget state that
  # doesn't exist outside _main_complete — confirmed: calling it standalone
  # errors "can only be called from completion function").
  (
    typeset -ga _fth_test_matches
    compadd() { _fth_test_matches+=("${@:#-*}"); }
    _describe() {
      shift 3  # drop -t TAG 'description', leaving the array-name arg
      local -a arr; arr=("${(@P)1}")
      _fth_test_matches+=("${(@)arr%%:*}")
    }
    typeset -gA _fth_flat_completers=(stubcmd _stubcompleter)
    _stubcompleter() { compadd -- file1 file2 }
    function fzf-tab-help {
      [[ $1 == options ]] || return 1
      printf '-a\t0\tAll\n--all\t0\tAll\n-t\t1\tType\n--type\t1\tType\n--group-directories-first\t0\tGroup dirs first\n'
    }

    # Case A: bare word -> real matches AND heuristic flags.
    _fth_test_matches=()
    local -a words=(stubcmd '') ; local CURRENT=2 PREFIX='' service=stubcmd
    _fth_options_wrapper
    [[ ${_fth_test_matches[(Ie)file1]} -gt 0 ]] || return 1
    [[ ${_fth_test_matches[(Ie)-a]} -gt 0 ]] || return 1

    # Case B: mid dash-prefix -> only the real completer's matches.
    _fth_test_matches=()
    words=(stubcmd --col) ; CURRENT=2 ; PREFIX='--col'
    _fth_options_wrapper
    [[ ${_fth_test_matches[(Ie)file1]} -gt 0 ]] || return 1
    [[ ${_fth_test_matches[(Ie)-a]} -eq 0 ]] || return 1

    # Case C: mid a value-taking flag's separate-word value -> no heuristic,
    # but the real completer's own matches still apply.
    _fth_test_matches=()
    words=(stubcmd -t '') ; CURRENT=3 ; PREFIX=''
    _fth_options_wrapper
    [[ ${_fth_test_matches[(Ie)file1]} -gt 0 ]] || return 1
    [[ ${_fth_test_matches[(Ie)-a]} -eq 0 ]] || return 1

    # Case D (the regression that failed twice): aliased words, previous
    # word a NO-value flag -> heuristic flags still offered. This is the
    # exact shape `ls <TAB>` takes after alias expansion
    # (ls='lsd --group-directories-first').
    _fth_test_matches=()
    words=(stubcmd --group-directories-first '') ; CURRENT=3 ; PREFIX=''
    _fth_options_wrapper
    [[ ${_fth_test_matches[(Ie)-a]} -gt 0 ]] || return 1

    exit 0
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

    # Flat command: no Commands:-style heading, just --options — the "ls,
    # rg, fd" case. Used to prove the divider says "Options" (not
    # "Commands") and that has-subcmds correctly says no for it.
    cat >"$bindir/flatcmd" <<'STUB'
#!/usr/bin/env zsh
cat <<'EOF'
Usage: flatcmd [options] [FILE]...

Options:
  -a, --all    Do not ignore entries starting with .
EOF
STUB
    chmod +x "$bindir/flatcmd"

    export PATH="$bindir:$PATH"
    export FZF_TAB_HELP_CACHE_DIR="$cachedir"
    export FZF_PREVIEW_COLUMNS=60

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

    # has-subcmds + the full-width divider: obsidian (has a Commands:
    # heading) gets "Commands" spanning FZF_PREVIEW_COLUMNS; flatcmd (no
    # heading, just --options) gets "Options", same width.
    zsh -f "$fth" has-subcmds -- obsidian || exit 1
    zsh -f "$fth" has-subcmds -- flatcmd && exit 1
    local divider_line
    divider_line=$(zsh -f "$fth" usage -- obsidian | tail -1)
    [[ $divider_line == *'Commands'* ]] || exit 1
    [[ ${#divider_line} == "$FZF_PREVIEW_COLUMNS" ]] || exit 1
    divider_line=$(zsh -f "$fth" usage -- flatcmd | tail -1)
    [[ $divider_line == *'Options'* ]] || exit 1
    [[ ${#divider_line} == "$FZF_PREVIEW_COLUMNS" ]] || exit 1

    # 'options' subcommand: flatcmd's same-line description must not be
    # mistaken for a value placeholder (TAKESVALUE=0 for both -a and --all).
    local options_out
    options_out=$(zsh -f "$fth" options -- flatcmd)
    [[ $options_out == *$'-a\t0\tDo not ignore entries starting with .'* ]] || exit 1
    [[ $options_out == *$'--all\t0\tDo not ignore entries starting with .'* ]] || exit 1

    # Case E: rg's "-e PATTERN, --regexp=PATTERN" comma-value style — the
    # placeholder sits BETWEEN flags, not at line-end; both must get
    # TAKESVALUE=1 (line-level arity, not per-segment).
    cat >"$bindir/fakerg" <<'STUB'
#!/usr/bin/env zsh
cat <<'EOF'
Usage: fakerg [OPTIONS] PATTERN

OPTIONS:
  -e PATTERN, --regexp=PATTERN
          Specify a pattern
EOF
STUB
    chmod +x "$bindir/fakerg"
    options_out=$(zsh -f "$fth" options -- fakerg)
    [[ $options_out == *$'-e\t1\t'* ]] || exit 1
    [[ $options_out == *$'--regexp\t1\t'* ]] || exit 1

    # Case F: width pinning — the SAME stub parsed at two different
    # FZF_PREVIEW_COLUMNS values must give identical TAKESVALUE output,
    # proving the options parse uses its own width-pinned cache entry, not
    # the live pane width.
    rm -rf -- "$cachedir"/*
    local options_80 options_120
    options_80=$(FZF_PREVIEW_COLUMNS=80 zsh -f "$fth" options -- fakerg)
    options_120=$(FZF_PREVIEW_COLUMNS=120 zsh -f "$fth" options -- fakerg)
    [[ $options_80 == "$options_120" ]] || exit 1

    # fzf-tab's preview template EXPORTS word/desc before exec'ing this
    # script; the script's own `local word desc` (no value) on an
    # already-exported param is zsh's typeset-query form and PRINTS it
    # unless typeset_silent is set — reproduced as a stray "word=…"/"desc=…"
    # line above every real preview. Export them here to catch a regression.
    local block_out
    block_out=$(word=aliases desc='aliases -- List aliases in the vault' \
      zsh -f "$fth" block aliases 'aliases -- List aliases in the vault' -- obsidian) || exit 1
    [[ $block_out == *'word='* || $block_out == *'desc='* ]] && exit 1

    # A command absent from PATH must never poison the cache: `timeout`
    # itself fails to exec (rc 127) and that failure text must not be
    # persisted as if it were real --help output (reproduced: a transient
    # PATH gap made obsidian's cache return "timeout: failed to run command
    # 'obsidian'" for up to 7 days).
    rm -rf -- "$cachedir"/*
    local missing_out
    missing_out=$(zsh -f "$fth" usage -- nonexistent-cmd-xyz)
    [[ $missing_out == *'failed to run'* ]] && exit 1
    grep -rlF 'failed to run' "$cachedir" >/dev/null 2>&1 && exit 1
    exit 0
  ) || return 1

  print 'Shell shortcut checks passed'
}
