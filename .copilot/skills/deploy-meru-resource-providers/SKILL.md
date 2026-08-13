---
name: deploy-meru-resource-providers
description: >-
  Deploy or undeploy local Meru resource-provider controllers and plugins for
  secret, network, local storage, compute, image, or block-device volume
  resources. Requires a running bare cluster and core managers, uses shared MnM
  YAMLs with one-node adjustments, and does not create workloads.
allowed-tools: shell
---

# deploy-meru-resource-providers

Deploys the resource-provider (RP) controllers + plugins that back user
resources. Each RP registers providers the `deploy-meru-workloads` skill then uses to
create resources.

## Authority boundary

A provider deployment request authorizes creating the selected local
applications. Undeploy only when the user explicitly requests removal or an
approved fresh scenario. Keep the volume provider opt-in because it changes
host and kernel prerequisites.

## Prerequisites

- Bare cluster up (`deploy-meru-cluster`) and core managers deployed
  (`deploy-meru-core-managers`). The Resource Manager (`_resource_manager_`) must be READY.

## Components

| Component | Apps | Enables resource types |
| --------- | ---- | ---------------------- |
| `secret` | ss_controller, ss_agent | `secret` |
| `network` | net_rp_controller, net_rp_plugin | `vnic`, `vnet`, `ingress` |
| `local_storage` | local_storage_controller, local_storage_plugin | `local_storage` |
| `compute` | compute_controller, vm_rp | `virtualmachine`, `virtual_machine_instance` |
| `image` | image_controller, image_plugin | `image` |
| `volume` | volume-manager, volumes | `volume` (block-device CSI) |

Source YAMLs: `ext/test-infra/src/admin/mnm/common/*.yaml` (shared MnM deployment
definitions; self-contained `@VAR@` templating resolved from each file's own
`environmentOverrides`).

## One-node adjustments (automatic)

- `volume-manager` `replicaCount` -> 1.
- `vm_rp` gets `VMMD_HYPERVISOR_SEL` from the `HYPERVISOR` env var (default `CHV`;
  set `QEMU` for the qemu hypervisor).
- The block-device **node-agent data-plane env** (`volume_node_agent.yaml`
  `DATA_PLANE_ENV`) can be overridden with `VOLUME_DATA_PLANE_ENV`.

### Block-device (volume) data-plane: file-backed vs emulated-loopback

The shared MnM `volume_node_agent.yaml` uses a **file-backed** data plane
(`DATA_PLANE_ENV: "--file-size 32768"`), which is what runs in E2E/MnM and on a
standard dev box. The original testbed `bd_node.yaml` instead used an
**emulated-loopback** data plane. The controller YAML
(`volume_manager_stateful.yaml`) is otherwise identical to the testbed's
`bd_controller_onenode.yaml` apart from `replicaCount` (forced to 1 here).

If block-device volumes fail to come up on a host without real storage, reproduce
the testbed's emulated config:

```bash
VOLUME_DATA_PLANE_ENV="--file-size 8192 --cpu-set f --transport-emulated-devices lo --transport-receive-buffers 65536 --transport-send-buffers 65536" \
  "$SKILL" deploy all
```

Diagnosing volume problems:
- `... meructl application list` — `volume-manager` and `volumes` should be READY.
- Check the node-agent process is up: `ps -ef | grep 'volume_rp.code/volume'`
  (file-backed shows `volume --file-size <N>`).
- `volume` create failures usually mean the CSI node agent can't back the store:
  confirm the data-plane env matches the host (file-backed needs writable storage
  under the app work dir; emulated needs the named device, e.g. `lo`).
- Block-device CSI may also require chibd host/kernel setup.

## Usage

```bash
SKILL=~/.copilot/skills/deploy-meru-resource-providers/deploy_resource_providers.sh

# Deploy the default set (everything except block-device volumes):
"$SKILL" deploy

# Deploy only what a VM + ingress needs:
"$SKILL" deploy network,compute,image

# Deploy everything including block-device CSI volumes:
"$SKILL" deploy all

# Use the qemu hypervisor for the VM plugin:
HYPERVISOR=QEMU "$SKILL" deploy network,compute,image

# Inspect / tear down:
"$SKILL" status
"$SKILL" undeploy            # default set
"$SKILL" undeploy all        # everything
```

`components` is a comma-separated subset of
`secret,network,local_storage,compute,image,volume` (or `all`). The default
(when omitted) is `secret,network,local_storage,compute,image` — `volume` is
opt-in because block-device CSI needs extra host/kernel setup (chibd).

## Notes

- Controllers are deployed before their plugins; `volume` apps are enlightened
  (stateful), the rest are not.
- After deploy, confirm providers with
  `~/.copilot/skills/deploy-meru-cluster/meru_local_cluster.sh meructl resource types`
  and app health with `... meructl application list`.
