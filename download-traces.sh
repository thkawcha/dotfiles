#!/bin/bash
set -euo pipefail

# Resolve paths relative to the script's location, not the caller's CWD
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

DOWNLOAD_PATH="${HOME}/tmp"
REPO_DIR="${SCRIPT_DIR}/meru-test-infra"
ARTIFACTS="traceviewer,traces,operational-traces,managed-application-traces,unmanaged-application-traces"

# Detect WSL and resolve the Windows user's Downloads folder dynamically
OUTPUT_PATH=""
if grep -qi microsoft /proc/version 2>/dev/null; then
    WIN_USERPROFILE="$(cmd.exe /C "echo %USERPROFILE%" 2>/dev/null | tr -d '\r')" || true
    if [[ -n "$WIN_USERPROFILE" ]]; then
        WIN_DOWNLOADS="$(wslpath -u "${WIN_USERPROFILE}")/Downloads"
        if [[ -d "$WIN_DOWNLOADS" ]]; then
            OUTPUT_PATH="$WIN_DOWNLOADS"
        fi
    fi
fi

BUILD_NUMBER="${1:?Usage: $0 <build-number> [additional-naming] [artifact-filter]}"
DOWNLOAD_DIR="${DOWNLOAD_PATH}/${BUILD_NUMBER}"
OUTPUT_DIR="${OUTPUT_PATH:+${OUTPUT_PATH}/${BUILD_NUMBER}}"

ADDITIONAL_NAMING=${2:-}
ARTIFACT_FILTER=${3:-}

if [ -n "$ADDITIONAL_NAMING" ]; then
    DOWNLOAD_DIR="${DOWNLOAD_PATH}/${BUILD_NUMBER}-${ADDITIONAL_NAMING}"
    OUTPUT_DIR="${OUTPUT_PATH:+${OUTPUT_PATH}/${BUILD_NUMBER}-${ADDITIONAL_NAMING}}"
fi

if [ -n "$ARTIFACT_FILTER" ]; then
    ARTIFACTS="$ARTIFACT_FILTER"
fi

echo "Downloading build '${BUILD_NUMBER}' traces to '${DOWNLOAD_DIR}'"
"${REPO_DIR}/src/test/systemtest/testfx/download-and-extract-diagnostics.sh" \
  --repo "${REPO_DIR}" \
  -p "$BUILD_NUMBER" \
  -d "${DOWNLOAD_DIR}" \
  -a "${ARTIFACTS}"
echo "Downloaded build '${BUILD_NUMBER}' traces to '${DOWNLOAD_DIR}'"

if [ ! -d "${DOWNLOAD_DIR}/traceviewer" ]; then
    TRACE_FOLDERS=(
        "traces"
        "operational-traces"
        "managed-application-traces"
        "unmanaged-application-traces"
    )

    TRACE_CONVERSION_INPUT_FOLDER_LIST=""
    for folder in "${TRACE_FOLDERS[@]}"; do
        full_path="${DOWNLOAD_DIR}/${folder}"
        if [ -d "$full_path" ]; then
            TRACE_CONVERSION_INPUT_FOLDER_LIST+="${TRACE_CONVERSION_INPUT_FOLDER_LIST:+,}${full_path}"
        fi
    done

    if [ -z "${TRACE_CONVERSION_INPUT_FOLDER_LIST}" ]; then
        echo "No traces to convert"
        exit 0
    fi

    echo "'${DOWNLOAD_DIR}/traceviewer' folder not found. Converting traces from: ${TRACE_CONVERSION_INPUT_FOLDER_LIST}"
    meruinsight traces convert-to-text \
        --input-folder-list "${TRACE_CONVERSION_INPUT_FOLDER_LIST}" \
        --output-folder "${DOWNLOAD_DIR}" \
        --skip-delete-source-files \
        --num-workers 160
    echo "Traces converted in ${DOWNLOAD_DIR}/traceviewer"
fi

# Copy to Windows Downloads folder (WSL only)
if [[ -n "$OUTPUT_DIR" && -d "${DOWNLOAD_DIR}/traceviewer" && ! -d "${OUTPUT_DIR}/traceviewer" ]]; then
    mkdir -p "${OUTPUT_DIR}"
    echo "Copying traceviewer files to Windows filesystem at '${OUTPUT_DIR}/traceviewer'"
    cp -r "${DOWNLOAD_DIR}/traceviewer" "${OUTPUT_DIR}"
fi
