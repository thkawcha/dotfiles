#!/bin/bash

set -euo pipefail

RELEASE_PACKAGE_PIPELINE_ID=166
RELEASE_PACKAGE_ARTIFACT_NAME=packages_amd64_retail_native
RELEASE_PACKAGE_BUILD_ID=last_succeeded
RELEASE_PACKAGES_FOLDER="$HOME/latest-release-packages"
REPO_ROOT="$HOME/meru-core"

echo "Removing ${RELEASE_PACKAGES_FOLDER} folder"
sudo rm -rf "${RELEASE_PACKAGES_FOLDER}"
mkdir -p "${RELEASE_PACKAGES_FOLDER}"
sudo rm -f /tmp/poirot_context /tmp/poirot_context.tmp

# az login --use-device-code

"${REPO_ROOT}/ext/test-infra/src/test/systemtest/testfx/download-pipeline-artifact.sh" \
    --pipeline-id $RELEASE_PACKAGE_PIPELINE_ID \
    --artifact-name $RELEASE_PACKAGE_ARTIFACT_NAME \
    --id $RELEASE_PACKAGE_BUILD_ID \
    --destination "$RELEASE_PACKAGES_FOLDER"
