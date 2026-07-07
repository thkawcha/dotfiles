#!/bin/bash
# create_workload.sh - create/start/delete user resources (workloads) on a
# running local one-node cluster: vnets, vnics, ingresses, images, VMs, volumes.
#
# Requires the resource providers to be deployed (deploy-meru-resource-providers skill):
#   network -> vnet/vnic/ingress, compute -> virtualmachine, image -> image,
#   volume  -> block-device CSI volume.
#
# Resource yamls are generated (parameterized) to match the shared MnM / testbed
# resource shapes. Provider/type pairs match `meructl resource types`.
#
# Subcommands:
#   local-storage [name]                       static backend (type local_storage)
#   vm-instance   [name]                        static backend (type virtual_machine_instance)
#   static-backends [--vnet V]                  local_storage + vm-instance + vnet
#   vnet     <name> [--subnet CIDR] [--gateway IP]
#   nic      <name> --vnet V [--ingress I]
#   ingress  <name> --vnet V --nic N
#   image    <name> [--url URL | --local | --remote]
#   vm       <name> --nic N --image I [--cpu C] [--mem-mib M] [--os-mib M] [--volume VOL]
#   volume   <name> [--size-mib S]
#   delete   <name> --type T --provider P
#   list     --type T --provider P
#   vm-basic        [--name vm1] [--cpu 2] [--mem-mib 2048] [--local|--remote|--image-url URL]
#                   [--skip-backends] [--skip-vnet] [--skip-image]
#                   Orchestrate static-backends + vnet + nic + image + VM (plain VM,
#                   no ingress; mirrors create_and_start_vm_ip1_ubuntu.sh).
#   vm-with-ingress [--name vm1] [--cpu 2] [--mem-mib 2048] [--local|--remote|--image-url URL]
#                   [--skip-backends] [--skip-vnet] [--skip-image]
#                   Orchestrate static-backends + vnet + nic + ingress + image + VM
#                   (the "VM with N cpu and an ingress" scenario).
#   vm-with-volume  [--name vm1_bd] [--cpu 2] [--mem-mib 2048] [--size-mib 4096]
#                   [--local|--remote|--image-url URL] [--skip-backends] [--skip-vnet] [--skip-image]
#                   Orchestrate static-backends + vnet + nic + image + BD volume + VM
#                   (mirrors create_and_start_vm_ip1_ubuntu_test_bd_volume.sh).
#   prefab-image [--output PATH] [--base IMG|URL] [--toolset DIR|TAR]
#                [--os-type linux|windows] [-- EXTRA prefab args]
#                   Produce a local Meru-ready qcow2 by running the Prefab Image
#                   Toolset (from the release packages) against a base cloud
#                   image. Default output is the local file:// image path.
#
# Image options (LOCAL vs REMOTE):
#   --local (default) : use the local file:// image (MERU_IMAGE_URL / MERU_IMAGE_PATH,
#                       default /var/lib/meru/images/ubuntu.qcow2). Build one with
#                       'prefab-image'. No network needed once produced.
#   --remote          : pull from an http(s) image server (MERU_REMOTE_IMAGE_URL,
#                       default the internal meruperi server used by the testbed).
#                       Needs corp network / VPN; the cluster node must reach it too.
#   --url URL         : use an explicit file:// or http(s):// URL.
#
# Defaults: vnet=test_vnet, nic=ip1, ingress=test_ingress, image=ubuntu_image,
#           vm=vm1, cpu=2, mem-mib=2048.

set -uo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../deploy-meru-cluster/_meru_env.sh
source "${SCRIPT_DIR}/../deploy-meru-cluster/_meru_env.sh"

# LOCAL image option: a file:// qcow2 the cluster user can read (produce it with
# 'prefab-image'). This is the default.
DEFAULT_IMAGE_URL="${MERU_IMAGE_URL:-file://${MERU_IMAGE_PATH:-/var/lib/meru/images/ubuntu.qcow2}}"
# REMOTE image option: pull from an http(s) image server (matches the testbed's
# ubuntu_image.yaml, which used the internal meruperi server). Used with --remote.
DEFAULT_REMOTE_IMAGE_URL="${MERU_REMOTE_IMAGE_URL:-http://meruperi.corp.microsoft.com:90/images/ubuntu-22.04-server-cloudimg-amd64.meru_20250904_353526.qcow2}"
# Base (stock) cloud image used by 'prefab-image' when --base is not given.
DEFAULT_BASE_IMAGE_URL="${MERU_BASE_IMAGE_URL:-https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64.img}"


usage() { sed -n '2,52p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

# True if a meructl resource-op response body indicates the op failed. meructl
# exits 0 even when the operation status is "Failed", so we must inspect the
# response: a "Failed" status or a populated error_description ("error": {...}).
# (Async states like "Starting"/"Created"/"Started"/"Stopped" are NOT failures.)
op_indicates_failure() {
  grep -qE '"type"[[:space:]]*:[[:space:]]*"Fail' <<<"$1" && return 0
  grep -qE '"error"[[:space:]]*:[[:space:]]*\{' <<<"$1" && return 0
  return 1
}

# create_and_start <name> <type> <provider> <yaml_file>
create_and_start() {
  local name="$1" rtype="$2" provider="$3" yaml="$4" out rc
  meru_log "creating ${rtype} resource '${name}'"
  out="$(meru_meructl resource create --file-path "$yaml" --name "$name" 2>&1)"; rc=$?
  printf '%s\n' "$out"
  if [ $rc -ne 0 ] || op_indicates_failure "$out"; then
    meru_err "create of ${rtype} '${name}' failed (see status/error above)"; return 1
  fi
  meru_log "starting ${rtype} resource '${name}' (provider ${provider})"
  out="$(meru_meructl resource start --name "$name" --type "$rtype" --provider "$provider" 2>&1)"; rc=$?
  printf '%s\n' "$out"
  if [ $rc -ne 0 ] || op_indicates_failure "$out"; then
    meru_err "start of ${rtype} '${name}' failed (see status/error above)"; return 1
  fi
}

# Pre-flight the image source and print diagnosis hints (warn, never fail).
# Handles both the LOCAL (file://) and REMOTE (http/https) image options.
check_image_url() {
  local url="$1"
  case "$url" in
    file://*)
      local path="${url#file://}"
      if [ ! -f "$path" ]; then
        meru_err "WARNING: [local image] file not found: ${path}"
        meru_err "  Produce one with the 'prefab-image' subcommand, override with"
        meru_err "  MERU_IMAGE_PATH / MERU_IMAGE_URL / --url, or use the remote option (--remote)."
      elif [ ! -r "$path" ]; then
        meru_err "WARNING: [local image] not readable by current user: ${path}"
        meru_err "  The cluster user (meruuser) must be able to read it; check dir + file perms/owner."
      fi
      ;;
    http://*|https://*)
      # Remote option: quick, non-fatal reachability probe from this shell.
      if command -v curl >/dev/null 2>&1; then
        if ! curl -fsI --max-time 8 "$url" >/dev/null 2>&1; then
          meru_err "WARNING: [remote image] URL not reachable from this shell: ${url}"
          meru_err "  Diagnose the remote option:"
          meru_err "   - internal servers (e.g. meruperi.corp.microsoft.com) need corp network / VPN;"
          meru_err "   - confirm DNS + port:  curl -I '${url}'"
          meru_err "   - the image path/tag may have rotated on the server;"
          meru_err "   - the cluster NODE (not just this shell) must also reach the server."
          meru_err "  If it stays unreachable, switch to the local option: 'prefab-image' then --local."
        fi
      fi
      ;;
    *)
      meru_err "WARNING: [image] unrecognized URL scheme (expected file://, http://, https://): ${url}"
      ;;
  esac
}

# ----- resource yaml generators (stdout) -----

# Static backend: local storage (mri v2 shape, minimal).
gen_local_storage() {
  cat <<EOF
type: local_storage
provider_name: local_storage_provider
description: local testbed local_storage backend
EOF
}

# Static backend: virtual machine instance (mri v2 shape, minimal).
gen_vm_instance() {
  cat <<EOF
type: virtual_machine_instance
provider_name: virtual_machine_instance_provider
description: local testbed virtual_machine_instance backend
EOF
}

gen_vnet() {
  local subnet="$1" gateway="$2"
  cat <<EOF
type: vnet
provider_name: vnet_provider
description: local testbed vnet
properties:
  version: v1
  properties:
    subnet: ${subnet}
    gateway: ${gateway}
    dns_config:
      server:
      - 10.50.50.50
      - 10.50.10.50
      - 8.8.8.8
EOF
}

# gen_nic <vnet> [ingress]
gen_nic() {
  local vnet="$1" ingress="${2:-}"
  cat <<EOF
type: vnic
provider_name: vnic_provider
description: local testbed vnic
properties:
  properties:
    ip_assignment: DYNAMIC
    vnet_id: "${vnet}"
EOF
  if [ -n "$ingress" ]; then
    cat <<EOF
    ingress_binding:
      ingress_id: "${ingress}"
      rules:
        - protocol: TCP
          frontend:
            start: 22
            end: 0
          backend:
            start: 22
            end: 0
EOF
  fi
}

# gen_ingress <vnet> <anchor_nic>
gen_ingress() {
  local vnet="$1" nic="$2"
  cat <<EOF
type: ingress
provider_name: ingress_provider
description: local testbed ingress
properties:
  version: v1
  properties:
    vnet_id: ${vnet}
    ip_assignment: DYNAMIC
    type: DHCP
    vnic:
      name: ${nic}
      type: vnic
      provider_name: vnic_provider
EOF
}

gen_image() {
  local url="$1"
  cat <<EOF
type: image
provider_name: image_resource_plugin
provider_properties:
  version: v1
  properties:
    source:
      url: ${url}
      image_format:
        type: QCOW2
EOF
}

# gen_vm <nic> <image> <cpu> <mem_mib> <os_mib> [volume]
gen_vm() {
  local nic="$1" image="$2" cpu="$3" mem="$4" os="$5" volume="${6:-}"
  cat <<EOF
type: virtualmachine
provider_name: virtualmachine_provider
properties:
  properties:
    compute_properties:
      device_profile:
        memoryMib: ${mem}
        cores: ${cpu}
      network_profile:
        network_interface_reference:
          name: ${nic}
          type: vnic
          provider_name: vnic_provider
      storage_profile:
        temporary_volumes:
          - tag: "temp-vol"
            size_mib: 2048
EOF
  if [ -n "$volume" ]; then
    cat <<EOF
        reliable_volumes:
        - tag: rel-vol
          volume_reference:
            name: ${volume}
            type: volume
            provider_name: csi_provider
EOF
  fi
  cat <<EOF
    os_volume:
      image_reference:
        name: ${image}
        type: image
        provider_name: image_resource_plugin
      size_mib: ${os}
      linux_profile: {}
EOF
}

gen_volume() {
  local size_bytes="$1"
  cat <<EOF
type: volume
provider_name: csi_provider
description: local testbed csi volume
properties:
  version: v1
  properties:
    csi_volume:
      provider:
        name: merubdCsiProvider
      description:
        parameters:
          create_volume_parameters: "user_device_type: USER_DEVICE_TYPE_VHOST cpu_set: \"1\"  vss_replica_count: {value: 1}"
        capacityRange:
          requiredBytes: ${size_bytes}
          limitBytes: ${size_bytes}
        volumeCapabilities:
        - accessMode:
            mode: SINGLE_NODE_WRITER
          mount:
            fsType: ext4
            mountFlags:
            - flagA
EOF
}

# ----- subcommands -----

with_tmp_yaml() {  # with_tmp_yaml <generator-output-on-stdin> -> prints path; caller rm's
  local f; f="$(mktemp --suffix=.yaml)"; cat > "$f"; echo "$f"
}

cmd_vnet() {
  local name="${1:-test_vnet}"; shift || true
  local subnet="192.168.10.0/24" gateway="192.168.10.1"
  while [ $# -gt 0 ]; do case "$1" in
    --subnet) subnet="$2"; shift 2;; --gateway) gateway="$2"; shift 2;;
    *) meru_err "unknown arg: $1"; return 2;; esac; done
  meru_setup_venv >&2 || return 1
  local f; f="$(gen_vnet "$subnet" "$gateway" | with_tmp_yaml)"
  create_and_start "$name" vnet vnet_provider "$f"; local rc=$?; rm -f "$f"; return $rc
}

cmd_local_storage() {
  local name="${1:-local_storage}"; shift || true
  [ $# -gt 0 ] && { meru_err "unknown arg: $1"; return 2; }
  meru_setup_venv >&2 || return 1
  local f; f="$(gen_local_storage | with_tmp_yaml)"
  create_and_start "$name" local_storage local_storage_provider "$f"; local rc=$?; rm -f "$f"; return $rc
}

cmd_vm_instance() {
  local name="${1:-virtual_machine_instance}"; shift || true
  [ $# -gt 0 ] && { meru_err "unknown arg: $1"; return 2; }
  meru_setup_venv >&2 || return 1
  local f; f="$(gen_vm_instance | with_tmp_yaml)"
  create_and_start "$name" virtual_machine_instance virtual_machine_instance_provider "$f"; local rc=$?; rm -f "$f"; return $rc
}

# Create the prerequisite static backends (mirrors create_static_resources.sh):
# local_storage + virtual_machine_instance + vnet.
cmd_static_backends() {
  local vnet="test_vnet"
  while [ $# -gt 0 ]; do case "$1" in
    --vnet) vnet="$2"; shift 2;;
    *) meru_err "unknown arg: $1"; return 2;; esac; done
  meru_setup_venv >&2 || return 1
  meru_log "creating static backends (local_storage, virtual_machine_instance, vnet '${vnet}')"
  cmd_local_storage || return 1
  cmd_vm_instance || return 1
  cmd_vnet "$vnet" || return 1
}

cmd_nic() {
  local name="${1:?nic name required}"; shift
  local vnet="test_vnet" ingress=""
  while [ $# -gt 0 ]; do case "$1" in
    --vnet) vnet="$2"; shift 2;; --ingress) ingress="$2"; shift 2;;
    *) meru_err "unknown arg: $1"; return 2;; esac; done
  meru_setup_venv >&2 || return 1
  local f; f="$(gen_nic "$vnet" "$ingress" | with_tmp_yaml)"
  create_and_start "$name" vnic vnic_provider "$f"; local rc=$?; rm -f "$f"; return $rc
}

cmd_ingress() {
  local name="${1:?ingress name required}"; shift
  local vnet="test_vnet" nic=""
  while [ $# -gt 0 ]; do case "$1" in
    --vnet) vnet="$2"; shift 2;; --nic) nic="$2"; shift 2;;
    *) meru_err "unknown arg: $1"; return 2;; esac; done
  if [ -z "$nic" ]; then meru_err "ingress requires --nic <anchor-nic>"; return 2; fi
  meru_setup_venv >&2 || return 1
  local f; f="$(gen_ingress "$vnet" "$nic" | with_tmp_yaml)"
  create_and_start "$name" ingress ingress_provider "$f"; local rc=$?; rm -f "$f"; return $rc
}

cmd_image() {
  local name="${1:-ubuntu_image}"; shift || true
  local url="" mode="local"
  while [ $# -gt 0 ]; do case "$1" in
    --url) url="$2"; mode="explicit"; shift 2;;
    --remote) mode="remote"; shift;;
    --local) mode="local"; shift;;
    *) meru_err "unknown arg: $1"; return 2;; esac; done
  case "$mode" in
    remote) url="${url:-$DEFAULT_REMOTE_IMAGE_URL}";;
    local)  url="${url:-$DEFAULT_IMAGE_URL}";;
  esac
  meru_setup_venv >&2 || return 1
  meru_log "using ${mode} image source: ${url}"
  check_image_url "$url"
  local f; f="$(gen_image "$url" | with_tmp_yaml)"
  create_and_start "$name" image image_resource_plugin "$f"; local rc=$?; rm -f "$f"; return $rc
}

cmd_vm() {
  local name="${1:?vm name required}"; shift
  local nic="" image="ubuntu_image" cpu=2 mem=2048 os=4096 volume=""
  while [ $# -gt 0 ]; do case "$1" in
    --nic) nic="$2"; shift 2;; --image) image="$2"; shift 2;;
    --cpu) cpu="$2"; shift 2;; --mem-mib) mem="$2"; shift 2;;
    --os-mib) os="$2"; shift 2;; --volume) volume="$2"; shift 2;;
    *) meru_err "unknown arg: $1"; return 2;; esac; done
  if [ -z "$nic" ]; then meru_err "vm requires --nic <nic-name>"; return 2; fi
  meru_setup_venv >&2 || return 1
  local f; f="$(gen_vm "$nic" "$image" "$cpu" "$mem" "$os" "$volume" | with_tmp_yaml)"
  create_and_start "$name" virtualmachine virtualmachine_provider "$f"; local rc=$?; rm -f "$f"; return $rc
}

cmd_volume() {
  local name="${1:?volume name required}"; shift
  local size_mib=4096
  while [ $# -gt 0 ]; do case "$1" in
    --size-mib) size_mib="$2"; shift 2;; *) meru_err "unknown arg: $1"; return 2;; esac; done
  meru_setup_venv >&2 || return 1
  local bytes=$(( size_mib * 1024 * 1024 ))
  local f; f="$(gen_volume "$bytes" | with_tmp_yaml)"
  create_and_start "$name" volume csi_provider "$f"; local rc=$?; rm -f "$f"; return $rc
}

cmd_delete() {
  local name="${1:?resource name required}"; shift
  local rtype="" provider=""
  while [ $# -gt 0 ]; do case "$1" in
    --type) rtype="$2"; shift 2;; --provider) provider="$2"; shift 2;;
    *) meru_err "unknown arg: $1"; return 2;; esac; done
  if [ -z "$rtype" ] || [ -z "$provider" ]; then meru_err "delete requires --type and --provider"; return 2; fi
  meru_setup_venv >&2 || return 1
  meru_log "stopping ${rtype} resource '${name}'"
  meru_meructl resource stop --name "$name" --type "$rtype" --provider "$provider" || \
    meru_err "stop failed (continuing to delete)"
  meru_log "deleting ${rtype} resource '${name}'"
  meru_meructl resource delete --name "$name" --type "$rtype" --provider "$provider"
}

cmd_list() {
  local rtype="" provider=""
  while [ $# -gt 0 ]; do case "$1" in
    --type) rtype="$2"; shift 2;; --provider) provider="$2"; shift 2;;
    *) meru_err "unknown arg: $1"; return 2;; esac; done
  if [ -z "$rtype" ] || [ -z "$provider" ]; then meru_err "list requires --type and --provider"; return 2; fi
  meru_meructl resource list --type "$rtype" --provider "$provider"
}

cmd_vm_with_ingress() {
  local vm="vm1" nic="ip1" vnet="test_vnet" ingress="test_ingress" image="ubuntu_image"
  local cpu=2 mem=2048 url="$DEFAULT_IMAGE_URL"
  local skip_backends=0 skip_vnet=0 skip_image=0
  while [ $# -gt 0 ]; do case "$1" in
    --name) vm="$2"; shift 2;; --nic) nic="$2"; shift 2;;
    --vnet) vnet="$2"; shift 2;; --ingress) ingress="$2"; shift 2;;
    --image) image="$2"; shift 2;; --cpu) cpu="$2"; shift 2;;
    --mem-mib) mem="$2"; shift 2;; --image-url) url="$2"; shift 2;;
    --remote) url="$DEFAULT_REMOTE_IMAGE_URL"; shift;;
    --local)  url="$DEFAULT_IMAGE_URL"; shift;;
    --skip-backends) skip_backends=1; shift;;
    --skip-vnet) skip_vnet=1; shift;;
    --skip-image) skip_image=1; shift;;
    *) meru_err "unknown arg: $1"; return 2;; esac; done
  meru_setup_venv >&2 || return 1
  meru_log "=== scenario: VM '${vm}' (${cpu} cpu) with ingress '${ingress}' ==="
  if [ "$skip_backends" -eq 0 ]; then
    # Prerequisite static backends (mirrors create_static_resources.sh):
    # local_storage + virtual_machine_instance + vnet.
    cmd_local_storage || return 1
    cmd_vm_instance || return 1
  fi
  [ "$skip_vnet" -eq 0 ] && { cmd_vnet "$vnet" || return 1; }
  cmd_nic "$nic" --vnet "$vnet" || return 1
  cmd_ingress "$ingress" --vnet "$vnet" --nic "$nic" || return 1
  [ "$skip_image" -eq 0 ] && { cmd_image "$image" --url "$url" || return 1; }
  cmd_vm "$vm" --nic "$nic" --image "$image" --cpu "$cpu" --mem-mib "$mem" || return 1
  meru_log "=== scenario complete: VM '${vm}' + ingress '${ingress}' created ==="
}

# Plain VM sanity flow (no ingress, no volume): mirrors the testbed's
# create_and_start_vm_ip1_ubuntu.sh path (static backends -> vnet -> nic ->
# image -> VM referencing the nic + image).
cmd_vm_basic() {
  local vm="vm1" nic="ip1" vnet="test_vnet" image="ubuntu_image"
  local cpu=2 mem=2048 os=4096 url="$DEFAULT_IMAGE_URL"
  local skip_backends=0 skip_vnet=0 skip_image=0
  while [ $# -gt 0 ]; do case "$1" in
    --name) vm="$2"; shift 2;; --nic) nic="$2"; shift 2;;
    --vnet) vnet="$2"; shift 2;; --image) image="$2"; shift 2;;
    --cpu) cpu="$2"; shift 2;; --mem-mib) mem="$2"; shift 2;;
    --os-mib) os="$2"; shift 2;; --image-url) url="$2"; shift 2;;
    --remote) url="$DEFAULT_REMOTE_IMAGE_URL"; shift;;
    --local)  url="$DEFAULT_IMAGE_URL"; shift;;
    --skip-backends) skip_backends=1; shift;;
    --skip-vnet) skip_vnet=1; shift;;
    --skip-image) skip_image=1; shift;;
    *) meru_err "unknown arg: $1"; return 2;; esac; done
  meru_setup_venv >&2 || return 1
  meru_log "=== scenario: plain VM '${vm}' (${cpu} cpu) ==="
  if [ "$skip_backends" -eq 0 ]; then
    cmd_local_storage || return 1
    cmd_vm_instance || return 1
  fi
  [ "$skip_vnet" -eq 0 ] && { cmd_vnet "$vnet" || return 1; }
  cmd_nic "$nic" --vnet "$vnet" || return 1
  [ "$skip_image" -eq 0 ] && { cmd_image "$image" --url "$url" || return 1; }
  cmd_vm "$vm" --nic "$nic" --image "$image" --cpu "$cpu" --mem-mib "$mem" --os-mib "$os" || return 1
  meru_log "=== scenario complete: plain VM '${vm}' created ==="
}

# VM with a block-device (CSI) volume attached: mirrors the testbed's
# create_and_start_vm_ip1_ubuntu_test_bd_volume.sh path (adds volume + VM
# reliable_volumes reference). Requires the 'volume' resource provider.
cmd_vm_with_volume() {
  local vm="vm1_bd" nic="ip1" vnet="test_vnet" image="ubuntu_image" volume="test_volume"
  local cpu=2 mem=2048 os=4096 size_mib=4096 url="$DEFAULT_IMAGE_URL"
  local skip_backends=0 skip_vnet=0 skip_image=0
  while [ $# -gt 0 ]; do case "$1" in
    --name) vm="$2"; shift 2;; --nic) nic="$2"; shift 2;;
    --vnet) vnet="$2"; shift 2;; --image) image="$2"; shift 2;;
    --volume) volume="$2"; shift 2;; --cpu) cpu="$2"; shift 2;;
    --mem-mib) mem="$2"; shift 2;; --os-mib) os="$2"; shift 2;;
    --size-mib) size_mib="$2"; shift 2;; --image-url) url="$2"; shift 2;;
    --remote) url="$DEFAULT_REMOTE_IMAGE_URL"; shift;;
    --local)  url="$DEFAULT_IMAGE_URL"; shift;;
    --skip-backends) skip_backends=1; shift;;
    --skip-vnet) skip_vnet=1; shift;;
    --skip-image) skip_image=1; shift;;
    *) meru_err "unknown arg: $1"; return 2;; esac; done
  meru_setup_venv >&2 || return 1
  meru_log "=== scenario: VM '${vm}' (${cpu} cpu) with block-device volume '${volume}' ==="
  if [ "$skip_backends" -eq 0 ]; then
    cmd_local_storage || return 1
    cmd_vm_instance || return 1
  fi
  [ "$skip_vnet" -eq 0 ] && { cmd_vnet "$vnet" || return 1; }
  cmd_nic "$nic" --vnet "$vnet" || return 1
  [ "$skip_image" -eq 0 ] && { cmd_image "$image" --url "$url" || return 1; }
  cmd_volume "$volume" --size-mib "$size_mib" || return 1
  cmd_vm "$vm" --nic "$nic" --image "$image" --cpu "$cpu" --mem-mib "$mem" --os-mib "$os" --volume "$volume" || return 1
  meru_log "=== scenario complete: VM '${vm}' + block-device volume '${volume}' created ==="
}

# ----- prefab-image: produce a local Meru-ready qcow2 via the Prefab Image Toolset -----

# Local filesystem path the workloads default image URL points at.
default_local_image_path() {
  case "$DEFAULT_IMAGE_URL" in
    file://*) echo "${DEFAULT_IMAGE_URL#file://}" ;;
    *)        echo "/var/lib/meru/images/ubuntu.qcow2" ;;
  esac
}

# Resolve the prefab-image.sh path. Echoes the script path on stdout.
# Extracts prefab_image_toolset*.tar.gz into $2 (a work dir) when needed.
resolve_prefab_script() {
  local toolset="$1" workdir="$2" tar="" s
  if [ -n "$toolset" ]; then
    if [ -d "$toolset" ]; then
      s="$(find "$toolset" -maxdepth 2 -name prefab-image.sh -type f 2>/dev/null | head -1)"
      [ -n "$s" ] && { echo "$s"; return 0; }
      meru_err "no prefab-image.sh found under toolset dir: $toolset"; return 1
    elif [ -f "$toolset" ]; then
      tar="$toolset"
    else
      meru_err "toolset not found: $toolset"; return 1
    fi
  else
    local ld; ld="$(meru_local_dir)" || return 1
    tar="$(ls -1 "${ld}"/prefab_image_toolset*.tar.gz 2>/dev/null | head -1)"
    if [ -z "$tar" ]; then
      meru_err "prefab_image_toolset*.tar.gz not found in ${ld}; pass --toolset <tar-or-dir> (or set MERU_LOCAL_DIR)"
      return 1
    fi
  fi
  meru_log "extracting prefab toolset: ${tar}" >&2
  tar xzf "$tar" -C "$workdir" >&2 || return 1
  s="$(find "$workdir" -maxdepth 2 -name prefab-image.sh -type f 2>/dev/null | head -1)"
  [ -n "$s" ] && { echo "$s"; return 0; }
  meru_err "prefab-image.sh not found after extracting ${tar}"; return 1
}

# Resolve the base (stock) image to a local path. Downloads http(s) URLs into $2.
resolve_base_image() {
  local base="$1" workdir="$2"
  [ -z "$base" ] && base="$DEFAULT_BASE_IMAGE_URL"
  case "$base" in
    http://*|https://*)
      local out="${workdir}/base-image.img"
      meru_log "downloading base image: ${base}" >&2
      if command -v wget >/dev/null 2>&1; then
        wget -q -c "$base" -O "$out" >&2 || return 1
      else
        curl -fSL "$base" -o "$out" >&2 || return 1
      fi
      echo "$out" ;;
    file://*) echo "${base#file://}" ;;
    *)
      if [ -f "$base" ]; then echo "$base"; else meru_err "base image not found: $base"; return 1; fi ;;
  esac
}

cmd_prefab_image() {
  local output="" base="" toolset="" os_type="linux"
  local -a extra=()
  while [ $# -gt 0 ]; do case "$1" in
    --output|-o) output="$2"; shift 2;;
    --base|-i)   base="$2"; shift 2;;
    --toolset)   toolset="$2"; shift 2;;
    --os-type)   os_type="$2"; shift 2;;
    --)          shift; extra=("$@"); break;;
    *) meru_err "unknown arg: $1"; return 2;;
  esac; done
  [ -z "$output" ] && output="$(default_local_image_path)"

  local workdir; workdir="$(mktemp -d)"
  local script base_img rc=0
  if ! script="$(resolve_prefab_script "$toolset" "$workdir")"; then rm -rf "$workdir"; return 1; fi
  if ! base_img="$(resolve_base_image "$base" "$workdir")"; then rm -rf "$workdir"; return 1; fi

  meru_sudo mkdir -p "$(dirname "$output")" || { rm -rf "$workdir"; return 1; }

  meru_log "prefabbing ${os_type} image"
  meru_log "  toolset: ${script}"
  meru_log "  base:    ${base_img}"
  meru_log "  output:  ${output}"
  # prefab-image.sh needs root (mounts/chroots the rootfs).
  meru_sudo "$script" --os-type "$os_type" -i "$base_img" -o "$output" --force ${extra[@]+"${extra[@]}"}
  rc=$?
  rm -rf "$workdir"
  if [ $rc -ne 0 ]; then meru_err "prefab-image failed (rc=${rc})"; return $rc; fi
  meru_log "produced local image: ${output}"
  meru_log "use it with: $(basename "$0") image ubuntu_image --url file://${output}"
}

main() {
  local sub="${1:-}"
  [ $# -gt 0 ] && shift
  case "$sub" in
    local-storage)   cmd_local_storage "$@" ;;
    vm-instance)     cmd_vm_instance "$@" ;;
    static-backends) cmd_static_backends "$@" ;;
    vnet)            cmd_vnet "$@" ;;
    nic)             cmd_nic "$@" ;;
    ingress)         cmd_ingress "$@" ;;
    image)           cmd_image "$@" ;;
    vm)              cmd_vm "$@" ;;
    volume)          cmd_volume "$@" ;;
    delete)          cmd_delete "$@" ;;
    list)            cmd_list "$@" ;;
    vm-with-ingress) cmd_vm_with_ingress "$@" ;;
    vm-basic)        cmd_vm_basic "$@" ;;
    vm-with-volume)  cmd_vm_with_volume "$@" ;;
    prefab-image)    cmd_prefab_image "$@" ;;
    ""|-h|--help|help) usage ;;
    *) meru_err "unknown subcommand: $sub"; usage; return 2 ;;
  esac
}

main "$@"
