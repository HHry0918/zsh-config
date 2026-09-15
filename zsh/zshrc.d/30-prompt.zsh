# agnoster prompt overrides (theme itself lives in omz-custom/themes/agnoster.zsh-theme)

# End the prompt, closing any open segments
prompt_end() {
  if [[ -n $CURRENT_BG ]]; then
    echo -n " %{%k%F{$CURRENT_BG}%}$SEGMENT_SEPARATOR"
  else
    echo -n "%{%k%}"
  fi
  echo -n "\n%{%F{$CURRENT_BG}%}$%{%f%}"
  CURRENT_BG=''
}

# agnoster.zsh-theme's own prompt_context (styled, root-highlighted, SSH-aware) already
# renders "user@host" — hidden by default (single-workstation setups don't need it), but
# shown when ZSH_CONFIG_DISPLAY_HOST is set (install.sh --display-host writes that into
# ~/.zshrc.local), which is useful on a shared fleet of similarly-named boxes.
#
# The check happens at prompt-render time, not here at load time: ~/.zshrc.local is
# sourced LAST by zsh/zshrc, after this file, so the variable doesn't exist yet if this
# just did `if [[ -z $ZSH_CONFIG_DISPLAY_HOST ]]; then override; fi` here directly —
# that would always take the "unset" branch regardless of the flag. Preserving the
# theme's original function and dispatching to it inside the new one sidesteps the
# ordering issue entirely, since the dispatch decision is deferred to when the prompt is
# actually drawn (well after ~/.zshrc.local has run).
functions[_agnoster_orig_prompt_context]=$functions[prompt_context]
prompt_context() {
  if [[ -n $ZSH_CONFIG_DISPLAY_HOST ]]; then
    _agnoster_orig_prompt_context
  else
    echo ""
  fi
}

: ${AGNOSTER_GIT_DIRTY_FG:=${CURRENT_FG}}
: ${AGNOSTER_BZR_DIRTY_FG:=${CURRENT_BG}}
: ${AGNOSTER_HG_CHANGED_FG:=${CURRENT_BG}}
: ${AGNOSTER_VENV_FG:=${CURRENT_BG}}
: ${AGNOSTER_AWS_FG:=${CURRENT_BG}}
: ${AGNOSTER_CONTEXT_BG:='NONE'}
: ${AGNOSTER_DIR_BG:=blue}
