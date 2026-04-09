#!/bin/bash

RELEASE_PACKAGE_PIPELINE_ID=166
RELEASE_PACKAGE_ARTIFACT_NAME=packages_amd64_retail_native
RELEASE_PACKAGE_BUILD_ID=last_succeeded
RELEASE_PACKAGES_FOLDER=/home/$USER/latest-release-packages

if [ -d "${RELEASE_PACKAGES_FOLDER}" ]; then
    echo "Removing ${RELEASE_PACKAGES_FOLDER} folder"
    rm -rf "${RELEASE_PACKAGES_FOLDER}"
    mkdir -p "${RELEASE_PACKAGES_FOLDER}"
fi

# az login --use-device-code

./meru-core/ext/test-infra/src/test/systemtest/testfx/download-pipeline-artifact.sh \
    --pipeline-id $RELEASE_PACKAGE_PIPELINE_ID \
    --artifact-name $RELEASE_PACKAGE_ARTIFACT_NAME \
    --id $RELEASE_PACKAGE_BUILD_ID \
    --destination $RELEASE_PACKAGES_FOLDER
