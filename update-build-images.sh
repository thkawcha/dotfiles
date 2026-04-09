#!/bin/bash
set -euo pipefail

# =============================================================================
# update-build-images.sh
#
# Checks the Azure Container Registry for newer build images and pulls them.
# Designed to run unattended (e.g., via cron or systemd timer).
#
# Authentication:
#   Uses existing az CLI credentials. If they have expired, the script
#   will exit with a message asking you to run 'az login' and
#   'az acr login -n merubuildimages' interactively before re-running.
#
# Usage:
#   ./update-build-images.sh              # Pull latest stable image
#   ./update-build-images.sh --next       # Pull latest -next (pre-release) image
#   ./update-build-images.sh --dry-run    # Check for updates without pulling
#   ./update-build-images.sh --install    # Install a nightly cron job (2 AM)
#   ./update-build-images.sh --uninstall  # Remove the cron job
# =============================================================================

ACR_NAME="merubuildimages"
ACR_HOST="${ACR_NAME}.azurecr.io"
REPOSITORY="ubuntu-22.04-x86_64"
IMAGE_BASE="${ACR_HOST}/${REPOSITORY}"
LOG_PREFIX="[update-build-images]"

PULL_NEXT=false
DRY_RUN=false

SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
LOG_FILE="$(dirname "$SCRIPT_PATH")/update-build-images.log"
CRON_TAG="# update-build-images"

# ---------------------------------------------------------------------------
# Cron install / uninstall helpers
# ---------------------------------------------------------------------------
install_cron() {
    local cron_line="0 2 * * * ${SCRIPT_PATH} >> ${LOG_FILE} 2>&1 ${CRON_TAG}"

    # Check if already installed
    if crontab -l 2>/dev/null | grep -qF "$CRON_TAG"; then
        echo "Cron job already installed:"
        crontab -l | grep -F "$CRON_TAG"
        exit 0
    fi

    # Append to existing crontab
    (crontab -l 2>/dev/null || true; echo "$cron_line") | crontab -
    echo "Cron job installed: ${cron_line}"
    echo "Logs will be written to: ${LOG_FILE}"
    exit 0
}

uninstall_cron() {
    if ! crontab -l 2>/dev/null | grep -qF "$CRON_TAG"; then
        echo "No cron job found to remove."
        exit 0
    fi

    crontab -l 2>/dev/null | grep -vF "$CRON_TAG" | crontab -
    echo "Cron job removed."
    exit 0
}

for arg in "$@"; do
    case "$arg" in
        --next)      PULL_NEXT=true ;;
        --dry-run)   DRY_RUN=true ;;
        --install)   install_cron ;;
        --uninstall) uninstall_cron ;;
        --help|-h)
            sed -n '/^# Usage:/,/^# ====/p' "$0" | sed 's/^# //' | sed 's/^#//'
            exit 0
            ;;
        *)
            echo "Unknown option: $arg"
            exit 1
            ;;
    esac
done

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') ${LOG_PREFIX} $*"
}

die() {
    log "ERROR: $*" >&2
    exit 1
}

# ---------------------------------------------------------------------------
# Authentication – just verify existing credentials work
# ---------------------------------------------------------------------------
check_acr_auth() {
    if az acr login -n "$ACR_NAME" 2>/dev/null; then
        log "ACR credentials are valid."
        return 0
    fi

    log ""
    log "============================================================"
    log "  ACR authentication has expired or is not configured."
    log "  Please run the following commands interactively:"
    log ""
    log "    az login"
    log "    az acr login -n ${ACR_NAME}"
    log ""
    log "  Then re-run this script."
    log "============================================================"
    log ""
    exit 1
}

# ---------------------------------------------------------------------------
# Query ACR for the latest image tag
# ---------------------------------------------------------------------------
get_latest_remote_tag() {
    local tags
    tags=$(az acr repository show-tags \
        -n "$ACR_NAME" \
        --repository "$REPOSITORY" \
        --orderby time_desc \
        --top 20 \
        --output tsv 2>/dev/null) \
        || die "Failed to query tags from ACR."

    local tag
    if $PULL_NEXT; then
        # Pick the newest tag ending in -next (but not "latest_next")
        tag=$(echo "$tags" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+-next$' | head -1)
    else
        # Pick the newest stable semver tag (digits.digits.digits, no suffix)
        tag=$(echo "$tags" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
    fi

    [[ -n "$tag" ]] || die "No suitable tag found in registry."
    echo "$tag"
}

# ---------------------------------------------------------------------------
# Determine the currently-pulled local tag for the image
# ---------------------------------------------------------------------------
get_local_tag() {
    docker images "$IMAGE_BASE" --format '{{.Tag}}' 2>/dev/null \
        | grep -E '^[0-9]+\.[0-9]+\.[0-9]+(-next)?$' \
        | sort -V \
        | tail -1 \
        || true
}

# ---------------------------------------------------------------------------
# Compare two semver-style versions. Returns 0 if $1 > $2.
# ---------------------------------------------------------------------------
is_newer() {
    local remote="$1" local_ver="$2"

    # Strip -next suffix for numeric comparison
    local r_base="${remote%-next}"
    local l_base="${local_ver%-next}"

    if [[ "$(printf '%s\n%s' "$l_base" "$r_base" | sort -V | tail -1)" == "$r_base" && "$r_base" != "$l_base" ]]; then
        return 0
    fi

    # Same base version but remote is -next and local is not (or vice versa):
    # treat -next as newer than same base without suffix if --next was requested
    if [[ "$r_base" == "$l_base" && "$remote" != "$local_ver" ]]; then
        return 0
    fi

    return 1
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    log "Starting build image update check."

    check_acr_auth

    local remote_tag
    remote_tag=$(get_latest_remote_tag)
    log "Latest remote tag: ${remote_tag}"

    local local_tag
    local_tag=$(get_local_tag)

    if [[ -n "$local_tag" ]]; then
        log "Latest local tag:  ${local_tag}"
    else
        log "No local build image found."
    fi

    # Decide whether to pull
    if [[ -z "$local_tag" ]] || is_newer "$remote_tag" "$local_tag"; then
        log "Newer image available: ${IMAGE_BASE}:${remote_tag}"

        if $DRY_RUN; then
            log "[DRY RUN] Would pull ${IMAGE_BASE}:${remote_tag}"
        else
            log "Pulling ${IMAGE_BASE}:${remote_tag} ..."
            docker pull "${IMAGE_BASE}:${remote_tag}" \
                || die "Failed to pull ${IMAGE_BASE}:${remote_tag}"
            log "Successfully pulled ${IMAGE_BASE}:${remote_tag}"
        fi
    else
        log "Local image is already up to date (${local_tag})."
    fi

    log "Done."
}

main
