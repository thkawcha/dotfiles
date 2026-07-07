#!/bin/bash
# deploy_scenario.sh - meta-orchestrator that brings up a local one-node Meru
# cluster for a named scenario by running the focused deploy-* skills in
# dependency order. Validates the release-package inputs up front.
#
# Scenarios (what gets deployed):
#   bare             cluster only (L0 runtime + gateway)
#   core-managers    bare + the 6 core managers (no resource providers/workloads)
#   providers        core-managers + resource providers (default RP component set)
#   vm               providers(network,compute,image) + a plain VM (nic + image, no ingress)
#   vm-with-ingress  providers(network,compute,image) + a VM with an ingress
#   vm-with-volume   providers(network,compute,image,volume) + a VM with a BD volume
#   full             core-managers + ALL resource providers (incl. block-device)
#
# Usage:
#   deploy_scenario.sh deploy --scenario <name> [options]
#   deploy_scenario.sh status
#   deploy_scenario.sh teardown
#   deploy_scenario.sh list-scenarios
#
# Options:
#   --scenario NAME        one of the scenarios above (required for deploy)
#   --packages-dir DIR     deployer + install scripts dir (meru_prod_core_*).
#                          Sets MERU_PACKAGES_DIR. Default: <repo>/out/release/packages
#   --local-dir DIR        release bits dir (meru_prod_release_*). Sets MERU_LOCAL_DIR.
#                          Default: ~/latest-release-packages
#   --components LIST       override RP component set (providers/full scenarios)
#   --hypervisor CHV|QEMU  VM hypervisor (default CHV)
#   --cpu N                VM vCPUs for the vm* scenarios (default 2)
#   --mem-mib N            VM memory MiB for the vm* scenarios (default 2048)
#   --local                use the LOCAL file:// VM image (default)
#   --remote               use the REMOTE (meruperi) http VM image
#   --image-url URL        use an explicit VM image URL
#   --fresh                force a clean redeploy of the base cluster even if up
#
# This skill ONLY orchestrates; each phase is owned by a focused skill:
#   deploy-meru-cluster, deploy-meru-core-managers,
#   deploy-meru-resource-providers, deploy-meru-workloads.
# It does NOT build the bits; if they are missing it tells you to build first.

set -uo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../deploy-meru-cluster/_meru_env.sh
source "${SCRIPT_DIR}/../deploy-meru-cluster/_meru_env.sh"

CLUSTER_SKILL="${SCRIPT_DIR}/../deploy-meru-cluster/meru_local_cluster.sh"
MANAGERS_SKILL="${SCRIPT_DIR}/../deploy-meru-core-managers/deploy_core_managers.sh"
PROVIDERS_SKILL="${SCRIPT_DIR}/../deploy-meru-resource-providers/deploy_resource_providers.sh"
WORKLOADS_SKILL="${SCRIPT_DIR}/../deploy-meru-workloads/create_workload.sh"

usage() { sed -n '2,39p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

SCENARIO=""
COMPONENTS=""
HYPERVISOR_OPT=""
CPU=2
MEM_MIB=2048
FRESH=0
IMAGE_OPT=()   # forwarded to the workloads skill (--local | --remote | --image-url URL)

parse_opts() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --scenario)     SCENARIO="$2"; shift 2;;
      --packages-dir) export MERU_PACKAGES_DIR="$2"; shift 2;;
      --local-dir)    export MERU_LOCAL_DIR="$2"; shift 2;;
      --components)   COMPONENTS="$2"; shift 2;;
      --hypervisor)   HYPERVISOR_OPT="$2"; shift 2;;
      --cpu)          CPU="$2"; shift 2;;
      --mem-mib)      MEM_MIB="$2"; shift 2;;
      --local)        IMAGE_OPT=(--local); shift;;
      --remote)       IMAGE_OPT=(--remote); shift;;
      --image-url)    IMAGE_OPT=(--image-url "$2"); shift 2;;
      --fresh)        FRESH=1; shift;;
      *) meru_err "unknown option: $1"; return 2;;
    esac
  done
}

# Validate the release-package inputs before doing anything destructive.
validate_inputs() {
  local pkg local_dir rel
  pkg="$(meru_packages_dir)" || return 1
  local_dir="$(meru_local_dir)" || return 1
  meru_log "packages dir (script_path): ${pkg}"
  meru_log "release bits (--local-dir): ${local_dir}"
  if [ ! -x "${pkg}/core-cluster-deployer.sh" ]; then
    meru_err "deployer not found in packages dir: ${pkg}"
    meru_err "build the release bits, or pass --packages-dir <dir-with-core-cluster-deployer.sh>."
    return 1
  fi
  if ! rel="$(meru_check_release_bits)"; then
    meru_err "release bits not valid. Build a matching meru_prod_release_*.tar.gz or pass"
    meru_err "  --local-dir <dir-with-meru_prod_release_*.tar.gz>  (and --packages-dir if needed)."
    return 1
  fi
  meru_log "release bits OK: ${rel}"
}

# Ensure the base cluster is up (deploy if needed or if --fresh).
phase_base() {
  if [ "$FRESH" -eq 0 ] && meru_cluster_reachable; then
    meru_log "[base] cluster already reachable; skipping (use --fresh to redeploy)"
    return 0
  fi
  meru_log "[base] deploying one-node cluster ..."
  "$CLUSTER_SKILL" deploy
}

# True if a core manager (_ism_) is already deployed.
managers_present() {
  meru_meructl application list 2>/dev/null | grep -q '"_ism_"'
}

phase_managers() {
  if [ "$FRESH" -eq 0 ] && managers_present; then
    meru_log "[managers] core managers already present; skipping"
    return 0
  fi
  meru_log "[managers] deploying core managers ..."
  "$MANAGERS_SKILL" deploy
}

phase_providers() {
  local comps="$1"
  meru_log "[providers] deploying resource providers: ${comps}"
  if [ -n "$HYPERVISOR_OPT" ]; then export HYPERVISOR="$HYPERVISOR_OPT"; fi
  "$PROVIDERS_SKILL" deploy "$comps"
}

phase_workload_vm_ingress() {
  meru_log "[workload] creating VM (${CPU} cpu) with ingress ..."
  "$WORKLOADS_SKILL" vm-with-ingress --cpu "$CPU" --mem-mib "$MEM_MIB" ${IMAGE_OPT[@]+"${IMAGE_OPT[@]}"}
}

phase_workload_vm_basic() {
  meru_log "[workload] creating plain VM (${CPU} cpu) ..."
  "$WORKLOADS_SKILL" vm-basic --cpu "$CPU" --mem-mib "$MEM_MIB" ${IMAGE_OPT[@]+"${IMAGE_OPT[@]}"}
}

phase_workload_vm_volume() {
  meru_log "[workload] creating VM (${CPU} cpu) with a block-device volume ..."
  "$WORKLOADS_SKILL" vm-with-volume --cpu "$CPU" --mem-mib "$MEM_MIB" ${IMAGE_OPT[@]+"${IMAGE_OPT[@]}"}
}

cmd_deploy() {
  parse_opts "$@" || return $?
  if [ -z "$SCENARIO" ]; then meru_err "deploy requires --scenario <name>"; usage; return 2; fi

  validate_inputs || return 1

  case "$SCENARIO" in
    bare)
      phase_base || return 1
      ;;
    core-managers)
      phase_base || return 1
      phase_managers || return 1
      ;;
    providers)
      phase_base || return 1
      phase_managers || return 1
      phase_providers "${COMPONENTS:-secret,network,local_storage,compute,image}" || return 1
      ;;
    vm)
      phase_base || return 1
      phase_managers || return 1
      phase_providers "${COMPONENTS:-network,compute,image}" || return 1
      phase_workload_vm_basic || return 1
      ;;
    vm-with-ingress)
      phase_base || return 1
      phase_managers || return 1
      phase_providers "${COMPONENTS:-network,compute,image}" || return 1
      phase_workload_vm_ingress || return 1
      ;;
    vm-with-volume)
      phase_base || return 1
      phase_managers || return 1
      phase_providers "${COMPONENTS:-network,compute,image,volume}" || return 1
      phase_workload_vm_volume || return 1
      ;;
    full)
      phase_base || return 1
      phase_managers || return 1
      phase_providers "${COMPONENTS:-all}" || return 1
      ;;
    *)
      meru_err "unknown scenario: ${SCENARIO}"; cmd_list_scenarios; return 2
      ;;
  esac
  meru_log "=== scenario '${SCENARIO}' deployed ==="
  meru_log "inspect with: deploy-meru-cluster-scenario/deploy_scenario.sh status"
}

cmd_status() { meru_meructl application list; }

cmd_teardown() { "$CLUSTER_SKILL" teardown; }

cmd_list_scenarios() {
  cat >&2 <<'EOF'
Scenarios:
  bare             cluster only
  core-managers    cluster + 6 core managers (no providers/workloads)
  providers        core-managers + resource providers (default set)
  vm               providers(network,compute,image) + a plain VM (no ingress)
  vm-with-ingress  providers(network,compute,image) + a VM with an ingress
  vm-with-volume   providers(network,compute,image,volume) + a VM with a BD volume
  full             core-managers + ALL resource providers
EOF
}

main() {
  local sub="${1:-}"
  [ $# -gt 0 ] && shift
  case "$sub" in
    deploy)         cmd_deploy "$@" ;;
    status)         cmd_status "$@" ;;
    teardown)       cmd_teardown "$@" ;;
    list-scenarios) cmd_list_scenarios "$@" ;;
    ""|-h|--help|help) usage ;;
    *) meru_err "unknown subcommand: $sub"; usage; return 2 ;;
  esac
}

main "$@"
