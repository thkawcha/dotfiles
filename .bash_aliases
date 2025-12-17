# ~/.bash_aliases: Custom bash aliases

# ls aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# Custom commands
alias update="sudo apt-get update && sudo apt-get upgrade"
alias sync_main="git checkout main && git fetch && git pull && git submodule update --init --recursive && git status"
