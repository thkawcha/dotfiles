---
name: deploy-meru-cluster
description: >-
  Deploy, inspect, and tear down a local single-node Meru cluster for testing
  operations and validating results against a live cluster. Use this skill when
  the user wants to "deploy a local meru cluster", "stand up a one-node cluster",
  "bring up a test cluster", "run a meructl command against a local cluster",
  "check if my local cluster is up", "wait for an app/manager to be READY", or
  "tear down the local cluster". This is the FOUNDATION skill: it brings up the
  bare cluster (core L0 runtime + envoy), sets up the meructl python venv, and is
  also the entry point for running arbitrary `meructl` operations against the
  cluster (the venv's meructl, run non-interactively). It does NOT deploy the L2
  core managers or any user workloads. To deploy the core managers
  (ISM/SSM/NM/RM/DM/sstore), chain the `deploy-meru-core-managers` skill after
  this one. Assumes the meru-core release bits are already built into
  out/release/packages.
---

# deploy-meru-cluster

Foundation skill for a local one-node Meru cluster. Wraps the documented manual
flow (`core-cluster-deployer.sh` + `installer.sh`) so an agent can bring the
cluster up, talk to it with `meructl`, and tear it down.

## Prerequisites

The deployer takes **two** package inputs:

- **Packages dir** (`out/release/packages`): holds the deployer + install scripts
  (`meru_prod_core_*.tar.gz`, `meru_sdk_core_*.tar.gz`) from the meru-core build.
  Auto-resolved to `<repo-root>/out/release/packages`; override with `MERU_PACKAGES_DIR`.
  Must contain exactly one `meru_prod_*.tar.gz`.
- **Local-dir / release bits** (`--local-dir`): holds the release binaries
  (`meru_prod_release_*.tar.gz`). Defaults to `~/latest-release-packages`; override
  with `MERU_LOCAL_DIR`. Must contain exactly one `meru_prod_release*.tar.gz`.

Both are validated before deploy. Run from anywhere inside the meru-core (or
meru-release) git tree.

## Usage

All commands go through `meru_local_cluster.sh`:

```bash
SKILL=~/.copilot/skills/deploy-meru-cluster/meru_local_cluster.sh

# Bring up a fresh one-node cluster + set up the meructl venv + health-check.
"$SKILL" deploy

# Show cluster state (meructl cluster view).
"$SKILL" status

# Run any meructl operation inside the venv (uses the venv's meructl,
# non-interactively — never the broken global one).
"$SKILL" meructl application list
"$SKILL" meructl resource types
"$SKILL" meructl cluster select --help

# Wait until an application is READY (validation helper).
"$SKILL" wait-app _ssm_ 180

# Remove the local cluster.
"$SKILL" teardown
```

## What `deploy` does

1. Validates the package inputs (one `meru_prod_*.tar.gz` in the packages dir,
   one `meru_prod_release*.tar.gz` in the local-dir).
2. Runs `./core-cluster-deployer.sh -one --legacy --local-dir <local-dir>`
   from the packages dir. This brings up the legacy meru + merucontroller L0
   runtime for a single-node cluster.
3. Sets up the meructl venv via `source ./installer.sh -v`.
4. Verifies the cluster is reachable with `meructl cluster view`.

If `meructl cluster view` reports the cluster is unreachable, check that envoy is
running and that the endpoint is correct (`meructl cluster select`; the local
gateway endpoint is `localhost:19080`).

## Version compatibility (important)

The packages dir (`meru_prod_core_*`) and the `--local-dir` release bits
(`meru_prod_release_*`) **must be version-compatible**. The deployer installs the
core package first (which provides `envoy`, `core.code`, etc.), then overlays the
release `bin/tools` with `--skip-old-files` (which provides `runtime.code/meru`,
the legacy gateway, `ClusterViewer`, etc.). If the two builds are far apart in
version, you get a mismatched install that fails to come up.

Known symptom of a version mismatch: the cluster processes start, `meru` listens
on 19079, but the **19080 gateway never binds** and `meructl` stays unreachable.
The envoy log (`/home/meruuser/meru_diagnostics_logs/node-0/envoy/envoylogs.trace`)
shows the listener being rejected, e.g.:

```
Error adding/updating listener(s) default-listener:
file .../runtime.code/ClusterViewer/build/logo192.png size is 5347 bytes; maximum is 4096
```

Fix: use a `meru_prod_release_*` tar built from roughly the same point in time as
your `meru_prod_core_*` build (e.g. build meru-release from the current submodules
and point `MERU_PACKAGES_DIR`/`MERU_LOCAL_DIR` at its `out/release/packages`).

## Notes

- The deployer runs as root automatically (via `sudo`); the meructl venv and
  `meructl` calls run as the current user. Override the sudo command with the
  `MERU_SUDO` env var if needed. Run where passwordless sudo (or root) is available.
- This skill intentionally stops at the bare cluster. Deploying L2 managers and
  workloads is owned by sibling skills so each stays small and composable:
  - `deploy-meru-core-managers` — deploy the core managers (ISM/SSM/NM/RM/DM/sstore).
  - `deploy-meru-resource-providers` — compute/network/image/storage RPs.
  - `deploy-meru-workloads` — create VMs, ingresses, volumes, etc.
  - `deploy-meru-cluster-scenario` — meta-orchestrator that runs the above in
    order for a named scenario.
- `_meru_env.sh` holds shared helpers (packages-dir resolution + venv activation
  + a `meru_meructl` wrapper) that the sibling skills source.
