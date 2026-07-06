#!/bin/bash
# download_release_bits.sh - thin wrapper that invokes the user's
# download-latest-release-bits.sh in $HOME to fetch the latest release packages
# (the meru_prod_release_* bits) into ~/latest-release-packages.
#
# That folder is the default --local-dir / MERU_LOCAL_DIR consumed by the
# deploy-meru-cluster (and deploy-meru-cluster-scenario) skills.
#
# Usage:
#   download_release_bits.sh [extra args forwarded to the HOME script]
#
# The HOME script is resolved as (first match wins):
#   $MERU_DOWNLOAD_SCRIPT  ->  ~/download-latest-release-bits.sh  ->  ~/download-latest-release*.sh

set -uo pipefail

log() { echo "[meru] $*" >&2; }
err() { echo "[meru][ERROR] $*" >&2; }

resolve_download_script() {
  if [ -n "${MERU_DOWNLOAD_SCRIPT:-}" ]; then
    [ -f "$MERU_DOWNLOAD_SCRIPT" ] && { echo "$MERU_DOWNLOAD_SCRIPT"; return 0; }
    err "MERU_DOWNLOAD_SCRIPT set but not found: $MERU_DOWNLOAD_SCRIPT"; return 1
  fi
  if [ -f "$HOME/download-latest-release-bits.sh" ]; then
    echo "$HOME/download-latest-release-bits.sh"; return 0
  fi
  local m
  m="$(ls -1 "$HOME"/download-latest-release*.sh 2>/dev/null | head -1)"
  if [ -n "$m" ]; then echo "$m"; return 0; fi
  err "no download-latest-release*.sh found in \$HOME; set MERU_DOWNLOAD_SCRIPT to its path."
  return 1
}

main() {
  case "${1:-}" in
    -h|--help|help)
      sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      return 0 ;;
  esac
  local script
  script="$(resolve_download_script)" || return 1
  log "downloading latest release bits via: ${script}"
  log "(requires Azure CLI auth; if it fails, run 'az login' first — do NOT use --use-device-code)"
  bash "$script" "$@"
  local rc=$?
  if [ $rc -ne 0 ]; then err "download script failed (rc=${rc})"; return $rc; fi
  log "release bits downloaded to ~/latest-release-packages (the deploy skills' default --local-dir)"
}

main "$@"
