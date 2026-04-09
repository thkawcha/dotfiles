#!/bin/bash
set -euo pipefail

DOWNLOAD_PATH="/home/thkawcha/tmp"
OUTPUT_PATH="/mnt/c/Users/thkawcha/Downloads"

BUILD_NUMBER=$1
DOWNLOAD_DIR="${DOWNLOAD_PATH}/${BUILD_NUMBER}"
OUTPUT_DIR="${OUTPUT_PATH}/${BUILD_NUMBER}"
ARTIFACTS="traceviewer,traces,operational-traces,managed-application-traces,unmanaged-application-traces"

ADDITIONAL_NAMING=${2:-}
ARTIFACT_FILTER=${3:-}

if [ -n "$ADDITIONAL_NAMING" ]; then
    DOWNLOAD_DIR="${DOWNLOAD_PATH}/${BUILD_NUMBER}-${ADDITIONAL_NAMING}"
    OUTPUT_DIR="${OUTPUT_PATH}/${BUILD_NUMBER}-${ADDITIONAL_NAMING}"
fi

if [ -n "$ARTIFACT_FILTER" ]; then
    ARTIFACTS="$ARTIFACT_FILTER"
fi

echo "Downloading build '${BUILD_NUMBER}' traces to '${DOWNLOAD_DIR}'"
./meru-test-infra/src/test/systemtest/testfx/download-and-extract-diagnostics.sh \
  --repo ~/meru-test-infra \
  -p "$BUILD_NUMBER" \
  -d "${DOWNLOAD_DIR}" \
  -a "${ARTIFACTS}"
echo "Downloaded build '${BUILD_NUMBER}' traces to '${DOWNLOAD_DIR}'"

if [ ! -d "${DOWNLOAD_DIR}/traceviewer" ]; then
    # Candidate subfolder names to look for
    TRACE_FOLDERS=(
        "traces"
        "operational-traces"
        "managed-application-traces"
        "unmanaged-application-traces"
    )

    existing_paths=()
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
        --skip-delete-source-files
        --num-workers 160
    echo "Traces converted in ${DOWNLOAD_DIR}/traceviewer"
fi

if [ -d "${DOWNLOAD_DIR}/traceviewer" ]  && [ ! -d "${OUTPUT_DIR}/traceviewer" ]; then
    mkdir -p "${OUTPUT_DIR}"
    echo "Copying traceviewer files to windows filesystem at '${OUTPUT_DIR}/traceviewer'"
    cp -r "${DOWNLOAD_DIR}/traceviewer" "${OUTPUT_DIR}"
fi
