#!/usr/bin/env bash

set -euo pipefail

DOTFILES_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly DOTFILES_DIR

HOME_DIR="${HOME:-}"
readonly HOME_DIR

if [[ -z "$HOME_DIR" || ! -d "$HOME_DIR" ]]; then
    printf 'error: HOME must refer to an existing directory\n' >&2
    exit 1
fi

if ! git -C "$DOTFILES_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'error: %s is not a Git worktree\n' "$DOTFILES_DIR" >&2
    exit 1
fi

declare -A REPORTED_DIRECTORY_CONFLICTS=()
linked_count=0
skipped_count=0
conflict_count=0

ensure_directory() {
    local directory="$1"
    local relative_directory
    local current="$HOME_DIR"
    local component
    local -a components

    if [[ "$directory" == "$HOME_DIR" ]]; then
        return 0
    fi

    relative_directory="${directory#"$HOME_DIR"/}"
    if [[ "$relative_directory" == "$directory" ]]; then
        printf 'error: refusing to create a directory outside HOME: %s\n' "$directory" >&2
        exit 1
    fi

    IFS='/' read -r -a components <<< "$relative_directory"
    for component in "${components[@]}"; do
        [[ -n "$component" ]] || continue
        current="$current/$component"

        if [[ -d "$current" ]]; then
            continue
        fi

        if [[ -e "$current" || -L "$current" ]]; then
            if [[ -z "${REPORTED_DIRECTORY_CONFLICTS[$current]+reported}" ]]; then
                printf 'conflict: ~/%s is not a directory; preserved\n' \
                    "${current#"$HOME_DIR"/}" >&2
                REPORTED_DIRECTORY_CONFLICTS["$current"]=1
                conflict_count=$((conflict_count + 1))
            fi
            return 1
        fi

        if [[ "$current" == "$HOME_DIR/.gnupg" ]]; then
            if ! mkdir -m 700 -- "$current"; then
                printf 'error: could not create %s\n' "$current" >&2
                exit 1
            fi
        elif ! mkdir -- "$current"; then
            printf 'error: could not create %s\n' "$current" >&2
            exit 1
        fi
    done
}

link_managed_path() {
    local relative_path="$1"
    local source="$DOTFILES_DIR/$relative_path"
    local destination="$HOME_DIR/$relative_path"
    local parent_directory="${destination%/*}"
    local is_top_level=false

    if [[ "$relative_path" != */* ]]; then
        is_top_level=true
    fi

    if [[ ! -e "$source" && ! -L "$source" ]]; then
        printf 'error: tracked path is missing: %s\n' "$source" >&2
        exit 1
    fi

    if [[ -d "$source" && ! -L "$source" ]]; then
        printf 'error: tracked path is unexpectedly a directory: %s\n' "$source" >&2
        exit 1
    fi

    if ! ensure_directory "$parent_directory"; then
        printf 'skipped: ~/%s (parent path conflict)\n' "$relative_path"
        skipped_count=$((skipped_count + 1))
        return 0
    fi

    if [[ -e "$destination" || -L "$destination" ]]; then
        if [[ "$destination" -ef "$source" ]]; then
            if [[ -L "$destination" ]]; then
                printf 'skipped: ~/%s (already linked)\n' "$relative_path"
            else
                printf 'skipped: ~/%s (already in place)\n' "$relative_path"
            fi
            skipped_count=$((skipped_count + 1))
        elif [[ "$is_top_level" == true && ( ! -d "$destination" || -L "$destination" ) ]]; then
            if ! ln -sfn -- "$source" "$destination"; then
                printf 'error: could not replace ~/%s\n' "$relative_path" >&2
                exit 1
            fi
            printf 'linked: ~/%s (replaced existing entry)\n' "$relative_path"
            linked_count=$((linked_count + 1))
        else
            printf 'conflict: ~/%s exists; preserved\n' "$relative_path" >&2
            conflict_count=$((conflict_count + 1))
        fi
        return 0
    fi

    if ! ln -s -- "$source" "$destination"; then
        printf 'error: could not link ~/%s\n' "$relative_path" >&2
        exit 1
    fi

    printf 'linked: ~/%s\n' "$relative_path"
    linked_count=$((linked_count + 1))
}

managed_paths="$(git -C "$DOTFILES_DIR" ls-files -- '.*')"
if [[ -z "$managed_paths" ]]; then
    printf 'error: no tracked dotfiles found in %s\n' "$DOTFILES_DIR" >&2
    exit 1
fi

while IFS= read -r relative_path; do
    [[ -n "$relative_path" ]] || continue
    link_managed_path "$relative_path"
done <<< "$managed_paths"

printf 'done: %d linked, %d skipped, %d conflicts\n' \
    "$linked_count" "$skipped_count" "$conflict_count"
