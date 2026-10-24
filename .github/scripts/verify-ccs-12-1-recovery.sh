#!/usr/bin/env bash
# Narrow, read-only recovery for a successful push whose receipt verification failed.
# These constants intentionally cannot be supplied by workflow input.
set -euo pipefail
[[ ! -e recovery ]] || { echo "Recovery output already exists; refusing to overwrite evidence" >&2; exit 1; }
version=12.1.0.00007
image="uoohyo/ccstudio-ide:$version"
repository=uoohyo/ccstudio-ide
original_run=40126099529
source_revision=f9e499f1901fef71cc4590f2d8ffed485fd7acc2
tested_id=sha256:26f6da4c102ceb503bc4ddbb51ab974caa2f7e1cd32d89eeb3b36e7350322027
published_digest=sha256:4de950059c533d47000cf98a480744da270398a4127af6cdc668a44abfbdb7fe
[[ "${GITHUB_REPOSITORY:-}" == uoohyo/docker-ccstudio-ide ]]
[[ "${GITHUB_SHA:-}" =~ ^[0-9a-f]{40}$ ]]
[[ "${GITHUB_RUN_ID:-}" =~ ^[1-9][0-9]*$ ]]
[[ "${GITHUB_RUN_ATTEMPT:-}" =~ ^[1-9][0-9]*$ ]]
[[ "$GITHUB_RUN_ID" != "$original_run" ]]
jq -e --arg sha "$source_revision" --argjson id "$original_run" '
  .id == $id and .head_sha == $sha and
  .repository.full_name == "uoohyo/docker-ccstudio-ide" and
  .head_repository.full_name == "uoohyo/docker-ccstudio-ide" and
  .path == ".github/workflows/build-all-versions.yml" and
  .event == "workflow_dispatch" and .status == "completed"
' original-run.json >/dev/null
jq -e --arg sha "$source_revision" --argjson run "$original_run" '
  .id == 12573379312 and .name == "rollback-12.1.0.00007" and .expired == false and
  .workflow_run.id == $run and .workflow_run.head_sha == $sha
' original-artifact.json >/dev/null
ledger="original-rollback/$version.json"
previous_ref=$(jq -er --arg image "$image" --arg sha "$source_revision" --arg id "$tested_id" '
  select(.image == $image and .source_revision == $sha and .proposed_image_id == $id) |
  .previous_repository_digest | select(test("^uoohyo/ccstudio-ide@sha256:[0-9a-f]{64}$"))
' "$ledger")
previous_digest=${previous_ref##*@}
[[ "$previous_digest" == sha256:fc22534fd50281274ce8c52d9a5efa3737bb93507ab668356c370e9651f5f729 ]]
jq -e --arg digest "$previous_digest" '.digest == $digest' "original-rollback/$version.manifest.json" >/dev/null
# Ensure the original raw manifest is present and valid before recovering a receipt.
jq -e 'type == "object" and .schemaVersion == 2' "original-rollback/$version.raw-manifest.json" >/dev/null
repository_digest="$repository@$published_digest"
docker pull "$repository_digest"
pulled_id=$(docker image inspect --format '{{.Id}}' "$repository_digest")
[[ "$pulled_id" == "$tested_id" ]] || { echo 'Published digest does not match the originally tested image' >&2; exit 1; }
converged=false
for attempt in 1 2 3 4 5 6; do
  current_digest=$(docker buildx imagetools inspect "$image" --format '{{json .Manifest}}' | jq -er '.digest | select(test("^sha256:[0-9a-f]{64}$"))')
  if [[ "$current_digest" == "$published_digest" ]]; then
    converged=true
    break
  fi
  [[ "$current_digest" == "$previous_digest" ]] || { echo 'Tag points at an unrelated digest; refusing recovery' >&2; exit 1; }
  echo "Tag still resolves to the recorded rollback digest ($attempt/6)" >&2
  if [[ "$attempt" -lt 6 ]]; then sleep 5; fi
done
[[ "$converged" == true ]] || { echo 'Tag did not converge; no receipt recovered' >&2; exit 1; }
mkdir -p recovery/original-rollback
cp original-rollback/*.json recovery/original-rollback/
cp original-run.json recovery/original-run.json
cp original-artifact.json recovery/original-artifact.json
jq -n --arg image "$image" --arg version "$version" --arg digest "$repository_digest" \
  --arg tested "$tested_id" --arg source "$source_revision" --arg previous "$previous_ref" \
  --arg original_run "$original_run" --arg validation_run "$GITHUB_RUN_ID" \
  --arg validation_attempt "$GITHUB_RUN_ATTEMPT" --arg validation_sha "$GITHUB_SHA" \
  '{kind: "read-only-publication-recovery", image: $image, version: $version,
    repository_digest: $digest, image_id: $tested, source_revision: $source,
    previous_repository_digest: $previous, original_run_id: $original_run, original_artifact_id: "12573379312",
    validation_run_id: $validation_run, validation_run_attempt: $validation_attempt,
    validation_code_revision: $validation_sha}' > "recovery/$version.json"
cat "recovery/$version.json"
