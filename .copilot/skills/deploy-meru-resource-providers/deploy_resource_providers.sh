#!/bin/bash
# deploy_resource_providers.sh - deploy/undeploy Meru resource-provider
# controllers + plugins onto a running local one-node cluster.
#
# Components (each = a controller + a plugin/agent), deployed in this order:
#   secret         secret store     (ss_controller, ss_agent)
#   network        vnic/vnet/ingress(net_rp_controller, net_rp_plugin)
#   local_storage  local storage    (local_storage_controller, local_storage_plugin)
#   compute        VM / vm_instance (compute_controller, vm_rp)
#   process        process workloads(process_rp)  [reuses compute_controller]
#   image          images           (image_controller, image_plugin)
#   volume         block-device CSI (volume-manager, volumes)  [opt-in]
#
# Source YAMLs are the SHARED MnM deployment definitions:
#   ext/test-infra/src/admin/mnm/common/*.yaml
# (self-contained @VAR@ templating resolved from each file's environmentOverrides).
#
# One-node adjustments applied automatically:
#   - volume-manager replicaCount -> 1
#   - vm_rp gets VMMD_HYPERVISOR_SEL (HYPERVISOR env, default CHV; CHV or QEMU)
#   - volume node-agent DATA_PLANE_ENV can be overridden via VOLUME_DATA_PLANE_ENV
#     (default keeps the shared MnM value "--file-size 32768", file-backed). For
#     hosts without real block storage, use the testbed's emulated-loopback config:
#       VOLUME_DATA_PLANE_ENV="--file-size 8192 --cpu-set f --transport-emulated-devices lo --transport-receive-buffers 65536 --transport-send-buffers 65536"
#
# Subcommands:
#   deploy    [components]   Deploy the given components (default: all but volume).
#   undeploy  [components]   Delete the given components (reverse order).
#   status                   List deployed applications.
#
# 'components' is a comma-separated subset of:
#   secret,network,local_storage,compute,image,volume   (or 'all').
# Default when omitted: secret,network,local_storage,compute,image (volume opt-in).
set -uo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../deploy-meru-cluster/_meru_env.sh
source "${SCRIPT_DIR}/../deploy-meru-cluster/_meru_env.sh"

HYPERVISOR="${HYPERVISOR:-CHV}"
# Optional override for the block-device data-plane env (volume_node_agent.yaml
# DATA_PLANE_ENV). Empty keeps the shared MnM value; set it to reproduce the
# testbed's one-node emulated-loopback config on hosts without real storage.
VOLUME_DATA_PLANE_ENV="${VOLUME_DATA_PLANE_ENV:-}"
DEFAULT_COMPONENTS="secret,network,local_storage,compute,image"
ALL_COMPONENTS="secret,network,local_storage,compute,process,image,volume"

usage() { sed -n '2,32p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

# component|app_name|yaml_basename|enlightened(0/1)   -- in deploy order.
provider_specs() {
  cat <<'EOF'
secret|ss_controller|sstore_controller.yaml|0
secret|ss_agent|sstore_agent.yaml|0
network|net_rp_controller|net_rp_controller.yaml|0
network|net_rp_plugin|net_rp_plugin.yaml|0
local_storage|local_storage_controller|local_storage_controller.yaml|0
local_storage|local_storage_plugin|local_storage_plugin.yaml|0
compute|compute_controller|compute_controller.yaml|0
compute|vm_rp|vm_plugin.yaml|0
process|process_rp|process_plugin.yaml|0
image|image_controller|image_controller.yaml|0
image|image_plugin|image_plugin.yaml|0
volume|volume-manager|volume_manager_stateful.yaml|1
volume|volumes|volume_node_agent.yaml|1
EOF
}

mnm_common_dir() {
  local root
  root="$(meru_repo_root)" || return 1
  echo "${root}/ext/test-infra/src/admin/mnm/common"
}

# Render an RP yaml with one-node adjustments into $2 (dest).
render_provider_yaml() {
  local src="$1" dest="$2"
  if [ ! -f "$src" ]; then meru_err "source yaml not found: $src"; return 1; fi
  cp "$src" "$dest" || return 1
  case "$(basename "$src")" in
    volume_manager_stateful.yaml)
      sed -i -e "s/^\(\s*replicaCount:\s*\).*/\11/" "$dest"
      ;;
    vm_plugin.yaml)
      # Inject the hypervisor selector into the template's environmentVariables.
      if ! grep -q "VMMD_HYPERVISOR_SEL" "$dest"; then
        sed -i -e "s/^\(\s*\)\(environmentVariables:\s*\)$/\1\2\n\1  VMMD_HYPERVISOR_SEL: \"${HYPERVISOR}\"/" "$dest"
      fi
      ;;
    volume_node_agent.yaml)
      # Optionally override the block-device data-plane env (e.g. to use the
      # testbed's emulated-loopback config on a host without real storage).
      if [ -n "$VOLUME_DATA_PLANE_ENV" ]; then
        sed -i -e "s|^\(\s*DATA_PLANE_ENV:\s*\).*|\1\"${VOLUME_DATA_PLANE_ENV}\"|" "$dest"
      fi
      ;;
  esac
}

# Echo selected components (validated) as space-separated, in canonical order.
resolve_components() {
  local req="${1:-$DEFAULT_COMPONENTS}"
  [ "$req" = "all" ] && req="$ALL_COMPONENTS"
  local canon c valid out=""
  IFS=',' read -ra req_arr <<< "$req"
  for c in "${req_arr[@]}"; do
    c="$(echo "$c" | tr -d '[:space:]')"
    [ -z "$c" ] && continue
    valid=0
    for canon in secret network local_storage compute process image volume; do
      [ "$c" = "$canon" ] && valid=1 && break
    done
    if [ "$valid" -eq 0 ]; then meru_err "unknown component: $c"; return 1; fi
    out="${out} ${c}"
  done
  echo "$out"
}

selected_has() {
  local needle="$1"; shift
  local c
  for c in "$@"; do [ "$c" = "$needle" ] && return 0; done
  return 1
}

cmd_deploy() {
  local components mnm tmp
  components="$(resolve_components "${1:-}")" || return 1
  mnm="$(mnm_common_dir)" || return 1
  meru_setup_venv >&2 || return 1
  tmp="$(mktemp -d)"
  meru_log "deploying resource providers (components:${components}; hypervisor:${HYPERVISOR})"

  local comp app yaml enl src dest failed=0
  while IFS='|' read -r comp app yaml enl; do
    [ -z "$comp" ] && continue
    selected_has "$comp" $components || continue
    src="${mnm}/${yaml}"; dest="${tmp}/${yaml}"
    meru_log "rendering ${app} (${comp}) from ${yaml}"
    render_provider_yaml "$src" "$dest" || { failed=1; break; }
    local enl_flag=""; [ "$enl" = "1" ] && enl_flag="--enlightened"
    meru_log "creating application ${app} ${enl_flag}"
    if ! meru_meructl application create --file-path "$dest" $enl_flag; then
      meru_err "failed to create application ${app}"
      failed=1; break
    fi
  done < <(provider_specs)

  rm -rf "$tmp"
  if [ "$failed" -ne 0 ]; then meru_err "resource provider deployment aborted"; return 1; fi
  meru_log "resource providers deployed"
}

cmd_undeploy() {
  local components
  components="$(resolve_components "${1:-}")" || return 1
  meru_setup_venv >&2 || return 1
  local apps app
  mapfile -t apps < <(provider_specs | while IFS='|' read -r comp app yaml enl; do
      selected_has "$comp" $components && echo "$app"; done | tac)
  for app in "${apps[@]}"; do
    [ -z "$app" ] && continue
    meru_log "deleting application ${app}"
    meru_meructl application delete --application-name "$app" || \
      meru_err "delete of ${app} failed (continuing)"
  done
}

cmd_status() { meru_meructl application list; }

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
