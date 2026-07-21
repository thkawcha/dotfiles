# ~/.bash_aliases: Custom bash aliases

# ls aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# Custom commands
alias update="sudo apt-get update && sudo apt-get upgrade"
alias sync_main="git checkout main && git fetch && git pull && git submodule update --init --recursive && git status"
alias checkout_submodules="git submodule update --init && ext/build-infra/devcontainer-features/meru-devcontainer-ubuntu/scripts/checkout-submodules.sh"

# Agency install
alias install_agency="curl -sSfL https://aka.ms/InstallTool.sh | sh -s agency && exec $SHELL -l"
