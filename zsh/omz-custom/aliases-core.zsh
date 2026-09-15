# lsd (replaces ls)
alias ls='lsd --group-directories-first'
alias l='lsd -lA --header --git --group-directories-first'
alias ll='lsd -lA --header --git --group-directories-first'
alias la='lsd -A --group-directories-first'
unalias lsa 2>/dev/null || true   # omz lib/directories.zsh leftover, still GNU ls
alias dir='dir --color'
alias vdir='vdir --color'
alias grep='grep --color'
alias fgrep='fgrep --color'
alias egrep='egrep --color'

alias zshconfig="${EDITOR:-vi} ~/.zshrc"
alias ohmyzsh="${EDITOR:-vi} ~/.oh-my-zsh"

alias bat="bat --color=always --style=numbers"
