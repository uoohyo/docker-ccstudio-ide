#!/usr/bin/env bash
# Persist the original release identity before any tag mutation.
set -euo pipefail
image=${1:?Image required}
receipt=${2:?Receipt path required}
repository=${image%:*}
tested_id=$(docker image inspect --format '{{.Id}}' "$image")
    # Do not replace an existing release until its exact rollback target is recorded.
    mkdir -p rollback
    docker buildx imagetools inspect "$image" --format '{{json .Manifest}}' > "rollback/$(basename "$receipt" .json).manifest.json"
    previous_digest=$(jq -er '.digest | select(test("^sha256:[0-9a-f]{64}$"))' "rollback/$(basename "$receipt" .json).manifest.json")
    docker buildx imagetools inspect "$repository@$previous_digest" --raw > "rollback/$(basename "$receipt" .json).raw-manifest.json"
    jq -n --arg image "$image" --arg previous "$repository@$previous_digest" \
        --arg proposed "$tested_id" --arg revision "${GITHUB_SHA:-unknown}" \
        '{image: $image, previous_repository_digest: $previous, proposed_image_id: $proposed, source_revision: $revision}' \
        > "rollback/$(basename "$receipt")"
