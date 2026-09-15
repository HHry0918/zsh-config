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
# left in place when ZSH_CONFIG_DISPLAY_HOST is set (install.sh --display-host writes
# that into ~/.zshrc.local), which is useful on a shared fleet of similarly-named boxes.
if [[ -z $ZSH_CONFIG_DISPLAY_HOST ]]; then
  prompt_context() {
      echo ""
  }
fi

: ${AGNOSTER_GIT_DIRTY_FG:=${CURRENT_FG}}
: ${AGNOSTER_BZR_DIRTY_FG:=${CURRENT_BG}}
: ${AGNOSTER_HG_CHANGED_FG:=${CURRENT_BG}}
: ${AGNOSTER_VENV_FG:=${CURRENT_BG}}
: ${AGNOSTER_AWS_FG:=${CURRENT_BG}}
: ${AGNOSTER_CONTEXT_BG:='NONE'}
: ${AGNOSTER_DIR_BG:=blue}
