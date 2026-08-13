---
name: wsl-kernel-headers
description: >-
  Build and install version-matching headers for the running WSL2 Microsoft
  kernel so out-of-tree modules such as chibd can compile. Use when the kernel
  build tree is missing or an injected header archive lacks it. WSL2-only,
  privileged, network- and disk-intensive. Do not use for a
  GENHD_FL_NO_PART_SCAN source compatibility error.
argument-hint: "Optional subcommand: status | sync (default) | clean."
allowed-tools: shell
---

# WSL2 Kernel Headers for Out-of-Tree Modules

Provides a real, version-matching `/lib/modules/$(uname -r)/build` tree for the
running **WSL2 custom Microsoft kernel** so out-of-tree kernel modules can be
built. In meru-core this is required by the `chibd` block-device kernel module
(built unconditionally by `ext/bd` / meru-core `CMakeLists.txt`), which otherwise
fails the build on WSL2.

## Authority boundary

`status` is read-only and may be used during diagnosis. `sync` installs packages,
clones and builds a large kernel tree, writes under `/usr/src` and
`/lib/modules`, and removes stale caches and older header trees; run it only
after the user explicitly requests or approves those effects. `clean` is
destructive and always requires explicit user intent. Do not start Docker in WSL;
ask the user to do so when container-image work is needed.

## Relationship to the containerized `./build.sh` (read first)

The standard meru-core build runs **inside a container**, and chibd compiles
there — not on the host. The container image bakes in kernel headers via
`images/ubuntu/install-dev-env-dependencies.sh` (`Phase2`). To provide them, the
host assembles the running kernel's headers into a tarball (`container-run.sh`
archives `/lib/modules/$(uname -r)` plus `/usr/src/linux-headers-$(uname -r)-*`)
that the image extracts.

**Two conditions gate this, and both bite on WSL2:**

- **The tarball is only injected on `aarch64` OR when `--copy-kernel-headers` is
  passed** (`container-run.sh` sets `COPY_KERNEL_HEADERS=true` only from that
  flag). WSL2 is **x86_64**, so injection does **not** happen automatically —
  you must pass `--copy-kernel-headers` to `./build.sh` (or `container-run.sh`).
  Without it, `Phase2` falls back to generic Ubuntu headers, which surfaces later
  as the `GENHD_FL_NO_PART_SCAN` compile mismatch in `chibd_quirks.h`.
- **Headers are only baked when the image is (re)built.** The whole
  injection block in `container-run.sh` is guarded by "build local image if it
  doesn't exist", so passing `--copy-kernel-headers` on a build that reuses a
  cached local image is a no-op. After staging/refreshing host headers you must
  **remove the cached local build image** so the flag takes effect on the
  rebuild.

If that tarball carries **no** `build/` tree — the default WSL2 state, because
Microsoft ships no matching `linux-headers` apt package — `Phase2` now
**fails fast** with an error that points at this skill, rather than silently
installing mismatched generic headers (which only surface later as confusing
compile errors such as the `GENHD_FL_NO_PART_SCAN` mismatch in
`chibd_quirks.h`).

**This skill is the remedy for that WSL2 case:** run it once on the host to build
and stage real matching headers. It installs a real tree under
`/usr/src/linux-headers-$(uname -r)-wsl` (a path the host tarball glob captures)
and clears the stale `~/kernel-headers-<ver>.tar.gz` cache. Then rebuild the
image **on x86_64 WSL2 you must pass `--copy-kernel-headers` and first remove the
cached local build image** (see the gating conditions above); with both in place
`container-run.sh` regenerates the tarball with the real build tree inside, and
chibd compiles.

## When to Use

If a **containerized** `./build.sh` on WSL2 fails at the chibd step with:

```
make -C /lib/modules/6.18.33.1-microsoft-standard-WSL2/build M=.../deps/chibd modules
make[1]: *** /lib/modules/6.18.33.1-microsoft-standard-WSL2/build: No such file or directory.  Stop.
```

or the image build aborts in `Phase2` with:

```
ERROR: the kernel headers tarball has no build tree for <uname -r>.
```

then run this skill on the host to build and stage the matching headers, then
remove the local build image and rebuild with `--copy-kernel-headers` (required
on x86_64 WSL2 — see "Relationship to the containerized `./build.sh`" above).

**Do NOT** use this skill for the `GENHD_FL_NO_PART_SCAN undeclared` _compile_
error inside `chibd_quirks.h` -- that is a different problem handled by the
`fix-chibd-kernel-mismatch` skill. This skill fixes the case where there is no
kernel build tree at all.

## Root Cause

WSL2 runs a custom Microsoft kernel (`uname -r` ends in
`-microsoft-standard-WSL2`). Microsoft does **not** publish an apt
`linux-headers` package matching it, so `/lib/modules/$(uname -r)/build` does not
exist. Any out-of-tree module Makefile that does
`make -C /lib/modules/$(uname -r)/build M=... modules` fails immediately. Because
the module is invoked via `env -i ... make all` (a stripped environment), warning
knobs like `KBUILD_MODPOST_WARN` cannot be injected, and the running config has
`CONFIG_MODVERSIONS=y`, so a real `Module.symvers` is needed for modpost to link
cleanly. This skill builds exactly that.

## What the Skill Does

`wsl_kernel_headers.sh` (in this directory):

1. Derives the upstream tag from `uname -r`
   (`6.18.33.1-microsoft-standard-WSL2` -> `linux-msft-wsl-6.18.33.1`) and
   verifies it exists in `microsoft/WSL2-Linux-Kernel`.
2. Installs build deps if missing (`build-essential bc bison flex cpio
libssl-dev libelf-dev`).
3. Shallow-clones the tag into a scratch dir under `~/wsl2-kernel-headers/`.
4. Applies the running kernel's config from `/proc/config.gz` (fallback:
   `Microsoft/config-wsl`), runs `olddefconfig`.
5. Builds with `make -j$(nproc)` so a real `Module.symvers` is produced.
6. Prunes kernel `*.o`/`*.cmd` objects (keeps `scripts/`, headers, and
   `Module.symvers`) to shrink the tree from ~19GB to ~7GB.
7. Installs the pruned tree to `/usr/src/linux-headers-$(uname -r)-wsl` and
   `sudo ln -sfn` it at `/lib/modules/$(uname -r)/build`.
8. Removes the stale `~/kernel-headers-<uname -r>.tar.gz` container cache so
   `container-run.sh` regenerates it with the real build tree inside.
9. Removes header trees, build symlinks, and stale caches for **other** kernel
   versions.

## Usage

```bash
SKILL=scripts/wsl-kernel-headers/wsl_kernel_headers.sh   # from the build-infra repo root

# Check current state:
"$SKILL" status

# Build/install/link headers for the running kernel, then clean up old versions:
"$SKILL" sync        # (default subcommand)

# Only remove header trees/links/caches for non-running kernels:
"$SKILL" clean
```

`sync` is idempotent: if the headers already exist and are linked, it skips the
build and just cleans up older versions.

### Rebuilding the container image after staging headers

Staging headers on the host is only half the job — the image must be rebuilt to
bake them in, and on **x86_64 WSL2** that requires the `--copy-kernel-headers`
flag (see the gating conditions above). Because the injection block only runs
when the local image does **not** already exist, remove the cached image first:

```bash
# 1. Stage matching headers on the host (this skill):
"$SKILL" sync

# 2. Drop the stale local build image so the header injection re-runs:
docker images --format '{{.Repository}}:{{.Tag}}' \
  | grep -- "-$(id -un)-$(uname -r | tr '[:upper:]' '[:lower:]')" \
  | xargs -r docker rmi

# 3. Rebuild, passing --copy-kernel-headers so the host headers are injected:
./build.sh --copy-kernel-headers ...   # your usual build args
```

Passing `--copy-kernel-headers` on a build that reuses a cached image has no
effect — step 2 is what makes it take.

### Keeping it up to date

After a WSL2 kernel update, `uname -r` changes and the old tree/symlink no longer
matches. Re-run `"$SKILL" sync`: it detects the new version, builds fresh headers
for it, installs and links them, clears the stale container cache, and removes
the previous version's tree. (WSL2 kernel updates happen via `wsl --update` on
the Windows host, not from inside the distro.)

## Cost (measured, 12-core WSL box)

- Shallow clone: ~1.5 min (~2GB checkout).
- Full `make -j`: under ~10 min (produces `Module.symvers`).
- On-disk after prune: ~7GB per kernel version (only the current one is kept).

## Important Notes

- **WSL2-only.** The script refuses to run if `uname -r` is not a WSL2 Microsoft
  kernel.
- Requires `sudo` for the `/usr/src` install, the `/lib/modules` symlink, and apt
  dependency installs.
- The built module's vermagic carries a trailing `+` (from `setlocalversion`
  reacting to Microsoft's tag naming). This is **cosmetic**: on WSL the module is
  only compiled to satisfy the build graph and is never loaded (WSL cannot run
  block-device tests or clusters).
- Override the scratch storage root with `WSL_KHDR_ROOT` (default
  `~/wsl2-kernel-headers`). The installed tree always lands under
  `/usr/src/linux-headers-$(uname -r)-wsl`.
