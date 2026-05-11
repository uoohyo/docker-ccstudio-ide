#!/bin/bash
set -e

# Build and run all CCS versions sequentially (reliable, simpler than parallel)

echo "=== Fetching CCS versions..."
VERSIONS_JSON=$(cat versions-temp.json)

# Parse and build each version
TOTAL=$(echo "$VERSIONS_JSON" | grep -o '"public_download":true' | wc -l)
CURRENT=0

get_base_image() {
    local major=$1
    if [ "$major" -le 8 ]; then
        echo "ubuntu:16.04"
    elif [ "$major" -le 11 ]; then
        echo "ubuntu:20.04"
    elif [ "$major" -le 19 ]; then
        echo "ubuntu:22.04"
    else
        echo "ubuntu:24.04"
    fi
}

echo "=== Found $TOTAL buildable versions"
echo "=== Starting builds..."
echo ""

# Arrays for container names
CONTAINERS=()

# Process each version
echo "$VERSIONS_JSON" | grep -o '{[^}]*}' | while read -r version_obj; do
    # Parse JSON fields manually (no jq needed)
    VERSION=$(echo "$version_obj" | grep -o '"version":"[^"]*"' | cut -d'"' -f4)
    PUBLIC=$(echo "$version_obj" | grep -o '"public_download":[^,}]*' | cut -d':' -f2)

    # Skip if not public
    if [ "$PUBLIC" != "true" ]; then
        continue
    fi

    MAJOR=$(echo "$version_obj" | grep -o '"major":"[^"]*"' | cut -d'"' -f4)
    MINOR=$(echo "$version_obj" | grep -o '"minor":"[^"]*"' | cut -d'"' -f4)
    PATCH=$(echo "$version_obj" | grep -o '"patch":"[^"]*"' | cut -d'"' -f4)
    BUILD=$(echo "$version_obj" | grep -o '"build":"[^"]*"' | cut -d'"' -f4)

    BASE_IMAGE=$(get_base_image "$MAJOR")
    CURRENT=$((CURRENT + 1))

    echo "=========================================="
    echo "[$CURRENT/$TOTAL] Building CCS $VERSION"
    echo "Base Image: $BASE_IMAGE"
    echo "=========================================="

    # Build image
    docker buildx build \
        --build-arg BASE_IMAGE="$BASE_IMAGE" \
        --build-arg CCS_VERSION="$VERSION" \
        --build-arg MAJOR_VER="$MAJOR" \
        --build-arg MINOR_VER="$MINOR" \
        --build-arg PATCH_VER="$PATCH" \
        --build-arg BUILD_VER="$BUILD" \
        --tag "ccstudio-ide:$VERSION" \
        --load \
        . || {
        echo "✗ Build failed for $VERSION"
        continue
    }

    echo "✓ Build complete: $VERSION"
    echo ""

    # Start container
    CONTAINER_NAME="ccs-v${MAJOR}-${VERSION}"
    echo "Starting container: $CONTAINER_NAME"

    docker run -d \
        --name "$CONTAINER_NAME" \
        --memory=2g \
        -e COMPONENTS=PF_C28 \
        "ccstudio-ide:$VERSION" \
        sleep infinity && {
        echo "✓ Container started: $CONTAINER_NAME"
        CONTAINERS+=("$CONTAINER_NAME")
    } || {
        echo "✗ Container start failed: $CONTAINER_NAME"
    }

    echo ""
done

echo ""
echo "=========================================="
echo "=== All builds and containers complete ==="
echo "=========================================="
echo ""
echo "Verification commands:"
echo ""
echo "# Check v20+ installation:"
echo 'docker exec ccs-v20-<version> test -x /opt/ti/ccs/eclipse/ccs-server-cli.sh && echo "✓ Ready"'
echo ""
echo "# Check v9-v19 installation:"
echo 'docker exec ccs-v12-<version> test -x /opt/ti/ccs/eclipse/eclipse && echo "✓ Ready"'
echo ""
echo "# Check v7-v8 installation:"
echo 'docker exec ccs-v7-<version> test -x /opt/ti/ccsv7/eclipse/eclipse && echo "✓ Ready"'
echo ""
echo "# View container logs:"
echo 'docker logs ccs-v<major>-<version>'
echo ""
echo "# List all CCS containers:"
echo 'docker ps -a | grep ccs-v'
echo ""
