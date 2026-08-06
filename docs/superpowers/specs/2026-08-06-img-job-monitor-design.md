# Design: `-ji` / `-je` — Monitor an Existing Image Import/Export Job

## Motivation

`-imgimport` and `-imgexport` now monitor their job to completion when they submit it (via `wait_for_job()`), but there is no way to re-attach monitoring to a job that is already running — for example after a detached/killed terminal, a lost SSH session, or a job that was submitted from a different machine. The user needs to look up an in-progress (or just-completed) import/export job and monitor it to completion without resubmitting the operation.

PowerVS exposes "get last job" endpoints for both resources, so no local state (job-ID file, log parsing) is needed — the tool can always ask the API directly, from any machine.

## A. New low-level API functions

Mirrors `img_import_api()` / `img_export_api()`'s existing shape (same headers, same `-w '\n%{http_code}'` HTTP-status-capture pattern established in the `-imgexport` plan).

- `img_import_status_api()` — `GET $base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/cos-images` (same URL as `img_import_api()`'s POST, GET instead — endpoint inferred from the IBM docs anchor `pcloud-v1-cloudinstances-cosimages-get`, alongside the already-confirmed-correct `pcloud-v1-cloudinstances-cosimages-post` anchor used for the existing `img_import_api()`).
- `img_export_status_api()` — `GET $base_url/pcloud/v2/cloud-instances/$CLOUD_INSTANCE_ID/images/$IMAGE_ID/export` (same URL as `img_export_api()`'s POST, GET instead — anchor `pcloud-v2-images-export-get` alongside the confirmed `pcloud-v2-images-export-post`).

Both use `-H "$header_auth" -H "CRN: $CRN" -H "$header_json"` like their POST counterparts, no request body.

**Confirmed response schema** (user verified against the official API reference): both endpoints return a `Job` resource:

```json
{
  "id": "...",
  "operation": {
    "action": "imageImport",
    "id": "...",
    "target": "image"
  },
  "status": {
    "message": "...",
    "progress": "...",
    "state": "running"
  }
}
```

No `imageName`/`targetImageName`/`name` field is present in this schema. Both endpoints' official documentation also explicitly lists `400`, `401`, `403`, `404`, and `500` as possible HTTP status codes — see Section C for how each is handled.

## B. New orchestration functions

### `img_import_monitor(WORKSPACE)`

1. Resolve `WORKSPACE` (short name or full name, case-insensitive) to `CRN`/`CLOUD_INSTANCE_ID`/`base_url`/`full_ws_name` — reuses (copies, not extracts — consistent with this file's existing mirror-don't-abstract convention) the resolution block already in `img_import()` (workspace-key lookup via `jq` over `.workspaces`, CRN/ID/base_url derivation). Aborts (exit 1) if the workspace isn't found or is missing CRN/ID/base_url, same messages as the existing block.
2. Calls `img_import_status_api()`, captures HTTP status same way Task 3 established (`"${raw##*$'\n'}"` / `"${raw%$'\n'*}"`).
3. Dispatches on HTTP status per Section C. Only `404` (or a `200` with an empty/job-less body) means "no history" — every other non-2xx gets its own specific message.
4. Extracts the job ID: `.id // .jobID // .job.id // .jobReference.id // empty` (confirmed schema field `.id` tried first, fallbacks kept as defensive belt-and-braces for the other resource types that reuse this pattern elsewhere in the file).
5. Logs `"Last image import job found: $job_id"` and `"Status: $job_state"` (from `.status.state`) before attaching the monitor.
6. Calls `wait_for_job "$job_id" "Image import job for workspace $full_ws_name"`.

### `img_export_monitor(IMAGE_NAME)`

1. Resolves `IMAGE_NAME` to `IMAGE_ID` by searching every workspace in `$allws` — reuses the same search-loop pattern already established in `img_export()` / `do_img_delete()` (iterate workspaces, resolve CRN/CLOUD_INSTANCE_ID/base_url per workspace, `img_ls`, exact-name match, first match wins, `break`). Aborts (exit 1) with `"Image with name $img_name not found in any Workspace."` if no match, same as `img_export()`.
2. Calls `img_export_status_api()`, captures HTTP status.
3. Same status dispatch as import (Section C).
4. Extracts job ID via the same fallback chain, logs the same "Last ... job found" / "Status: ..." pair.
5. Calls `wait_for_job "$job_id" "Image export job for image $img_name"`.

## C. HTTP status dispatch (both endpoints — official docs list 400/401/403/404/500)

Collapsing every non-2xx into a single "no job history" message is explicitly wrong (caught in spec review) — a 401/403/500 would be misreported to the user as "this workspace/image has never had a job," which is actively misleading for diagnosis. Each status gets its own message, all aborting with exit 1 except the true "no history" case:

| Status | Meaning | Message |
|---|---|---|
| `404` | No job history for this workspace/image | `"No import/export job history found for <workspace/image>."` |
| `200` with empty/job-less body | Same as 404 — some APIs return 200 with an empty object instead of 404 | Same "no job history" message |
| `400` | Invalid request | `"Invalid request while retrieving the last import/export job."` |
| `401` | IAM token invalid/expired | `"Authentication failed while retrieving the last import/export job."` |
| `403` | Not authorized | `"Not authorized to retrieve the last import/export job."` |
| `500` | PowerVS service error | `"PowerVS service error while retrieving the last import/export job."` |
| any other non-2xx | Unclassified | `"Failed to retrieve the last import/export job, HTTP status <code>."` |

All messages end with exit code 1 via `abort(..., 1)`.

**Precise "200 empty/job-less" condition** (to remove ambiguity for implementation): a `200` response is treated as "no job history" if the body is empty, OR is valid JSON but `.id` and `.status.state` are both null/absent. A `200` with a populated `.id`/`.status.state` proceeds normally (job found).

## D. Flags

- `-ji WORKSPACE` — the confirmed schema has no image-name field on the Job resource, so an optional `IMAGE_NAME` argument would have no real value (it could never be validated against anything) and risks documentation implying a check that doesn't happen. Dropped per spec review; the endpoint is workspace-scoped only, so `WORKSPACE` alone is sufficient and unambiguous.
- `-je IMAGE_NAME` — always searches every workspace; no workspace argument (deliberately, to avoid the risk of the user mistyping/misremembering the workspace and silently searching the wrong scope).

Argument-count validation in both case-dispatch blocks aborts with exit 1 (consistent with the `-imgimport`/`-imgexport` fix from the prior plan).

## E. `wait_for_job()` reuse

No changes to `wait_for_job()`. Both new orchestration functions call it exactly as `-imgimport`/`-imgexport` already do, with a label describing the workspace/image rather than a fresh submission.

## F. Documentation

- Header comment block: new "Monitor an existing import/export job" section next to the existing import/export documentation, with the exact `-ji`/`-je` syntax.
- `help()`: new entries for `-ji`/`-je` — both the general help listing and the command-specific syntax line, same plain-text/5250-safe conventions as the rest of the file.
- `README.md`: new subsection under the existing image import/export documentation.
- `CHANGELOG.md`: new entry under `### Added`.
- After implementation is complete and verified: update project memory (this is a standing session convention, not code) to record the `-ji`/`-je` feature the same way the `-imgexport` work was recorded.

## G. Versioning

Purely additive, no existing behavior changes → MINOR bump (`1.14.0` → `1.15.0`).

## Non-goals

- No local persistence of job IDs (rejected during design — the API's "last job" lookup makes it unnecessary and works across machines/sessions).
- No generic "monitor any job type by ID" flag — scoped strictly to image import/export, mirroring the existing `-imgimport`/`-imgexport` split rather than a unified command.
- `job_monitor()` and the existing `-j` (capture monitor) flag are not touched.
- No change to `-imgimport`/`-imgexport` themselves — they already call `wait_for_job()` at submission time (prior plan); this is purely for re-attaching after the fact.
- All script-facing strings (`echoscreen`/`abort` messages, `help()` text) are in English, matching the rest of the file — this document is in Portuguese only because that's the conversation language.
