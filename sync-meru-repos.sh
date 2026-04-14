#!/bin/bash
set -e

REPO_ROOT="${1:-$HOME}"
CHECKOUT_SCRIPT="ext/build-infra/devcontainer-features/meru-devcontainer-ubuntu/scripts/checkout-submodules.sh"

failed=()

for repo in "$REPO_ROOT"/meru-*/; do
    name=$(basename "$repo")
    echo "=== $name ==="

    cd "$repo"

    # Fetch latest and checkout main
    git fetch --all --prune -q
    git checkout main -q
    git pull --ff-only -q

    # Update submodules using the canonical script if available
    if [ -f "$CHECKOUT_SCRIPT" ]; then
        bash "$CHECKOUT_SCRIPT" "$repo"
    else
        git submodule update --init
    fi

    echo "✓ OK"
    echo ""
done

if [ ${#failed[@]} -gt 0 ]; then
    echo "Failed repos: ${failed[*]}"
    exit 1
fi

echo "All meru repos synced successfully."
