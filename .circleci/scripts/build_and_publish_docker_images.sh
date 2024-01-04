#!/bin/bash
set -e

echo $SERVICE

# To pass variables React build time in build-ui.yaml
if [ "$SERVICE" == "ui" ]; then
    if [ -n "$CIRCLE_BRANCH" ]; then
        cp ui/.env.build.$CIRCLE_BRANCH ui/.env
    elif [ -n "$CIRCLE_TAG" ]; then
        cp ui/.env.build.master ui/.env
    fi
fi

# Extract the arch from the job name
if [[ "$CIRCLE_JOB" == *"arm64"* ]]; then
    echo "Job is for arm64."
    ARCH="arm64"
elif [[ "$CIRCLE_JOB" == *"amd64"* ]]; then
    echo "Job is for amd64."
    ARCH="amd64"
else
    echo "Error: CIRCLE_JOB does not contain 'arm64' or 'amd64'."
    exit 1  # Exit with a non-zero status to indicate an error.
fi

NAMESPACE="ghcr.io/ethereum/sourcify"
IMAGE_NAME="$NAMESPACE/$SERVICE"
# Login to Github Container Registry
echo $GITHUB_CR_PAT | docker login ghcr.io --username kuzdogan --password-stdin

# Triggered by a branch
# e.g. sourcify/server:master-arm64
if [ -n "$CIRCLE_BRANCH" ]; then
    BRANCH_TAG="$IMAGE_NAME:$CIRCLE_BRANCH-$ARCH"
    TAG_COMMAND="-t $BRANCH_TAG"
fi

# Triggered by a tag (release)
# e.g. sourcify/server:latest-arm64  &  sourcify/server:0.1.0-arm64
if [ -n "$CIRCLE_TAG" ]; then
    # Assuming CIRCLE_TAG is something like "sourcify-monitor@1.1.3"
    # Extract the version number after the last '@'
    VERSION=${CIRCLE_TAG##*@}
    VERSION_TAG="$IMAGE_NAME:$VERSION-$ARCH"
    LATEST_TAG="$IMAGE_NAME:latest-$ARCH"
    
    TAG_COMMAND="-t $LATEST_TAG -t $VERSION_TAG"
fi

docker build \
    -f $DOCKERFILE \
    $TAG_COMMAND \
    $DOCKER_BUILD_CONTEXT \

docker push --all-tags $IMAGE_NAME


mkdir -p workspace

# In branch builds we only need to write to server:master-arm64.txt
if [ -n "$CIRCLE_BRANCH" ]; then
    MANIFEST=$(docker manifest inspect $BRANCH_TAG)
    SHA=$(echo $MANIFEST | jq -r '.config.digest')
    echo "Branch tag $BRANCH_TAG SHA: $SHA"
    echo "Writing sha $SHA to workspace/$SERVICE_$ARCH_image_sha.txt"
    echo -n $SHA > workspace/"$SERVICE"_"$ARCH"_image_sha.txt
fi

# No need to extract the image tag if the build is triggered by a tag because the deployment will be done by the branch trigger.
if [ -n "$CIRCLE_TAG" ]; then
    echo "CIRCLE_TAG=$CIRCLE_TAG No need to write to workspace/$SERVICE_image_sha.txt for tag builds."
fi