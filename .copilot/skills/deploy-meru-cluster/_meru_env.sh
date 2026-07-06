#!/bin/bash
# Shared helpers for the local-meru-cluster family of skills.
#
# Source this file (do NOT execute it) to get:
#   - meru_repo_root            : path to the git repo root
#   - meru_packages_dir         : path to out/release/packages (deployer + install scripts)
#   - meru_local_dir            : dir with release bits (meru_prod_release*.tar.gz)
#   - meru_check_release_bits   : validate the deployer's two tar inputs
#   - meru_setup_venv           : create + activate the meructl python venv
#   - meru_activate_venv        : activate an already-created meructl venv
#   - meru_meructl <args...>    : run meructl inside the venv
#
# Conventions: progress/errors -> stderr, machine-readable results -> stdout.
#
# Environment overrides:
#   MERU_REPO_ROOT      : force the repo root (default: git toplevel of cwd)
#   MERU_PACKAGES_DIR   : force the packages dir (default: <root>/out/release/packages)
#   MERU_LOCAL_DIR      : force the release-bits dir (default: ~/latest-release-packages)
#   MERU_SUDO           : sudo command for the deployer (default: sudo)

meru_log()  { echo "[meru] $*" >&2; }
meru_err()  { echo "[meru][ERROR] $*" >&2; }

# Run a command as root. No-op prefix when already root. Override the sudo
# binary/args with MERU_SUDO (e.g. MERU_SUDO="sudo -E").
meru_sudo() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    ${MERU_SUDO:-sudo} "$@"
  fi
}

meru_repo_root() {
  if [ -n "${MERU_REPO_ROOT:-}" ]; then
    echo "$MERU_REPO_ROOT"
    return 0
  fi
  local root
  root="$(git -C "${1:-$PWD}" rev-parse --show-toplevel 2>/dev/null)"
  if [ -z "$root" ]; then
    meru_err "could not determine repo root (not in a git repo and MERU_REPO_ROOT unset)"
    return 1
  fi
  echo "$root"
}

meru_packages_dir() {
  if [ -n "${MERU_PACKAGES_DIR:-}" ]; then
    echo "$MERU_PACKAGES_DIR"
    return 0
  fi
  local root
  root="$(meru_repo_root)" || return 1
  echo "${root}/out/release/packages"
}

# Directory holding the downloaded release binaries (meru_prod_release*.tar.gz),
# passed to the deployer as --local-dir. This is DISTINCT from the packages dir:
# the packages dir holds the install scripts (meru_prod_core*), while the
# local-dir holds the release bits the deployer installs.
# Override with MERU_LOCAL_DIR (default: ~/latest-release-packages).
meru_local_dir() {
  if [ -n "${MERU_LOCAL_DIR:-}" ]; then
    echo "$MERU_LOCAL_DIR"
    return 0
  fi
  echo "${HOME}/latest-release-packages"
}

# Validate the deployer's two tar inputs:
#   - exactly one meru_prod_*.tar.gz in the packages dir (install scripts)
#   - exactly one meru_prod_release*.tar.gz in the local-dir (release bits)
# Echoes the release tar basename on success.
meru_check_release_bits() {
  local pkg local_dir
  pkg="$(meru_packages_dir)" || return 1
  local_dir="$(meru_local_dir)" || return 1

  local prod_matches
  mapfile -t prod_matches < <(cd "$pkg" 2>/dev/null && ls -1 meru_prod_*.tar.gz 2>/dev/null)
  if [ "${#prod_matches[@]}" -ne 1 ]; then
    meru_err "expected exactly one meru_prod_*.tar.gz in packages dir ${pkg}, found ${#prod_matches[@]}:"
    printf '  %s\n' "${prod_matches[@]}" >&2
    meru_err "remove stale tar(s) and retry (or rebuild the release bits)."
    return 1
  fi

  if [ ! -d "$local_dir" ]; then
    meru_err "release bits dir not found: ${local_dir} (set MERU_LOCAL_DIR)."
    return 1
  fi
  local rel_matches
  mapfile -t rel_matches < <(cd "$local_dir" 2>/dev/null && ls -1 meru_prod_release*.tar.gz 2>/dev/null)
  if [ "${#rel_matches[@]}" -ne 1 ]; then
    meru_err "expected exactly one meru_prod_release*.tar.gz in local-dir ${local_dir}, found ${#rel_matches[@]}:"
    printf '  %s\n' "${rel_matches[@]}" >&2
    return 1
  fi
  echo "${rel_matches[0]}"
}

# Activate an already-created venv. Returns non-zero if it does not exist.
meru_activate_venv() {
  local pkg
  pkg="$(meru_packages_dir)" || return 1
  if [ ! -f "${pkg}/venv/bin/activate" ]; then
    return 1
  fi
  # shellcheck disable=SC1090
  source "${pkg}/venv/bin/activate"
}

# Create (if needed) and activate the meructl venv via installer.sh -v.
meru_setup_venv() {
  local pkg
  pkg="$(meru_packages_dir)" || return 1
  if meru_activate_venv; then
    return 0
  fi
  if [ ! -f "${pkg}/installer.sh" ]; then
    meru_err "installer.sh not found in ${pkg}"
    return 1
  fi
  meru_log "setting up meructl venv via 'source installer.sh -v' ..."
  local prev="$PWD"
  cd "$pkg" || return 1
  # installer.sh -v must be sourced; it creates ./venv and activates it.
  # shellcheck disable=SC1091
  source ./installer.sh -v >&2
  local rc=$?
  cd "$prev" || true
  if [ $rc -ne 0 ]; then
    meru_err "installer.sh -v failed (rc=$rc)"
    return $rc
  fi
  meru_activate_venv
}

# Run meructl inside the venv. Always activates (creating if needed) the venv so
# the venv's meructl is used, never a stale global one on PATH.
# Stdin is taken from /dev/null so meructl's interactive prompts (which it raises
# on connection errors) can never hang the caller.
meru_meructl() {
  # Use the venv's meructl explicitly to avoid shadowing by a global install.
  local pkg
  pkg="$(meru_packages_dir)" || return 1
  if [ "${VIRTUAL_ENV:-}" != "${pkg}/venv" ]; then
    meru_setup_venv >&2 || return 1
  fi
  if [ -x "${pkg}/venv/bin/meructl" ]; then
    "${pkg}/venv/bin/meructl" "$@" </dev/null
  else
    meructl "$@" </dev/null
  fi
}

# Returns 0 if the cluster gateway answers (non-interactive probe).
meru_cluster_reachable() {
  meru_meructl application list >/dev/null 2>&1
}

# Poll until the cluster gateway is reachable or the timeout elapses.
# Usage: meru_wait_for_cluster [timeout_seconds] [interval_seconds]
# The legacy one-node cluster comes up asynchronously a few minutes after the
# deployer returns, so callers should wait rather than probe once.
meru_wait_for_cluster() {
  local timeout="${1:-300}" interval="${2:-10}" waited=0
  meru_setup_venv >&2 || return 1
  meru_log "waiting up to ${timeout}s for the cluster gateway to come up ..."
  while [ "$waited" -lt "$timeout" ]; do
    if meru_cluster_reachable; then
      meru_log "cluster gateway reachable after ${waited}s"
      return 0
    fi
    sleep "$interval"
    waited=$((waited + interval))
  done
  meru_err "cluster gateway not reachable after ${timeout}s"
  return 1
}
