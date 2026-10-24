#!/usr/bin/env bash
# Publish the locally tested image without rebuilding, then verify its identity.
set -euo pipefail
image=${1:?Usage: publish-tested-image.sh IMAGE RECEIPT}
receipt=${2:?Receipt path required}
repository=${image%:*}
tested_id=$(docker image inspect --format '{{.Id}}' "$image")
[[ "$tested_id" == sha256:* ]] || { echo "Invalid tested image ID" >&2; exit 1; }
published=false
for attempt in 1 2 3; do
    if docker push "$image"; then published=true; break; fi
    if [ "$attempt" -lt 3 ]; then sleep 60; fi
done
[ "$published" = true ] || { echo "Image publication failed" >&2; exit 1; }
# A digest-qualified pull prevents a later tag change from changing this check.
repository_digest=$(docker image inspect --format '{{json .RepoDigests}}' "$image" |     jq -er --arg prefix "$repository@sha256:" '[.[] | select(startswith($prefix))][0] // error("Missing pushed digest")')
docker pull "$repository_digest"
pulled_id=$(docker image inspect --format '{{.Id}}' "$repository_digest")
[ "$tested_id" = "$pulled_id" ] || { echo "Published image differs from tested image" >&2; exit 1; }
mkdir -p "$(dirname "$receipt")"
jq -n --arg image "$image" --arg digest "$repository_digest" --arg id "$tested_id"     --arg revision "${GITHUB_SHA:-unknown}"     '{image: $image, repository_digest: $digest, image_id: $id, source_revision: $revision}' > "$receipt"
cat "$receipt" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
