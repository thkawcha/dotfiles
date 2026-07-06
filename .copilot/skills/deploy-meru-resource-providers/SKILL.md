---
name: deploy-meru-resource-providers
description: >-
  Deploy (or undeploy) Meru resource-provider controllers and plugins onto a
  running local one-node cluster: network (vnic/vnet/ingress), compute (VM),
  image, local storage, secret store, and block-device CSI volumes. Use this
  skill when the user wants to "deploy the resource providers", "set up the
  compute/network/image plugins", "enable VM/ingress/volume resources", or before
  creating any user workloads (VMs, NICs, ingresses, volumes). Assumes the bare
  cluster and core managers are already up (use `deploy-meru-cluster` then
  `deploy-meru-core-managers` first). It uses the SHARED MnM deployment YAMLs and applies
  one-node adjustments automatically. It does NOT create resources themselves —
  that is the `deploy-meru-workloads` skill.
---

# deploy-meru-resource-providers

Deploys the resource-provider (RP) controllers + plugins that back user
resources. Each RP registers providers the `deploy-meru-workloads` skill then uses to
create resources.

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
