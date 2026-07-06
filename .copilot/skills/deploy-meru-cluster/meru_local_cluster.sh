#!/bin/bash
# meru_local_cluster.sh - lifecycle for a local one-node Meru cluster.
#
# Subcommands:
#   deploy     Bring up a fresh one-node cluster from out/release/packages and
#              set up the meructl venv. Verifies with 'meructl cluster view'.
#   status     Activate the venv and run 'meructl cluster view'.
#   meructl    Run an arbitrary meructl command inside the venv.
#              e.g. ./meru_local_cluster.sh meructl application list
#   wait-app   Wait until an application reports READY.
#              e.g. ./meru_local_cluster.sh wait-app _ssm_ 180
#   teardown   Remove the local cluster (deployer cleanup operation).
#
# Assumes the release bits are already built (exactly one meru_prod*.tar.gz in
# the packages dir). Override the packages dir with MERU_PACKAGES_DIR.

set -uo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_meru_env.sh
source "${SCRIPT_DIR}/_meru_env.sh"

usage() {
  sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

cmd_deploy() {
  local pkg local_dir rel_tar
  pkg="$(meru_packages_dir)" || return 1
  local_dir="$(meru_local_dir)" || return 1
  if [ ! -x "${pkg}/core-cluster-deployer.sh" ]; then
    meru_err "core-cluster-deployer.sh not found/executable in ${pkg}"
    return 1
  fi
  rel_tar="$(meru_check_release_bits)" || return 1
  meru_log "deploying one-node cluster"
  meru_log "  packages (script_path): ${pkg}"
  meru_log "  release bits (--local-dir): ${local_dir} (${rel_tar})"

  ( cd "$pkg" && meru_sudo ./core-cluster-deployer.sh -one --legacy --local-dir "$local_dir" )
  local rc=$?
  if [ $rc -ne 0 ]; then
    meru_err "core-cluster-deployer.sh failed (rc=$rc)"
    return $rc
  fi

  meru_log "cluster deployed; setting up meructl venv"
  meru_setup_venv >&2 || return 1

  meru_log "verifying cluster reachability (cluster comes up asynchronously)"
  if meru_wait_for_cluster "${MERU_CLUSTER_WAIT:-300}"; then
    meru_meructl cluster view || true
    meru_log "cluster is up and reachable"
    return 0
  fi
  meru_err "cluster deployed but the gateway did not come up in time."
  meru_err "check that envoy is running and the endpoint is correct ('meructl cluster select')."
  return 1
}

cmd_status() {
  meru_meructl cluster view
}

cmd_meructl() {
  meru_meructl "$@"
}

# Wait until application <name> reports READY (or timeout). Useful for
# validating that a deployed app/manager/provider has come up.
cmd_wait_app() {
  local name="${1:-}" timeout="${2:-180}" waited=0 interval=5 status=""
  if [ -z "$name" ]; then meru_err "usage: wait-app <name> [timeout_s]"; return 2; fi
  meru_setup_venv >&2 || return 1
  meru_log "waiting up to ${timeout}s for application ${name} to be READY ..."
  while [ "$waited" -lt "$timeout" ]; do
    status="$(meru_meructl application list 2>/dev/null | python3 -c '
import sys, json
name = sys.argv[1]
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for a in d.get("applications", []):
    if a.get("name") == name:
        print(a.get("status", ""))
        break
' "$name")"
    if [ "$status" = "READY" ]; then
      meru_log "application ${name} is READY (after ${waited}s)"
      return 0
    fi
    sleep "$interval"; waited=$((waited + interval))
  done
  meru_err "application ${name} not READY after ${timeout}s (last status: '${status:-none}')"
  return 1
}

cmd_teardown() {
  local pkg
  pkg="$(meru_packages_dir)" || return 1
  if [ ! -x "${pkg}/core-cluster-deployer.sh" ]; then
    meru_err "core-cluster-deployer.sh not found/executable in ${pkg}"
    return 1
  fi
  meru_log "tearing down local cluster (deployer cleanup)"
  ( cd "$pkg" && meru_sudo ./core-cluster-deployer.sh -one --legacy -o c )
}

main() {
  local sub="${1:-}"
  [ $# -gt 0 ] && shift
  case "$sub" in
    deploy)   cmd_deploy "$@" ;;
    status)   cmd_status "$@" ;;
    meructl)  cmd_meructl "$@" ;;
    wait-app) cmd_wait_app "$@" ;;
    teardown) cmd_teardown "$@" ;;
    ""|-h|--help|help) usage ;;
    *) meru_err "unknown subcommand: $sub"; usage; return 2 ;;
  esac
}

main "$@"
