#!/usr/bin/env bash
#
# wsl_kernel_headers.sh - Build & install kernel headers/build-tree for the
# running WSL2 custom kernel so out-of-tree kernel modules (e.g. meru-bd's
# chibd) can compile.
#
# WSL2 ships a custom Microsoft kernel and provides NO apt package with a
# matching /lib/modules/$(uname -r)/build tree. Out-of-tree modules whose
# Makefile does `make -C /lib/modules/$(uname -r)/build ... modules` therefore
# fail with "No such file or directory". This script builds the matching kernel
# source from microsoft/WSL2-Linux-Kernel (at the exact tag for the running
# kernel), leaves a full Module.symvers so modpost links cleanly, and installs
# it. It keeps only the current kernel's tree and removes older ones.
#
# Install layout (mirrors Debian/Ubuntu linux-headers packages):
#   /usr/src/linux-headers-<uname -r>-wsl   real, pruned build tree
#   /lib/modules/<uname -r>/build           symlink -> the /usr/src tree
#
# This layout is deliberate so the meru containerized build picks the headers
# up automatically. container-run.sh tars /lib/modules/<uname -r> plus
# /usr/src/linux-headers-<uname -r>-* into a cached kernel-headers tarball that
# the image extracts; placing REAL files under /usr/src/linux-headers-<uname
# -r>-wsl (matched by that glob) means the container receives the exact headers
# — tar would only capture a bare symlink if the tree lived under $HOME. After
# (re)building, this script also deletes the stale ~/kernel-headers-<ver>.tar.gz
# cache so container-run.sh regenerates it with the real build tree inside.
#
# Subcommands:
#   status   Show current kernel, expected tag, and whether headers are ready.
#   sync     (default) Ensure headers for the running kernel exist & are linked;
#            build them if missing; then clean up trees for other versions.
#   clean    Remove header trees and build symlinks for NON-running kernels.
#
# Notes:
#  * The produced module's vermagic carries a trailing '+' (setlocalversion
#    reacts to Microsoft's tag naming). This is cosmetic: on WSL the module is
#    only compiled to satisfy the build graph, never insmod'd.
#  * Requires sudo for the /lib/modules symlink and for apt (dependency install).
#
set -euo pipefail

REPO_URL="https://github.com/microsoft/WSL2-Linux-Kernel.git"
ROOT="${WSL_KHDR_ROOT:-$HOME/wsl2-kernel-headers}"
UNR="$(uname -r)"

log()  { printf '\033[0;34m[wsl-khdr]\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m[wsl-khdr] WARNING:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[0;31m[wsl-khdr] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# --- derive tag from running kernel release ---------------------------------
# uname -r looks like: 6.18.33.1-microsoft-standard-WSL2
# upstream tag looks like: linux-msft-wsl-6.18.33.1
kver_from_unr() { printf '%s' "${UNR%%-microsoft*}"; }
tag_from_unr()  { printf 'linux-msft-wsl-%s' "$(kver_from_unr)"; }

require_wsl() {
  case "$UNR" in
    *-microsoft-standard-WSL2|*microsoft*WSL2*) : ;;
    *) die "Running kernel '$UNR' is not a WSL2 Microsoft kernel; this skill is WSL-only." ;;
  esac
}

dest_dir()   { printf '%s/%s' "$ROOT" "$UNR"; }   # transient build scratch (home)
src_dest()   { printf '/usr/src/linux-headers-%s-wsl' "$UNR"; }  # installed tree
build_link() { printf '/lib/modules/%s/build' "$UNR"; }
host_cache() { printf '%s/kernel-headers-%s.tar.gz' "$HOME" "$UNR"; } # container-run.sh cache

headers_ready() {
  local s; s="$(src_dest)"
  [ -f "$s/Module.symvers" ] && [ -e "$s/scripts/mod/modpost" ] \
    && [ "$(readlink -f "$(build_link)" 2>/dev/null)" = "$s" ]
}

# --- dependency check --------------------------------------------------------
ensure_deps() {
  local missing_cmds=() pkgs=() p
  for c in gcc make bc bison flex cpio; do
    command -v "$c" >/dev/null 2>&1 || missing_cmds+=("$c")
  done
  for p in libssl-dev libelf-dev; do
    dpkg -s "$p" >/dev/null 2>&1 || pkgs+=("$p")
  done
  # map missing commands to packages
  ((${#missing_cmds[@]})) && pkgs+=(build-essential bc bison flex cpio)
  if ((${#pkgs[@]})); then
    log "Installing build dependencies: ${pkgs[*]}"
    sudo apt-get update -qq
    sudo apt-get install -y "${pkgs[@]}"
  fi
}

# --- config source -----------------------------------------------------------
apply_config() {
  local d="$1"
  if [ -r /proc/config.gz ]; then
    log "Applying running-kernel config from /proc/config.gz"
    zcat /proc/config.gz > "$d/.config"
  elif [ -r "$d/Microsoft/config-wsl" ]; then
    warn "/proc/config.gz not available; falling back to Microsoft/config-wsl"
    cp "$d/Microsoft/config-wsl" "$d/.config"
  else
    die "No kernel config available (no /proc/config.gz and no Microsoft/config-wsl)."
  fi
}

# --- prune to keep only what out-of-tree module builds need ------------------
prune_tree() {
  local d="$1"
  log "Pruning kernel object files (keeps headers, scripts/, Module.symvers)"
  ( cd "$d"
    find . -not -path './scripts/*' \
        \( -name '*.o' -o -name '*.cmd' -o -name '*.o.d' \) -type f -delete
    rm -f vmlinux vmlinux.o vmlinux.a vmlinux.symvers .vmlinux.export.c 2>/dev/null || true
    find . -name 'built-in.a' -type f -delete 2>/dev/null || true
  )
}

# --- build the headers/build tree for the running kernel --------------------
build_headers() {
  local tag dest src jobs
  tag="$(tag_from_unr)"; dest="$(dest_dir)"; src="$(src_dest)"; jobs="$(nproc)"

  log "Running kernel : $UNR"
  log "Upstream tag   : $tag"
  log "Build scratch  : $dest"
  log "Install dest   : $src"

  log "Verifying tag exists upstream..."
  git ls-remote --exit-code --tags "$REPO_URL" "refs/tags/$tag" >/dev/null 2>&1 \
    || die "Tag '$tag' not found in $REPO_URL. Check that WSL2-Linux-Kernel has published it."

  ensure_deps

  mkdir -p "$ROOT"
  rm -rf "$dest"
  log "Shallow-cloning $tag (~2GB working tree)..."
  git clone --depth 1 --branch "$tag" "$REPO_URL" "$dest"

  apply_config "$dest"

  log "Configuring (olddefconfig)..."
  make -C "$dest" -j"$jobs" olddefconfig >/dev/null

  log "Building kernel with -j$jobs to produce Module.symvers (several minutes)..."
  make -C "$dest" -j"$jobs"

  [ -f "$dest/Module.symvers" ] || die "Build finished but Module.symvers is missing."

  prune_tree "$dest"

  # Install the pruned tree under /usr/src so the containerized build's header
  # tarball (which archives /usr/src/linux-headers-<uname -r>-*) captures REAL
  # files, not just a $HOME symlink. Then point /lib/modules/<uname -r>/build
  # at it for host-side out-of-tree builds.
  log "Installing tree to $src"
  sudo rm -rf "$src"
  sudo mkdir -p /usr/src
  sudo mv "$dest" "$src"

  log "Linking $(build_link) -> $src"
  sudo mkdir -p "/lib/modules/$UNR"
  sudo ln -sfn "$src" "$(build_link)"

  # Invalidate the stale host header tarball so container-run.sh regenerates it
  # with the real build tree inside on the next build.
  if [ -f "$(host_cache)" ]; then
    log "Removing stale container header cache: $(host_cache)"
    rm -f "$(host_cache)"
  fi

  log "Headers ready for $UNR ($(du -sh "$src" | cut -f1) on disk)."
}

# --- remove trees / links / caches for other kernel versions ----------------
clean_others() {
  local d ver link t

  # Stale build scratch dirs left in $ROOT (any version).
  if [ -d "$ROOT" ]; then
    for d in "$ROOT"/*/; do
      [ -d "$d" ] || continue
      log "Removing stale build scratch: $d"
      rm -rf "$d"
    done
  fi

  # Installed /usr/src trees for other WSL kernels + their build symlinks.
  for d in /usr/src/linux-headers-*-wsl; do
    [ -d "$d" ] || continue
    [ "$d" = "$(src_dest)" ] && continue
    ver="$(basename "$d")"; ver="${ver#linux-headers-}"; ver="${ver%-wsl}"
    log "Removing stale header tree: $d"
    sudo rm -rf "$d"
    link="/lib/modules/$ver/build"
    if [ -L "$link" ]; then
      log "Removing stale build symlink: $link"
      sudo rm -f "$link"
    fi
  done

  # Stale container header caches for other kernel versions.
  for t in "$HOME"/kernel-headers-*.tar.gz; do
    [ -e "$t" ] || continue
    [ "$t" = "$(host_cache)" ] && continue
    log "Removing stale container header cache: $t"
    rm -f "$t"
  done
}

cmd_status() {
  require_wsl
  echo "Running kernel : $UNR"
  echo "Expected tag   : $(tag_from_unr)"
  echo "Install dest   : $(src_dest)"
  echo "Build symlink  : $(build_link) -> $(readlink -f "$(build_link)" 2>/dev/null || echo '(missing)')"
  echo "Container cache: $(host_cache) $( [ -f "$(host_cache)" ] && echo '(present)' || echo '(absent — will be regenerated on next build)')"
  if headers_ready; then
    echo "Status         : READY"
  else
    echo "Status         : NOT READY (run: $0 sync)"
  fi
}

cmd_sync() {
  require_wsl
  if headers_ready; then
    log "Headers already present and linked for $UNR; nothing to build."
  else
    build_headers
  fi
  clean_others
  log "Done."
}

cmd_clean() {
  require_wsl
  clean_others
  log "Cleanup done."
}

main() {
  case "${1:-sync}" in
    status) cmd_status ;;
    sync)   cmd_sync ;;
    clean)  cmd_clean ;;
    *) die "Unknown subcommand '$1' (use: status | sync | clean)" ;;
  esac
}

main "$@"
