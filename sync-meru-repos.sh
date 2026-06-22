#!/bin/bash
# Sync all meru-* repos: fetch, fast-forward main, update submodules.
# Resilient to transient SSH/network errors (e.g. GitHub "Could not fetch origin")
# via per-operation retries with exponential backoff.

REPO_ROOT="${1:-$HOME}"
CHECKOUT_SCRIPT="ext/build-infra/devcontainer-features/meru-devcontainer-ubuntu/scripts/checkout-submodules.sh"

# Tunables (override via env): number of attempts and base backoff seconds.
RETRIES="${SYNC_RETRIES:-4}"
BACKOFF="${SYNC_BACKOFF:-3}"

# Reuse SSH connections across the many fetches/pulls below. This dramatically
# reduces the number of TCP/SSH handshakes to github.com, which is the main
# source of transient "Could not fetch origin" throttling/resets.
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o ControlMaster=auto -o ControlPersist=60 -o ControlPath=/tmp/.ssh-meru-%r@%h:%p}"

failed=()

# retry <description> <command...>
# Runs the command, retrying on failure with exponential backoff.
retry() {
    local desc="$1"; shift
    local attempt=1 delay="$BACKOFF"
    while true; do
        if "$@"; then
            return 0
        fi
        if [ "$attempt" -ge "$RETRIES" ]; then
            echo "  ✗ $desc failed after $attempt attempts" >&2
            return 1
        fi
        echo "  … $desc failed (attempt $attempt/$RETRIES); retrying in ${delay}s" >&2
        sleep "$delay"
        attempt=$((attempt + 1))
        delay=$((delay * 2))
    done
}

for repo in "$REPO_ROOT"/meru-*/; do
    [ -d "$repo" ] || continue
    name=$(basename "$repo")
    echo "=== $name ==="

    if ! cd "$repo"; then
        echo "  ✗ could not cd into $repo" >&2
        failed+=("$name")
        continue
    fi

    ok=true
    # --force/--prune-tags so a tag that was moved or deleted on the remote
    # (e.g. "would clobber existing tag") updates cleanly instead of failing
    # the fetch deterministically.
    retry "fetch"     git fetch --all --prune --prune-tags --force -q || ok=false
    if $ok; then
        retry "checkout main" git checkout main -q || ok=false
    fi
    if $ok; then
        retry "pull"  git pull --ff-only -q || ok=false
    fi
    if $ok; then
        if [ -f "$CHECKOUT_SCRIPT" ]; then
            retry "submodules" bash "$CHECKOUT_SCRIPT" "$repo" || ok=false
        else
            retry "submodules" git submodule update --init || ok=false
        fi
    fi

    if $ok; then
        echo "✓ OK"
    else
        echo "✗ FAILED"
        failed+=("$name")
    fi
    echo ""
done

if [ ${#failed[@]} -gt 0 ]; then
    echo "Failed repos: ${failed[*]}"
    exit 1
fi

echo "All meru repos synced successfully."
