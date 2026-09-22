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
install_agency() {
    local windows_system32="/mnt/c/Windows/System32"
    local status

    if [[ -n "${AGENCY_SESSION_ID:-}" ]]; then
        echo "install_agency: exit Agency and rerun this command in a regular WSL terminal." >&2
        return 1
    fi

    if [[ ! -x "$windows_system32/cmd.exe" ]] ||
       ! "$windows_system32/cmd.exe" /c ver >/dev/null 2>&1; then
        echo "install_agency: Windows interop is unavailable; cmd.exe is required for authentication." >&2
        return 1
    fi

    (
        export PATH="$windows_system32:$PATH"
        set -o pipefail
        curl -sSfL https://aka.ms/InstallTool.sh | bash -e -s agency
    )
    status=$?
    if (( status != 0 )); then
        echo "install_agency: update failed with status $status." >&2
        return "$status"
    fi

    exec "${SHELL:-/bin/bash}" -l
}
