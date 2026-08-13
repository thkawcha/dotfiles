---
name: download-meru-release-bits
description: >-
  Download or refresh the Meru release-package artifact used by local cluster
  deployment through the user's canonical download script. Use when the user
  requests release bits or approves refreshing a missing or stale package
  directory.
allowed-tools: shell
---

# download-meru-release-bits

Thin wrapper around the user's `~/download-latest-release-bits.sh`, which pulls the
latest successful release-pipeline artifact into `~/latest-release-packages`.

## Authority boundary

A download or refresh request authorizes the helper's destructive replacement
of `~/latest-release-packages`. Do not download merely because deployment
preflight reports missing bits; obtain explicit user intent first. Do not
reimplement or bypass the canonical helper's safeguards.

## Usage

```bash
SKILL=~/.copilot/skills/download-meru-release-bits/download_release_bits.sh

# Download the latest release bits into ~/latest-release-packages:
"$SKILL"

# Any extra args are forwarded to the underlying HOME script:
"$SKILL" --id <build-id>
```

## What it does

- Resolves the HOME script (`MERU_DOWNLOAD_SCRIPT` env override →
  `~/download-latest-release-bits.sh` → `~/download-latest-release*.sh`).
- Runs it. The script removes and re-populates `~/latest-release-packages` with
  the `packages_amd64_retail_native` artifact from the release pipeline.

## Notes

- **Azure CLI auth is required** (the download pulls a pipeline artifact). If it
  fails on auth, run plain `az login` first (per user preference, do **not** use
  `--use-device-code`); see the `azure-auth` skill.
- Uses `sudo` internally (the HOME script clears `~/latest-release-packages`).
- After download, deploy with the `deploy-meru-cluster` skill (its default
  `--local-dir` is `~/latest-release-packages`). Ensure the downloaded
  `meru_prod_release_*` version is compatible with your `meru_prod_core_*` build
  (see the deploy-meru-cluster version-compatibility note).
