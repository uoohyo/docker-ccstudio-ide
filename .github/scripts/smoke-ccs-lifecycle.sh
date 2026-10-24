#!/usr/bin/env bash
# Install once, then verify that the same stopped container reuses its installation.
set -euo pipefail

IMAGE=${1:?Usage: smoke-ccs-lifecycle.sh IMAGE VERSION MAJOR [COMPONENTS]}
VERSION=${2:?Version is required}
MAJOR=${3:?Major version is required}
COMPONENTS=${4:-PF_C28}
[[ "$MAJOR" =~ ^[0-9]+$ ]] || { echo 'Invalid major version' >&2; exit 1; }
WORK_DIR=$(mktemp -d)
CONTAINER_ID=''
cleanup() {
    status=$?
    if [ -n "$CONTAINER_ID" ]; then
        if [ "$status" -ne 0 ]; then
            docker logs "$CONTAINER_ID" >&2 || true
        fi
        docker rm -f "$CONTAINER_ID" >/dev/null || true
    fi
    rm -rf "$WORK_DIR"
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# This command runs after the image entrypoint on both starts. Capture CLI output
# before matching it so neither grep nor head can hide the CLI's exit status.
VALIDATE=$(cat <<'VALIDATION'
version=$1
major=$2
components=$3
test -s /opt/ti/.ccs-install-complete
expected=$(printf '%s\n%s' "$version" "$components")
test "$(cat /opt/ti/.ccs-install-complete)" = "$expected"
test ! -d /opt/ccs-installer
if [ "$major" -ge 20 ]; then
    mkdir -p /tmp/ccs_verify
    cd /opt/ti/ccs/eclipse
    output=$(./ccs-server-cli.sh -noSplash -workspace /tmp/ccs_verify -application com.ti.ccs.apps.inspect -ccs.help 2>&1)
    printf '%s\n' "$output"
    grep -q 'Usage:' <<< "$output"
elif [ "$major" -ge 9 ]; then
    output=$(/opt/ti/ccs/eclipse/eclipse -help 2>&1)
    printf '%s\n' "$output"
    grep -q 'Eclipse' <<< "$output"
else
    output=$("/opt/ti/ccsv${major}/eclipse/eclipse" -help 2>&1)
    printf '%s\n' "$output"
    grep -q 'Eclipse' <<< "$output"
fi
VALIDATION
)

# Do not use --rm: the second start must use this exact container filesystem.
NAME="ccs-lifecycle-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-${MAJOR}-$$"
CONTAINER_ID=$(docker create --name "$NAME" -e "COMPONENTS=$COMPONENTS" "$IMAGE" \
    bash -euo pipefail -c "$VALIDATE" -- "$VERSION" "$MAJOR" "$COMPONENTS")

run_and_wait() {
    local timeout_seconds=$1
    docker start "$CONTAINER_ID" >/dev/null
    local exit_code
    if ! exit_code=$(timeout "$timeout_seconds" docker wait "$CONTAINER_ID"); then
        echo "Container did not finish within ${timeout_seconds}s" >&2
        return 1
    fi
    if [ "$exit_code" != 0 ]; then
        echo "Container failed with exit code: $exit_code" >&2
        return 1
    fi
    test "$(docker inspect --format '{{.State.Status}}' "$CONTAINER_ID")" = exited
}

# Installation is performed only on this first invocation.
run_and_wait 660
docker logs "$CONTAINER_ID" > "$WORK_DIR/first.log" 2>&1
grep -Fxq "=== CCS ${VERSION} is ready. ===" "$WORK_DIR/first.log"
if grep -Fq '>>> Reusing verified CCS' "$WORK_DIR/first.log"; then
    echo 'First start unexpectedly reused an installation' >&2
    exit 1
fi
docker cp "$CONTAINER_ID:/opt/ti/.ccs-install-complete" "$WORK_DIR/first.marker"
test -s "$WORK_DIR/first.marker"

# Restart the same stopped container. The payload verifies the CLI and marker
# again; installation files must remain deleted and the marker must not change.
run_and_wait 90
docker logs "$CONTAINER_ID" > "$WORK_DIR/restarted.log" 2>&1
test "$(grep -Fxc ">>> Reusing verified CCS ${VERSION} installation." "$WORK_DIR/restarted.log")" = 1
test "$(grep -Fxc "=== CCS ${VERSION} is ready. ===" "$WORK_DIR/restarted.log")" = 1
docker cp "$CONTAINER_ID:/opt/ti/.ccs-install-complete" "$WORK_DIR/restarted.marker"
cmp "$WORK_DIR/first.marker" "$WORK_DIR/restarted.marker"
printf 'PASS: CCS %s installed once and the same container restarted successfully (%s).\n' "$VERSION" "$CONTAINER_ID"
