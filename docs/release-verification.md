# Release verification and pending policy decisions

## What is automated

Each version is built and tested independently. Its matrix job publishes the same local image only after its own tests pass. Publication records the image ID, repository digest, and source revision, and verifies a digest-qualified pull. Failed versions remain failed; they do not suppress successful siblings. `latest` requires at least one verified publication receipt and a complete, valid registry lookup. Merely discovered versions never become `latest` candidates.

Image build/publication runs only through explicit dispatch; publication defaults to false. Automatic version discovery may request a build-only diagnostic, never a publication. Use `push_to_registry=false` for a selected-version diagnostic build. This still downloads and installs vendor software; it is **not** an offline or license-free test. Local unit tests and the Validate release reliability workflow use fixtures and do not perform vendor installations or publish images.

## Existing version updates

Automatic discovery continues to skip existing toolchain tags. Explicit rebuild controls are not proof that a source fix reached an existing image. Record the source revision and digest for every release, and do not mark an issue deployed until the intended version has been rebuilt and verified.

The maintainer selected updates to currently published version tags rather than a new additive tag scheme. Use `existing_versions_only=true` to intersect selected/discovered toolchains with the complete registry inventory; this excludes unpublished versions such as STM32CubeCLT 1.22.0. Start with a small explicit version selection, verify its pull/sample checks, then expand the batch.

Before overwriting an existing image, the publication script records its previous registry digest and the tested proposed image ID in a rollback ledger. A failed lookup prevents the push. The ledger is retained separately even if publication or verification fails; successful receipts record the new digest/source revision. A rollback should restore the recorded digest after confirming the exact target; it must not rebuild old source and assume equivalence. Existing component-selectable runtime installation remains unchanged. No image was deployed while developing this PR.

## Verification still required before release

- Run a selected vendor version with publication disabled after confirming installer rights and runner prerequisites.
- Exercise both a successful and failed version to verify independent matrix results.
- After separately approved publication, inspect the recorded source revision and digest and verify downstream Action/sample Debug and Release builds.
- Keep unresolved vendor access, credentials, license permissions, and policy choices explicit. A passing fixture test does not establish a successful vendor installation or deployment.

## Container restart contract

A completion marker is written only after installer success, executable validation, and compatibility patches. Restarting the same container with the same version/components reuses that installation. Changing components/version, removing the executable, or losing the marker requires recreating the container. An executable left by an interrupted installation alone is not evidence of success. Components remain selectable on first startup; no preinstalled component bundle is imposed.

## Rollback retention limits

The ledger records original manifest metadata and digest before overwrite, and verifies that the old digest can be resolved. Registry retention after retagging is not guaranteed. The metadata artifact alone does not archive every old image layer; if the registry garbage-collects unreferenced blobs, it is not a complete offline recovery backup. Preserve an authorized full image backup when that stronger rollback guarantee is required.
