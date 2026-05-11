#!/bin/bash
set -e

# Get all buildable versions
echo "=== Fetching CCS versions..."
VERSIONS_JSON=$(bash .github/scripts/parse-versions.sh)

# Filter public_download=true versions
PUBLIC_VERSIONS=$(echo "$VERSIONS_JSON" | jq -r '.[] | select(.public_download == true) | @json')

# Count total versions
TOTAL=$(echo "$PUBLIC_VERSIONS" | wc -l)
echo "=== Found $TOTAL buildable versions"

# Build configuration
CONCURRENT_BUILDS=4
CONCURRENT_RUNS=8
BUILD_COUNT=0
RUN_COUNT=0

# Function to determine base image
get_base_image() {
    local major=$1
    if [ "$major" -le 8 ]; then
        echo "ubuntu:18.04"
    elif [ "$major" -le 11 ]; then
        echo "ubuntu:20.04"
    else
        echo "ubuntu:22.04"
    fi
}

# Arrays to track builds and containers
declare -a BUILD_PIDS=()
declare -a CONTAINER_NAMES=()

# Function to build a single version
build_version() {
    local version_json=$1
    local version=$(echo "$version_json" | jq -r '.version')
    local major=$(echo "$version_json" | jq -r '.major')
    local minor=$(echo "$version_json" | jq -r '.minor')
    local patch=$(echo "$version_json" | jq -r '.patch')
    local build=$(echo "$version_json" | jq -r '.build')
    local base_image=$(get_base_image "$major")

    echo ">>> Building CCS $version (Base: $base_image)..."

    docker buildx build \
        --build-arg BASE_IMAGE="$base_image" \
        --build-arg CCS_VERSION="$version" \
        --build-arg MAJOR_VER="$major" \
        --build-arg MINOR_VER="$minor" \
        --build-arg PATCH_VER="$patch" \
        --build-arg BUILD_VER="$build" \
        --tag "ccstudio-ide:$version" \
        --load \
        . 2>&1 | sed "s/^/[BUILD $version] /"

    echo "✓ Build complete: $version"
}

# Function to run a container
run_container() {
    local version=$1
    local major=$(echo "$version" | cut -d. -f1)
    local container_name="ccs-v${major}-${version}"

    echo ">>> Starting container: $container_name"

    docker run -d \
        --name "$container_name" \
        --memory=2g \
        -e COMPONENTS=PF_C28 \
        "ccstudio-ide:$version" \
        sleep infinity

    echo "✓ Container started: $container_name"
    CONTAINER_NAMES+=("$container_name")
}

# Function to wait for builds
wait_for_builds() {
    for pid in "${BUILD_PIDS[@]}"; do
        wait "$pid" 2>/dev/null || true
    done
    BUILD_PIDS=()
}

# Main build loop
echo ""
echo "=== Starting parallel builds (max $CONCURRENT_BUILDS concurrent)..."
echo ""

while IFS= read -r version_json; do
    # Wait if we've reached max concurrent builds
    if [ ${#BUILD_PIDS[@]} -ge $CONCURRENT_BUILDS ]; then
        echo "--- Waiting for builds to complete..."
        wait_for_builds
    fi

    # Start build in background
    build_version "$version_json" &
    BUILD_PIDS+=($!)
    BUILD_COUNT=$((BUILD_COUNT + 1))

    echo "Progress: $BUILD_COUNT/$TOTAL builds started"

done <<< "$PUBLIC_VERSIONS"

# Wait for remaining builds
echo "--- Waiting for final builds..."
wait_for_builds

echo ""
echo "=== All builds complete! ($TOTAL versions)"
echo ""

# Start all containers in parallel
echo "=== Starting all containers..."
echo ""

while IFS= read -r version_json; do
    version=$(echo "$version_json" | jq -r '.version')

    # Wait if we've reached max concurrent runs
    active_containers=$(docker ps -q | wc -l)
    while [ "$active_containers" -ge $CONCURRENT_RUNS ]; do
        sleep 2
        active_containers=$(docker ps -q | wc -l)
    done

    run_container "$version" &
    RUN_COUNT=$((RUN_COUNT + 1))
    echo "Progress: $RUN_COUNT/$TOTAL containers started"

done <<< "$PUBLIC_VERSIONS"

# Wait for all container starts to complete
wait

echo ""
echo "=== All containers started! ==="
echo ""
echo "Container names:"
for name in "${CONTAINER_NAMES[@]}"; do
    echo "  - $name"
done

echo ""
echo "=== Installation in progress ==="
echo "Use 'docker ps' to see running containers"
echo "Use 'docker logs <container_name>' to check installation progress"
echo ""
echo "Verification commands:"
echo "  # Check v20+ installation:"
echo "  docker exec <container> test -x /opt/ti/ccs/eclipse/ccs-server-cli.sh && echo 'Ready'"
echo ""
echo "  # Check v9-v19 installation:"
echo "  docker exec <container> test -x /opt/ti/ccs/eclipse/eclipse && echo 'Ready'"
echo ""
echo "  # Check v7-v8 installation:"
echo "  docker exec <container> test -x /opt/ti/ccsv7/eclipse/eclipse && echo 'Ready'"
echo ""
