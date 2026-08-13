---
name: deploy-meru-core-managers
description: >-
  Deploy or undeploy the six L2 core managers on a running local one-node Meru
  cluster using shared E2E/MnM YAMLs with one-node substitutions. Use for ISM,
  SSM, NM, RM, DM, and sstore only; providers and workloads are separate skills.
allowed-tools: shell
---

# deploy-meru-core-managers

Deploys the six L2 core managers onto an already-running local one-node cluster.

## Authority boundary

A deployment request authorizes creating these six local applications.
Undeploy only when the user explicitly requests removal or an approved fresh
scenario; do not use undeploy as an automatic retry strategy.

## Prerequisites

- A bare local cluster is already up and `meructl` is reachable. Bring it up with
  the `deploy-meru-cluster` skill (`meru_local_cluster.sh deploy`).
- The meru-core git tree is available (the shared manager YAMLs are read from it).

## Shared YAML sources (why these)

| Manager | Source YAML |
| ------- | ----------- |
| ISM, SSM, NM, RM, DM | `ext/test-infra/src/eris/lib/eris/apps/*.yaml` |
| Secret Store (sstore) | `ext/test-infra/src/admin/mnm/common/sstore.yaml` |

These are the definitions used in nightly E2E / MnM deployments, so they stay
current (they include fields the old testbed copies were missing, e.g.
`meru_service_principal`, v1 async gRPC prefixes, `deploymentDescription`).

The eris YAMLs contain placeholders that are substituted for a one-node cluster:

| Placeholder | Default | Override env var |
| ----------- | ------- | ---------------- |
| `REPLICA_COUNT_REPLACE` | `1` | `REPLICA_COUNT` |
| `ENABLE_SSM_V2_REPLACE` | `0` | `ENABLE_SSM_V2` |
| `ENABLE_NM_V2_REPLACE` | `0` | `ENABLE_NM_V2` |

`sstore.yaml` (mnm common) has no replica placeholder, so its `replicaCount` is
forced to the one-node value.

## Usage

```bash
SKILL=~/.copilot/skills/deploy-meru-core-managers/deploy_core_managers.sh

# Deploy all six core managers (enlightened), in dependency order.
"$SKILL" deploy

# List deployed applications.
"$SKILL" status

# Remove all six core managers (reverse order).
"$SKILL" undeploy

# Enable SSM v2 / NM v2 paths:
ENABLE_SSM_V2=1 ENABLE_NM_V2=1 "$SKILL" deploy
```

## Deploy order

`ISM -> SSM -> Node Manager -> Resource Manager -> Deployment Manager -> Secret Store`,
each created with `meructl application create --file-path <rendered> --enlightened`.
Rendered YAMLs are written to a temp dir and cleaned up afterward.

## Notes

- "Core managers only, no user workloads" = `deploy-meru-cluster deploy` then this
  skill's `deploy`.
- To create user workloads (VMs, ingresses, volumes) you also need resource
  providers and resource definitions — owned by the (future) sibling skills
  `deploy-meru-resource-providers` and `deploy-meru-workloads`.
- Shared helpers (venv activation, `meru_meructl`) come from
  `../deploy-meru-cluster/_meru_env.sh`.
