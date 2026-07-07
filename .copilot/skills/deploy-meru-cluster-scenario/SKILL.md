---
name: deploy-meru-cluster-scenario
description: >-
  Meta-orchestrator that deploys a local one-node Meru cluster for a named
  end-to-end scenario, running the focused deploy-* skills in the right order and
  validating the release-package inputs up front. Use this skill when the user
  asks for a whole outcome rather than a single phase: "deploy a cluster with the
  core managers only", "deploy a cluster with a VM and an ingress", "deploy a VM
  with a block-device volume", "stand up a full cluster with all resource
  providers", "bring up a test cluster for scenario X", or "deploy everything
  needed to test <component>". It figures out
  which components a scenario needs and deploys them in dependency order (cluster
  -> core managers -> resource providers -> workloads), skipping phases already
  present. It does NOT build the bits; if the release packages are missing it
  tells the user to build / specify them. For a single phase, prefer the focused
  skills (deploy-meru-cluster, deploy-meru-core-managers,
  deploy-meru-resource-providers, deploy-meru-workloads) directly.
---

# deploy-meru-cluster-scenario

One entry point that maps a high-level scenario to an ordered run of the focused
deploy-* skills. The focused skills stay modular; this skill orchestrates them.

## How an agent should use it

1. Translate the user's request into a scenario (or a custom component set):
   - "core managers only, no workloads" -> `core-managers`
   - "VM with N cpu and an ingress" -> `vm-with-ingress` (+ `--cpu N`)
   - "everything / all providers" -> `full`
   - "just the cluster" -> `bare`
2. Make sure the release-package inputs are known. The deployer needs:
   - **packages dir** (`--packages-dir`, default `<repo>/out/release/packages`):
     the deployer + install scripts (`meru_prod_core_*`). Built by meru-core.
   - **local-dir** (`--local-dir`, default `~/latest-release-packages`): the
     release bits (`meru_prod_release_*`). Must be **version-compatible** with the
     packages dir (see deploy-meru-cluster troubleshooting). If unsure, ask the
     user to point at the release-packages folder.
3. Run the scenario.

## Scenarios

| Scenario | Deploys |
| -------- | ------- |
| `bare` | cluster only |
| `core-managers` | cluster + 6 core managers |
| `providers` | core-managers + resource providers (default set) |
| `vm` | providers(network,compute,image) + a plain VM (no ingress) |
| `vm-with-ingress` | providers(network,compute,image) + a VM with an ingress |
| `vm-with-volume` | providers(network,compute,image,volume) + a VM with a block-device volume |
| `full` | core-managers + ALL resource providers |

The `vm*` scenarios accept `--local` (default), `--remote`, or `--image-url URL`
to choose the VM image source (forwarded to the workloads skill; see
deploy-meru-workloads "VM image: LOCAL vs REMOTE").

## Usage

```bash
SKILL=~/.copilot/skills/deploy-meru-cluster-scenario/deploy_scenario.sh

# Core managers only:
"$SKILL" deploy --scenario core-managers

# Plain VM sanity test (local image), explicit package dirs:
"$SKILL" deploy --scenario vm --cpu 2 --mem-mib 2048 \
    --packages-dir /home/me/meru-core/out/release/packages \
    --local-dir /home/me/latest-release-packages

# VM with 2 cpu + ingress, using the remote (meruperi) image:
"$SKILL" deploy --scenario vm-with-ingress --cpu 2 --mem-mib 2048 --remote

# VM with a block-device volume:
"$SKILL" deploy --scenario vm-with-volume --cpu 2 --mem-mib 2048

# Full cluster (all RPs), qemu hypervisor:
"$SKILL" deploy --scenario full --hypervisor QEMU

# Custom provider set:
"$SKILL" deploy --scenario providers --components network,compute,image

# Inspect / tear down:
"$SKILL" status
"$SKILL" teardown
"$SKILL" list-scenarios
```

## Behavior

- **Validates inputs first**: confirms the deployer + a single `meru_prod_*` in the
  packages dir and a single `meru_prod_release*` in the local-dir before doing
  anything. Clear error + guidance if missing (it will NOT build for you).
- **Idempotent-ish**: skips the base-cluster deploy if the gateway is already
  reachable, and skips the core managers if `_ism_` is already present. Use
  `--fresh` to force a clean base redeploy.
- **Delegates** each phase to the focused skill; it exports `MERU_PACKAGES_DIR` /
  `MERU_LOCAL_DIR` / `HYPERVISOR` so the child skills inherit the same inputs.

## Notes

- Networking workloads (vnet/vnic/ingress) require host CNI/networking setup; see
  the `deploy-meru-workloads` caveats. The `vm-with-ingress` scenario will create
  the resources but they only become healthy where host networking is configured.
- This skill assumes the bits are already built. To build, see the meru-core /
  meru-release build instructions; then re-run with the correct `--local-dir`.
