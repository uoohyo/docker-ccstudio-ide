#!/usr/bin/env bash
# Publish the locally tested image without rebuilding, then verify its identity.
set -euo pipefail
image=${1:?Usage: publish-tested-image.sh IMAGE RECEIPT}
receipt=${2:?Receipt path required}
repository=${image%:*}
tested_id=$(docker image inspect --format '{{.Id}}' "$image")
[[ "$tested_id" == sha256:* ]] || { echo "Invalid tested image ID" >&2; exit 1; }
previous_digest=""
if [ "${REQUIRE_EXISTING_IMAGE:-false}" = true ]; then
    # The workflow must upload this ledger successfully before entering this step.
    ledger="rollback/$(basename "$receipt")"
    previous_ref=$(jq -er --arg image "$image" --arg id "$tested_id" \
        'select(.image == $image and .proposed_image_id == $id) | .previous_repository_digest' "$ledger")
    previous_digest=${previous_ref##*@}
    current_digest=$(docker buildx imagetools inspect "$image" --format '{{json .Manifest}}' | jq -er '.digest')
    [ "$current_digest" = "$previous_digest" ] || { echo "Release changed after rollback snapshot; refusing overwrite" >&2; exit 1; }
fi
# The push response identifies the manifest actually accepted by the registry.
# A tag lookup immediately after push may still return the previous manifest.
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
push_log="$work_dir/push.log"
published=false
for attempt in 1 2 3; do
    set +e
    docker push "$image" 2>&1 | tee "$push_log"
    statuses=("${PIPESTATUS[@]}")
    set -e
    if [ "${statuses[0]}" -eq 0 ]; then
        # A successful push with an unreadable log must never be pushed again.
        [ "${statuses[1]}" -eq 0 ] || { echo "Push succeeded but its output could not be recorded" >&2; exit 1; }
        published=true
        break
    fi
    [ "${statuses[1]}" -eq 0 ] || { echo "Unable to record failed push output" >&2; exit 1; }
    if [ "$attempt" -lt 3 ]; then sleep 60; fi
done
[ "$published" = true ] || { echo "Image publication failed" >&2; exit 1; }
published_digest=$(jq -R -s -e -r --arg tag "${image##*:}" '
    split("\n") | map(sub("\r$"; "")) |
    map(select(startswith($tag + ": digest: "))) |
    if length != 1 then error("Expected exactly one successful push digest summary")
    else .[0] | capture("^[^ ]+: digest: (?<digest>sha256:[0-9a-f]{64}) size: [0-9]+$").digest end
' "$push_log")
# Verify the authoritative digest, not an eventually consistent tag lookup.
repository_digest="$repository@$published_digest"
docker pull "$repository_digest"
pulled_id=$(docker image inspect --format '{{.Id}}' "$repository_digest")
[ "$tested_id" = "$pulled_id" ] || { echo "Published image differs from tested image" >&2; exit 1; }

# The mutable tag must also converge before recording success. Only the known
# rollback digest is an acceptable stale value; an unrelated digest can indicate
# another publisher and must fail closed. Verification failures never re-push.
converged=false
for ((attempt=1; attempt<=25; attempt++)); do
    current_digest=$(docker buildx imagetools inspect "$image" --format '{{json .Manifest}}' | \
        jq -er '.digest | select(test("^sha256:[0-9a-f]{64}$"))')
    if [ "$current_digest" = "$published_digest" ]; then
        converged=true
        break
    fi
    if [ -z "$previous_digest" ] || [ "$current_digest" != "$previous_digest" ]; then
        echo "Tag points to an unrelated digest after push; refusing a success receipt" >&2
        exit 1
    fi
    echo "Tag still shows its rollback digest (verification ${attempt}/25)" >&2
    if [ "$attempt" -lt 25 ]; then sleep 5; fi
done
[ "$converged" = true ] || { echo "Tag did not converge to the pushed digest; no receipt recorded" >&2; exit 1; }
mkdir -p "$(dirname "$receipt")"
jq -n --arg image "$image" --arg digest "$repository_digest" --arg id "$tested_id" \
    --arg revision "${GITHUB_SHA:-unknown}" --arg previous "$previous_digest" \
    '{image: $image, repository_digest: $digest, image_id: $id, source_revision: $revision, previous_digest: $previous}' > "$receipt"
cat "$receipt" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
