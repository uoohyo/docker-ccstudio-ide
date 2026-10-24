# Read-only CCS 12.1 publication recovery

The manual `Verify existing CCS 12.1 publication recovery` workflow is deliberately
restricted to the successful Docker push from build run `40126099529`. It does not
build, run, install, push, retag, log in to Docker Hub, or change release metadata.
The Docker operations are public pull by exact digest, local image inspection, and
read-only remote tag inspection. Only the current repository's read-only GitHub
token is used to retrieve the original run and artifact.

The approved identity is fixed in the verifier rather than accepted as arbitrary
workflow input:

- Version: `12.1.0.00007`
- Original source: `f9e499f1901fef71cc4590f2d8ffed485fd7acc2`
- Tested image ID: `sha256:26f6da4c102ceb503bc4ddbb51ab974caa2f7e1cd32d89eeb3b36e7350322027`
- Successful push digest: `sha256:4de950059c533d47000cf98a480744da270398a4127af6cdc668a44abfbdb7fe`
- Original rollback artifact: `12573379312`, `rollback-12.1.0.00007`
- Previous digest: `sha256:fc22534fd50281274ce8c52d9a5efa3737bb93507ab668356c370e9651f5f729`

After provenance validation, the verifier pulls only the successful push digest
and compares its image ID with the original tested ID. It then checks the current
tag up to six times, allowing only the known previous digest during convergence.
An unrelated digest, API error, identity mismatch, or timeout fails closed without
a receipt. Recovery never retries publication.

A successful run uploads a separately named `recovery-*` artifact, not a normal
`published-*` receipt. It preserves the original rollback files and provenance
JSON, with original source/run and validation code/run recorded separately. It
does not make the original failed workflow successful, rerun installation smoke,
promote `latest`, replace the original artifact, or automatically close an issue.
Expired or missing original evidence requires investigation, not a new build or
an unverified receipt.
