# `-imgexport` design — export a boot image to Cloud Object Storage

Status: approved by user, pending spec review
Date: 2026-08-06
Repo: bluexport_api (`bluexport_api.sh`)

## Problem

`bluexport_api.sh` has `-imgimport` (import a boot image from a COS bucket into a PowerVS workspace image catalog) but no inverse operation. The user wants `-imgexport`: export an existing boot image from a workspace's image catalog to a COS bucket, mirroring `-imgimport`'s design (including `CURRACCOUNT`/`OTHERACCOUNT` cross-account support).

## Research: the underlying PowerVS API

Confirmed against IBM's official docs (`https://github.com/ibm-cloud-docs/power-iaas/blob/master/exporting-boot-image.md`, cross-checked with `importing-boot-image.md`):

- Import: `POST /pcloud/v1/cloud-instances/{id}/cos-images` (v1). Required body: `imageName`, `imageFilename`, `bucketName` (+ `accessKey`/`secretKey` for private buckets).
- Export: `POST /pcloud/v2/cloud-instances/{id}/images/{IMAGE_ID}/export` (v2 — different version, and identifies the image by **ID**, not filename). Required body: `bucketName`, `accessKey`. Optional: `region`, `secretKey`. No `imageFilename`/output-name field exists — the API decides the resulting object name in the bucket.

Consistent with this script's convention of never exposing raw IDs to the user, `-imgexport` takes an image **name** and resolves it to an `IMAGE_ID` internally, the same way `do_img_delete`/`-imgdel` already does (search every workspace by name, case-sensitive exact match, first match wins — no new disambiguation added; mirrors existing accepted behavior).

## Bug found during research (in scope, must fix)

`img_import()`'s `OTHERACCOUNT` path (`bluexport_api.sh:4426`) calls `load_hmac_keys "$hmac_file"` — **this function is never defined anywhere in the script.** `-imgimport ... OTHERACCOUNT <hmac_file>` has therefore never worked: it always fails with "Missing COS HMAC accessKey/secretKey" because `hmac_access_key`/`hmac_secret_key` are never set. Since `-imgexport` also needs `OTHERACCOUNT` support, a working HMAC-loading routine is required regardless — confirmed with the user (2026-08-06) to write it properly and wire it back into `-imgimport` too, fixing the existing bug as part of this work.

## Design

### A. `load_hmac_keys()` — new function, fixes `-imgimport`, used by `-imgexport`

Placed right before `img_import()`. Reads `.cos_hmac_keys.access_key_id` / `.cos_hmac_keys.secret_access_key` from the given JSON file path (the exact format IBM Cloud COS "Service credentials" produces — already documented in this script's header/help), validates the file is parseable JSON and both fields are present, sets globals `hmac_access_key`/`hmac_secret_key`, aborts with a clear message otherwise. No other change needed at `img_import()`'s call site — it already expects exactly these two globals.

### B. `wait_for_job()` — new generic job poller

The existing `job_monitor()` is tightly coupled to the capture/export-VSI flow (`$capture_name`, `$vsi`, `$destination`, `$bucket`, `$single`, `delete_previous_img()`, `operid_file` reuse for `-j`, a per-capture permanent log file) and is not safely reusable as-is. Decision (confirmed with user): write a new, separate, smaller function — `wait_for_job JOB_ID LABEL` — copying `job_monitor()`'s proven polling/retry skeleton (transient-failure retry up to 10 attempts/30s backoff, proactive IAM token refresh every 45min, `spin_wait`-based progress display) but with none of the capture-specific behavior. `job_monitor()` itself is left untouched — no risk to the production capture path.

Placed right after `job_monitor()`. Uses the same globals already loaded at script startup (`$job_log`, `$job_monitor`, `$log_file`) and the same `job_get()` (generic `/pcloud/v1/.../jobs/$JOB_ID` endpoint — confirmed via the export doc's own wording, "Add image export job to the jobs queue", that PowerVS uses one unified async jobs queue across capture, import, and export operations, so `job_get()` needs no changes).

**Startup race guard** (user correction, 2026-08-06): a job can take a few seconds to actually register after submission; polling immediately can hit "not found" and burn a retry attempt for no real reason. `wait_for_job()` does a `spin_wait 10 "Waiting for job to register"` before its first poll attempt — inside the function itself (not at each call site), so it automatically covers every future caller, not just import/export.

On `completed`: logs and `abort`s with a success message built from `LABEL`. On `failed`: `abort`s with the job's message. Otherwise: same queued/running/still-running progression as `job_monitor()`, using `LABEL` instead of capture-specific wording.

### C. `-imgimport` — wire in job monitoring

At the end of `img_import()` (`bluexport_api.sh:4502-4509`), after extracting `import_job_id` from the response:

- If a Job ID was returned: log it, then call `wait_for_job "$import_job_id" "Image import of $img_name_ws"` (replaces the old fire-and-forget `abort "...submitted successfully..."`).
- If no Job ID was returned: `abort` with a message explaining there's nothing to monitor and pointing at `-imglsall`/the console to confirm completion manually. This is a **behavior change** from today (today this path still reports success even with no Job ID) — confirmed acceptable by the user, since "submitted, can't confirm" is more honest than an unconditional success message once the tool claims to monitor jobs.

### D. `img_export_api()` + `img_export()` + `-imgexport` case dispatch

- `img_export_api()`: `curl -sX POST $base_url/pcloud/v2/cloud-instances/$CLOUD_INSTANCE_ID/images/$IMAGE_ID/export ...` — placed next to `img_import_api()`.
- `img_export()`: takes `IMGNAME BUCKET BUCKET_REGION CURRACCOUNT|OTHERACCOUNT [HMAC_JSON_FILE]`. Structure:
  1. Argument/format validation (region format, account type, HMAC-file mutual-exclusivity/existence) — mirrors `img_import()`'s validation style exactly.
  2. Resolve `IMAGE_ID` by searching every workspace for an exact name match — copies `do_img_delete()`'s existing loop (same CRN/CLOUD_INSTANCE_ID/base_url resolution per workspace, same `img_ls` + jq filter, first match wins).
  3. Resolve COS credentials: `CURRACCOUNT` → existing globals `$accesskey`/`$secretkey`; `OTHERACCOUNT` → `load_hmac_keys`.
  4. Pre-validate the **target bucket** (not a specific object — it doesn't exist yet) via an HTTP HEAD on the bucket root, stripping any `bucket/optional/folder` suffix from `BUCKET` first (`bucket_root="${export_bucket%%/*}"`) since S3 bucket-existence checks operate on the bucket itself. Same `--aws-sigv4`/bearer-auth branching as `img_import()`'s object-level HEAD check, same HTTP-status-to-message mapping (200/204 OK, 301/302/307/308 → likely wrong region, 403 → credentials, 404 → not found, else → generic).
  5. Build `ACTIONS` (`bucketName`, `region`, `accessKey`, `secretKey` — no `imageFilename`, per the API), call `img_export_api()`, handle API-level errors the same way `img_import()` does (HMAC/credential-keyword detection for a clearer message).
  6. Extract Job ID, call `wait_for_job "$export_job_id" "Image export of $img_name to bucket $export_bucket"` (or `abort` if no Job ID, same as the `-imgimport` change in section C).
- Case dispatch: `$# -lt 5 || $# -gt 6` (4 required + `-imgexport` itself + 1 optional HMAC file), calls `img_export "$2" "$3" "$4" "$5" "$6"`.

`BUCKET` accepts the same `bucketName/optional/folders` compound format `-imgimport` already accepts (confirmed sufficient by the user — no separate folder/prefix argument needed).

### E. Documentation

- Header comment block (mirrors the existing `-imgimport` block).
- `help()` (mirrors the existing `-imgimport` block, references the same HMAC JSON format/`hmac_keys_example.json` instead of repeating the structure).
- New file `hmac_keys_example.json` at repo root:
  ```json
  {
      "cos_hmac_keys": {
          "access_key_id": "COLOCAR_ACCESS_KEY_AQUI",
          "secret_access_key": "COLOCAR_SECRET_KEY_AQUI"
      }
  }
  ```
- `README.md`: new "Export image to COS" section next to "Import image from COS"; note that both flags now monitor the job to completion via `wait_for_job` instead of only confirming submission.
- `CHANGELOG.md`: entry covering the new `-imgexport` flag, the `load_hmac_keys` fix (and that it silently never worked before), and `wait_for_job` now backing both `-imgimport` and `-imgexport`.

### F. Versioning

`bluexport_api.sh` only. **MINOR** bump (`1.13.0` → `1.14.0`, confirmed with user): additive (`-imgexport`), a real bug fix (`load_hmac_keys`), and one observable behavior change at the tail of `-imgimport` (now monitors to completion, and now `abort`s instead of claiming success when no Job ID is returned) — none of these break existing call syntax or require any change from current callers, so MINOR rather than MAJOR.

## Non-goals

- No disambiguation for an image name that exists in more than one workspace — mirrors `do_img_delete`'s existing first-match-wins behavior, not introducing new logic here (consistent with the deferred cross-workspace-collision decision from the earlier multi-OS LPAR work).
- No control over the exported object's filename/path within the bucket beyond the existing `bucketName/optional/folders` compound-path convention — the API does not expose this, confirmed acceptable by the user.
- `job_monitor()` (capture/export-VSI flow) is not touched or refactored.
