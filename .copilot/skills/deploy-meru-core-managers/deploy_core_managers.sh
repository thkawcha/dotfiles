#!/bin/bash
# deploy_core_managers.sh - deploy/undeploy the L2 Meru core managers onto a
# running local one-node cluster.
#
# Managers (deployed in this order, all enlightened):
#   ISM, SSM, Node Manager, Resource Manager, Deployment Manager, Secret Store
#
# Source YAMLs are the SHARED E2E definitions (not point-in-time copies):
#   - ISM/SSM/NM/RM/DM : ext/test-infra/src/eris/lib/eris/apps/*.yaml
#                        (placeholders substituted for a one-node cluster)
#   - sstore           : ext/test-infra/src/admin/mnm/common/sstore.yaml
#                        (replicaCount forced to 1)
#
# Placeholder substitutions (one-node defaults):
#   REPLICA_COUNT_REPLACE  -> 1
#   ENABLE_SSM_V2_REPLACE  -> 0   (override with ENABLE_SSM_V2=1)
#   ENABLE_NM_V2_REPLACE   -> 0   (override with ENABLE_NM_V2=1)
#
# Subcommands:
#   deploy     Create all core manager applications.
#   undeploy   Delete all core manager applications (reverse order).
#   status     List deployed applications (meructl application list).

set -uo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../deploy-meru-cluster/_meru_env.sh
source "${SCRIPT_DIR}/../deploy-meru-cluster/_meru_env.sh"

ENABLE_SSM_V2="${ENABLE_SSM_V2:-0}"
ENABLE_NM_V2="${ENABLE_NM_V2:-0}"
REPLICA_COUNT="${REPLICA_COUNT:-1}"

usage() {
  sed -n '2,24p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# Deploy order: app_name|source_yaml_path (relative to repo root)
manager_specs() {
  local root="$1"
  cat <<EOF
_ism_|${root}/ext/test-infra/src/eris/lib/eris/apps/ism.yaml
_ssm_|${root}/ext/test-infra/src/eris/lib/eris/apps/ssm.yaml
_node_manager_|${root}/ext/test-infra/src/eris/lib/eris/apps/node_manager.yaml
_resource_manager_|${root}/ext/test-infra/src/eris/lib/eris/apps/resource_manager.yaml
_deployment_manager_|${root}/ext/test-infra/src/eris/lib/eris/apps/deployment_manager.yaml
_sstore_|${root}/ext/test-infra/src/admin/mnm/common/sstore.yaml
EOF
}

# Render a manager yaml with one-node substitutions into $1 (dest file).
render_yaml() {
  local src="$1" dest="$2"
  if [ ! -f "$src" ]; then
    meru_err "source yaml not found: $src"
    return 1
  fi
  sed -e "s/REPLICA_COUNT_REPLACE/${REPLICA_COUNT}/g" \
      -e "s/ENABLE_SSM_V2_REPLACE/${ENABLE_SSM_V2}/g" \
      -e "s/ENABLE_NM_V2_REPLACE/${ENABLE_NM_V2}/g" \
      "$src" > "$dest" || return 1

  # sstore (mnm common) has no replica placeholder; force it to 1 node.
  case "$src" in
    */mnm/common/sstore.yaml)
      sed -i -e "s/^\(\s*replicaCount:\s*\).*/\1${REPLICA_COUNT}/" "$dest"
      ;;
  esac
}

cmd_deploy() {
  local root tmp
  root="$(meru_repo_root)" || return 1
  meru_setup_venv >&2 || return 1
  local tmp app src dest failed=0
  tmp="$(mktemp -d)"

  while IFS='|' read -r app src; do
    [ -z "$app" ] && continue
    dest="${tmp}/$(basename "$src")"
    meru_log "rendering ${app} from ${src#"$root"/}"
    render_yaml "$src" "$dest" || { failed=1; break; }
    meru_log "creating application ${app}"
    if ! meru_meructl application create --file-path "$dest" --enlightened; then
      meru_err "failed to create application ${app}"
      failed=1
      break
    fi
  done < <(manager_specs "$root")

  rm -rf "$tmp"
  if [ "$failed" -ne 0 ]; then
    meru_err "core manager deployment aborted"
    return 1
  fi
  meru_log "all core managers deployed"
  meru_log "tip: run 'meru_local_cluster.sh meructl application list' to inspect"
}

cmd_undeploy() {
  local root
  root="$(meru_repo_root)" || return 1
  meru_setup_venv >&2 || return 1
  # Delete in reverse order.
  local apps app
  mapfile -t apps < <(manager_specs "$root" | cut -d'|' -f1 | tac)
  for app in "${apps[@]}"; do
    [ -z "$app" ] && continue
    meru_log "deleting application ${app}"
    meru_meructl application delete --application-name "$app" || \
      meru_err "delete of ${app} failed (continuing)"
  done
}

cmd_status() {
  meru_meructl application list
}

main() {
  local sub="${1:-}"
  [ $# -gt 0 ] && shift
  case "$sub" in
    deploy)   cmd_deploy "$@" ;;
    undeploy) cmd_undeploy "$@" ;;
    status)   cmd_status "$@" ;;
    ""|-h|--help|help) usage ;;
    *) meru_err "unknown subcommand: $sub"; usage; return 2 ;;
  esac
}

main "$@"
