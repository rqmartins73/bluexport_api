# Design: `-ji` / `-je` — Monitor an Existing Image Import/Export Job

## Motivation

`-imgimport` and `-imgexport` now monitor their job to completion when they submit it (via `wait_for_job()`), but there is no way to re-attach monitoring to a job that is already running — for example after a detached/killed terminal, a lost SSH session, or a job that was submitted from a different machine. The user needs to look up an in-progress (or just-completed) import/export job and monitor it to completion without resubmitting the operation.

PowerVS exposes "get last job" endpoints for both resources, so no local state (job-ID file, log parsing) is needed — the tool can always ask the API directly, from any machine.

## A. New low-level API functions

Mirrors `img_import_api()` / `img_export_api()`'s existing shape (same headers, same `-w '\n%{http_code}'` HTTP-status-capture pattern established in the `-imgexport` plan).

- `img_import_status_api()` — `GET $base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/cos-images` (same URL as `img_import_api()`'s POST, GET instead — endpoint inferred from the IBM docs anchor `pcloud-v1-cloudinstances-cosimages-get`, alongside the already-confirmed-correct `pcloud-v1-cloudinstances-cosimages-post` anchor used for the existing `img_import_api()`).
- `img_export_status_api()` — `GET $base_url/pcloud/v2/cloud-instances/$CLOUD_INSTANCE_ID/images/$IMAGE_ID/export` (same URL as `img_export_api()`'s POST, GET instead — anchor `pcloud-v2-images-export-get` alongside the confirmed `pcloud-v2-images-export-post`).

Both use `-H "$header_auth" -H "CRN: $CRN" -H "$header_json"` like their POST counterparts, no request body.

**Known unknown:** the exact response body schema was not confirmed against live documentation (the IBM API reference page is a heavy client-rendered SPA that could not be scraped). The response is assumed to be the same `Job` resource shape already used by the unified jobs queue (`status.state`, `status.message`, `status.progress`, and a job-id field reachable via the existing fallback chain `.jobID // .id // .job.id // .jobReference.id`) — this is the same resource family (IBM's own docs describe both the "Ongoing job status dialog" and these "last job" endpoints in identical terms). This will be verified against the real API during implementation/testing (Task-6-style, same as the `-imgexport` plan's undocumented 409 behavior) and the jq extraction adjusted if reality differs.

## B. New orchestration functions

### `img_import_monitor(WORKSPACE, [IMAGE_NAME])`

1. Resolve `WORKSPACE` (short name or full name, case-insensitive) to `CRN`/`CLOUD_INSTANCE_ID`/`base_url`/`full_ws_name` — reuses (copies, not extracts — consistent with this file's existing mirror-don't-abstract convention) the resolution block already in `img_import()` (workspace-key lookup via `jq` over `.workspaces`, CRN/ID/base_url derivation). Aborts (exit 1) if the workspace isn't found or is missing CRN/ID/base_url, same messages as the existing block.
2. Calls `img_import_status_api()`, captures HTTP status same way Task 3 established (`"${raw##*$'\n'}"` / `"${raw%$'\n'*}"`).
3. If the HTTP status is not 2xx, the body is empty, or the body parses but has no `.status.state` field: abort (exit 1) with `"No import job history found for workspace $full_ws_name."`
4. Extracts the job ID via the established fallback chain.
5. If `IMAGE_NAME` was given: best-effort, non-blocking check — if the response has a plausible target-image-name field (try `.imageName // .targetImageName // .name // empty`) and it doesn't case-insensitively match `IMAGE_NAME`, log a warning to the screen and log file (`"WARNING - the last import job's target image name ('X') does not match the name you gave ('Y') - monitoring it anyway, since this is the only import job on record for this workspace."`) but continue — never aborts on a name mismatch, since the API only ever tracks one (the most recent) import job per workspace regardless of name.
6. Calls `wait_for_job "$job_id" "Image import job for workspace $full_ws_name"`.

### `img_export_monitor(IMAGE_NAME)`

1. Resolves `IMAGE_NAME` to `IMAGE_ID` by searching every workspace in `$allws` — reuses the same search-loop pattern already established in `img_export()` / `do_img_delete()` (iterate workspaces, resolve CRN/CLOUD_INSTANCE_ID/base_url per workspace, `img_ls`, exact-name match, first match wins, `break`). Aborts (exit 1) with `"Image with name $img_name not found in any Workspace."` if no match, same as `img_export()`.
2. Calls `img_export_status_api()`, captures HTTP status.
3. Same "no job history" detection as import: abort (exit 1) with `"No export job history found for image $img_name."`
4. Extracts job ID via the fallback chain.
5. Calls `wait_for_job "$job_id" "Image export job for image $img_name"`.

## C. "No job history" detection

Three independent conditions, any one of which triggers the abort described above — deliberately conservative given the schema is unconfirmed:
- HTTP status is not `2xx`.
- Response body is empty.
- Response body is valid JSON but `.status.state` is null/absent.

## D. Flags

- `-ji WORKSPACE [IMAGE_NAME]` — `IMAGE_NAME` optional, used only for the best-effort mismatch warning in B.1.5.
- `-je IMAGE_NAME` — always searches every workspace; no workspace argument (deliberately, to avoid the risk of the user mistyping/misremembering the workspace and silently searching the wrong scope).

Argument-count validation in both case-dispatch blocks aborts with exit 1 (consistent with the `-imgimport`/`-imgexport` fix from the prior plan).

## E. `wait_for_job()` reuse

No changes to `wait_for_job()`. Both new orchestration functions call it exactly as `-imgimport`/`-imgexport` already do, with a label describing the workspace/image rather than a fresh submission.

## F. Documentation

- Header comment block: new "Monitor an existing import/export job" section next to the existing import/export documentation.
- `help()`: new entries for `-ji`/`-je`, same plain-text/5250-safe conventions as the rest of the file.
- `README.md`: new subsection under the existing image import/export documentation.
- `CHANGELOG.md`: new entry under `### Added`.

## G. Versioning

Purely additive, no existing behavior changes → MINOR bump (`1.14.0` → `1.15.0`).

## Non-goals

- No local persistence of job IDs (rejected during design — the API's "last job" lookup makes it unnecessary and works across machines/sessions).
- No generic "monitor any job type by ID" flag — scoped strictly to image import/export, mirroring the existing `-imgimport`/`-imgexport` split rather than a unified command.
- `job_monitor()` and the existing `-j` (capture monitor) flag are not touched.
- No change to `-imgimport`/`-imgexport` themselves — they already call `wait_for_job()` at submission time (prior plan); this is purely for re-attaching after the fact.
- All script-facing strings (`echoscreen`/`abort` messages, `help()` text) are in English, matching the rest of the file — this document is in Portuguese only because that's the conversation language.
