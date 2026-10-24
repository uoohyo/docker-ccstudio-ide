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
    # Do not replace an existing release until its exact rollback target is recorded.
    previous_digest=$(docker buildx imagetools inspect "$image" --format '{{json .Manifest}}' | \
        jq -er '.digest | select(test("^sha256:[0-9a-f]{64}$"))')
    mkdir -p rollback
    jq -n --arg image "$image" --arg previous "$repository@$previous_digest" \
        --arg proposed "$tested_id" --arg revision "${GITHUB_SHA:-unknown}" \
        '{image: $image, previous_repository_digest: $previous, proposed_image_id: $proposed, source_revision: $revision}' \
        > "rollback/$(basename "$receipt")"
fi
published=false
for attempt in 1 2 3; do
    if docker push "$image"; then published=true; break; fi
    if [ "$attempt" -lt 3 ]; then sleep 60; fi
done
[ "$published" = true ] || { echo "Image publication failed" >&2; exit 1; }
# A digest-qualified pull prevents a later tag change from changing this check.
published_digest=$(docker buildx imagetools inspect "$image" --format '{{json .Manifest}}' | \
    jq -er '.digest | select(test("^sha256:[0-9a-f]{64}$"))')
repository_digest="$repository@$published_digest"
docker pull "$repository_digest"
pulled_id=$(docker image inspect --format '{{.Id}}' "$repository_digest")
[ "$tested_id" = "$pulled_id" ] || { echo "Published image differs from tested image" >&2; exit 1; }
mkdir -p "$(dirname "$receipt")"
jq -n --arg image "$image" --arg digest "$repository_digest" --arg id "$tested_id" \
    --arg revision "${GITHUB_SHA:-unknown}" --arg previous "$previous_digest" \
    '{image: $image, repository_digest: $digest, image_id: $id, source_revision: $revision, previous_digest: $previous}' > "$receipt"
cat "$receipt" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
