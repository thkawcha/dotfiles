---
name: download-meru-release-bits
description: >-
  Download the latest Meru release packages (the meru_prod_release_* bits) needed
  to deploy a local cluster, by invoking the user's
  ~/download-latest-release-bits.sh. Use this skill when the user wants to
  "download the latest release bits", "get/refresh the release packages", "grab
  the deploy bits", "update ~/latest-release-packages", or before deploying a
  cluster when the release bits are missing or stale. The download lands in
  ~/latest-release-packages, which is the default `--local-dir` / `MERU_LOCAL_DIR`
  consumed by the `deploy-meru-cluster` and `deploy-meru-cluster-scenario` skills.
---

# download-meru-release-bits

Thin wrapper around the user's `~/download-latest-release-bits.sh`, which pulls the
latest successful release-pipeline artifact into `~/latest-release-packages`.

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
