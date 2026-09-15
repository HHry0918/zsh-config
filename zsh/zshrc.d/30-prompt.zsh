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

prompt_context() {
    echo ""
}

: ${AGNOSTER_GIT_DIRTY_FG:=${CURRENT_FG}}
: ${AGNOSTER_BZR_DIRTY_FG:=${CURRENT_BG}}
: ${AGNOSTER_HG_CHANGED_FG:=${CURRENT_BG}}
: ${AGNOSTER_VENV_FG:=${CURRENT_BG}}
: ${AGNOSTER_AWS_FG:=${CURRENT_BG}}
: ${AGNOSTER_CONTEXT_BG:='NONE'}
: ${AGNOSTER_DIR_BG:=blue}
