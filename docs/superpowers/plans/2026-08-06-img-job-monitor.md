# `-ji` / `-je` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `-ji WORKSPACE` and `-je IMAGE_NAME` to `bluexport_api.sh` — re-attach monitoring to an already-running (or just-completed) image import/export job without resubmitting it, using PowerVS's "get last job" endpoints instead of any locally stored job ID.

**Architecture:** Two new thin API wrapper functions (`img_import_status_api()`, `img_export_status_api()`) mirror the existing `img_import_api()`/`img_export_api()` shape. Two new orchestration functions (`img_import_monitor()`, `img_export_monitor()`) resolve the workspace/image the same way `img_import()`/`img_export()` already do, call the new status APIs, dispatch on the confirmed HTTP status codes, and hand the resolved Job ID to the existing `wait_for_job()` — unchanged.

**Tech Stack:** Bash (IBM i PASE-compatible), `jq`, `curl`.

## Global Constraints

- Must remain IBM i PASE/QShell-compatible — no Linux-only constructs, no GNU-only flags not already used elsewhere in this file.
- `wait_for_job()` is not modified in any way — both new functions call it exactly as `img_import()`/`img_export()` already do (`wait_for_job "$job_id" "$label"`).
- `job_monitor()` and the existing `-j` (capture monitor) flag are not touched.
- HTTP status dispatch must NOT collapse every non-2xx into "no job history" — `400`/`401`/`403`/`500`/other-unclassified each get their own distinct message; only `404` or a `2xx` response with an empty/job-less body means "no job history." See spec Section C for the exact table.
- Job ID extraction: `.id // .jobID // .job.id // .jobReference.id // empty` — confirmed schema field `.id` tried first.
- For a 2xx response: an empty body, or a body that both `.id` and `.status.state` are null/absent for, means "no job history." A non-empty body that fails to parse as JSON is a distinct failure ("Invalid response received...", exit 1) — never silently treated as "no job history." `.status.state` alone (without `.id`) is NOT sufficient to proceed — `wait_for_job()` requires a real Job ID to poll, so a response with `.status.state` set but `.id` empty/absent is its own failure ("...response did not include a Job ID...", exit 1), distinct from "no history." Only `.id` present (with or without `.status.state`) counts as "job found."
- `-ji` takes `WORKSPACE` only (no optional image-name argument — dropped in spec review, the confirmed Job resource schema has no name field).
- `-je` takes `IMAGE_NAME` only (no workspace argument — always searches every workspace in `$allws`, per spec review, to avoid a mistyped workspace silently narrowing the search).
- Every abort() call in new code passes `1` as the second argument (genuine failure = exit 1).
- Version bump: MINOR (`1.14.0` → `1.15.0`) — purely additive, no existing behavior changes.
- Spec: `docs/superpowers/specs/2026-08-06-img-job-monitor-design.md` (approved).

---

## File Structure

- Modify `bluexport_api.sh` only:
  - New `img_import_status_api()` / `img_export_status_api()` — placed immediately after `img_export_api()` (currently line 828-830, before the `## Snapshots` comment at line 832).
  - New `img_import_monitor()` — placed immediately after `img_import()` (currently ends before `img_export()` at line 4674).
  - New `img_export_monitor()` — placed immediately after `img_export()` (currently ends before line ~4870, confirm with grep).
  - New `-ji)` / `-je)` case dispatch blocks — placed immediately after the existing `-imgexport)` block (currently lines 5636-5642).
  - Header comment block and `help()` — new `-ji`/`-je` documentation.
  - `README.md`, `CHANGELOG.md`.
  - `Version=` (line 154) — bump to `1.15.0`.

---

### Task 1: `img_import_status_api()` + `img_import_monitor()` + `-ji` dispatch

**Files:**
- Modify: `bluexport_api.sh` — new function `img_import_status_api()`, placed immediately after `img_export_api()` (confirm current line with `grep -n '^img_export_api() {' bluexport_api.sh` first)
- Modify: `bluexport_api.sh` — new function `img_import_monitor()`, placed immediately after `img_import()`'s closing `}` and its `#### END:FUNCTION` marker (confirm current line with `grep -n '^img_import() {\|^img_export() {' bluexport_api.sh` first)
- Modify: `bluexport_api.sh` — new `-ji)` case block, placed immediately after the existing `-imgexport)` case block's closing `;;` (confirm current line with `grep -n '^   -imgexport)' bluexport_api.sh` first)

**Interfaces:**
- Consumes: `abort MESSAGE [EXIT_CODE]`, `wait_for_job JOB_ID LABEL` (both existing, unchanged), globals `$bluexscrt`, `$header_auth`, `$header_json`, `$log_file`, and the `base_<region>` indirection pattern already used throughout the file.
- Produces: `img_import_status_api()` (no args, relies on `$base_url`/`$CLOUD_INSTANCE_ID`/`$CRN` already being set by the caller), `img_import_monitor WORKSPACE` (resolves workspace, finds the last import job, calls `wait_for_job`). Consumed only by this task's own `-ji` dispatch.

- [ ] **Step 1: Confirm current line numbers**

Run: `grep -n '^img_export_api() {\|^img_import() {\|^img_export() {\|^   -imgexport)' bluexport_api.sh`

Read from `img_export_api() {` to its closing `}` to confirm the insertion point for Step 2. Read `img_import()`'s full body (from `#### START:FUNCTION` to `#### END:FUNCTION`) to confirm its exact workspace-resolution block (used verbatim in Step 3) still matches what's quoted below.

- [ ] **Step 2: Add `img_import_status_api()` immediately after `img_export_api()`**

Insert immediately after `img_export_api()`'s closing `}`:

```bash

img_import_status_api() {
	curl -sX GET $base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/cos-images -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -w '\n%{http_code}'
}
```

- [ ] **Step 3: Add `img_import_monitor()` immediately after `img_import()`**

Insert immediately after `img_import()`'s closing `}` and its `#### END:FUNCTION` marker:

```bash

####  START:FUNCTION - Monitor Existing Image Import Job (img_import_monitor) ####
# img_import_monitor WORKSPACE
#   Re-attaches monitoring to the last import job PowerVS has on record for the given
#   workspace, without resubmitting anything. Uses PowerVS's "get last cos-image import
#   job" endpoint (workspace-scoped - no image name involved, since the confirmed Job
#   resource has no name field and the endpoint only ever tracks one, the most recent,
#   import job per workspace).
img_import_monitor() {
	local workspace_to_import="$1"

	if [[ -z "$workspace_to_import" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many or too few arguments!! Syntax: bluexport_api.sh -ji WORKSPACE" 1
	fi

	local ws_key=""
	ws_key=$(jq -r --arg ws "$workspace_to_import" '
		.workspaces
		| to_entries[]?
		| select((.key | ascii_downcase) == ($ws | ascii_downcase) or (.value.name | ascii_downcase) == ($ws | ascii_downcase))
		| .key
	' "$bluexscrt" 2>>"$log_file" | head -n1)
	if [[ -z "$ws_key" || "$ws_key" == "null" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Workspace $workspace_to_import not found in $bluexscrt. Use the workspace short name or full workspace name from your JSON." 1
	fi

	CRN=$(jq -r --arg ws "$ws_key" '.workspaces[$ws].crn' "$bluexscrt")
	CLOUD_INSTANCE_ID=$(jq -r --arg ws "$ws_key" '.workspaces[$ws].id' "$bluexscrt")
	full_ws_name=$(jq -r --arg ws "$ws_key" '.workspaces[$ws].name // $ws' "$bluexscrt")
	if [[ -z "$CRN" || "$CRN" == "null" || -z "$CLOUD_INSTANCE_ID" || "$CLOUD_INSTANCE_ID" == "null" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Workspace $ws_key ($full_ws_name) missing CRN or ID in $bluexscrt. Aborting..." 1
	fi

	region_api=$(echo "$CRN" | sed -n 's/.*power-iaas:\([^:]*\):.*/\1/p' | tr '-' '_')
	base_url_var="base_${region_api}"
	base_url="${!base_url_var}"
	if [[ -z "$base_url" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Could not resolve PowerVS API endpoint for workspace $full_ws_name region $region_api." 1
	fi

	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Workspace resolved: $workspace_to_import -> $ws_key ($full_ws_name)." "1"
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Retrieving last image import job for Workspace $full_ws_name..." "1"

	local status_raw status_http_code status_resp job_id job_state
	status_raw=$(img_import_status_api 2>>"$log_file")
	status_http_code="${status_raw##*$'\n'}"
	status_resp="${status_raw%$'\n'*}"
	echo "$status_resp" >> "$log_file"

	case "$status_http_code" in
		2*)
			if [[ -z "$status_resp" ]]
			then
				abort "`date +%Y-%m-%d_%H:%M:%S` - No import job history found for workspace $full_ws_name." 1
			fi
			if ! printf '%s' "$status_resp" | jq -e . >/dev/null 2>&1
			then
				abort "`date +%Y-%m-%d_%H:%M:%S` - Invalid response received while retrieving the last import job for workspace $full_ws_name. Check $log_file." 1
			fi
			job_id=$(printf '%s' "$status_resp" | jq -r '.id // .jobID // .job.id // .jobReference.id // empty' 2>/dev/null)
			job_state=$(printf '%s' "$status_resp" | jq -r '.status.state // empty' 2>/dev/null)
			if [[ -z "$job_id" && -z "$job_state" ]]
			then
				abort "`date +%Y-%m-%d_%H:%M:%S` - No import job history found for workspace $full_ws_name." 1
			elif [[ -z "$job_id" ]]
			then
				abort "`date +%Y-%m-%d_%H:%M:%S` - Import job history was returned, but the response did not include a Job ID. Check $log_file." 1
			fi
			;;
		404)
			abort "`date +%Y-%m-%d_%H:%M:%S` - No import job history found for workspace $full_ws_name." 1
			;;
		400)
			abort "`date +%Y-%m-%d_%H:%M:%S` - Invalid request while retrieving the last import job for workspace $full_ws_name." 1
			;;
		401)
			abort "`date +%Y-%m-%d_%H:%M:%S` - Authentication failed while retrieving the last import job for workspace $full_ws_name." 1
			;;
		403)
			abort "`date +%Y-%m-%d_%H:%M:%S` - Not authorized to retrieve the last import job for workspace $full_ws_name." 1
			;;
		500)
			abort "`date +%Y-%m-%d_%H:%M:%S` - PowerVS service error while retrieving the last import job for workspace $full_ws_name." 1
			;;
		*)
			abort "`date +%Y-%m-%d_%H:%M:%S` - Failed to retrieve the last import job for workspace $full_ws_name, HTTP status $status_http_code." 1
			;;
	esac

	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Last image import job found: $job_id" "1"
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Status: $job_state" "1"
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Attaching monitor..." "1"
	wait_for_job "$job_id" "Image import job for workspace $full_ws_name"
}
####  END:FUNCTION - Monitor Existing Image Import Job ####
```

- [ ] **Step 4: Add the `-ji` case dispatch**

Insert immediately after the existing `-imgexport)` case block's closing `;;`:

```bash

   -ji)
	if [[ $# -ne 2 ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many or too few arguments!! Syntax: bluexport_api.sh -ji WORKSPACE" 1
	fi
	img_import_monitor "$2"
    ;;
```

- [ ] **Step 5: Syntax check**

Run: `bash -n bluexport_api.sh`
Expected: no output.

- [ ] **Step 6: Write and run a mocked functional test**

Create `/tmp/test_img_import_monitor.sh`:

```bash
#!/bin/bash
set -uo pipefail
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

REPO=/home/rqmartins/Git/bluexport_api
source <(sed -n '/^abort() {/,/^}/p' "$REPO/bluexport_api.sh")
source <(sed -n '/^img_import_monitor() {/,/^}/p' "$REPO/bluexport_api.sh")

log_file="$WORKDIR/test.log"
end_log_file=""
: > "$log_file"
echoscreen() { echo "LOG: $1" >> "$WORKDIR/echoscreen.log"; }

bluexscrt="$WORKDIR/bluexscrt.json"
cat > "$bluexscrt" <<'EOF'
{
  "workspaces": {"WS1": {"crn":"crn:v1:bluemix:public:power-iaas:us-east:a/x:id1::", "id":"cloudinst1", "name":"Workspace One"}}
}
EOF
base_us_east="https://us-east.power-iaas.cloud.ibm.com"
header_auth="Authorization: Bearer faketoken"
header_json="Content-Type: application/json"

fail=0

echo "=== Case 1: workspace not found -> abort 1 ==="
( img_import_monitor "NOPE" ) >/dev/null 2>&1
rc=$?
if [[ "$rc" == "1" ]]; then echo "PASS"; else echo "FAIL: rc=$rc"; fail=1; fi

echo "=== Case 2: 2xx with valid job -> wait_for_job called with correct ID ==="
img_import_status_api() { printf '{"id":"job-abc","status":{"state":"running"}}\n200'; }
wait_for_job() { echo "WAIT_FOR_JOB_CALLED: $1" > "$WORKDIR/wfj.log"; }
rm -f "$WORKDIR/wfj.log"
( img_import_monitor "WS1" ) >/dev/null 2>&1
if [[ "$(cat "$WORKDIR/wfj.log" 2>/dev/null)" == "WAIT_FOR_JOB_CALLED: job-abc" ]]; then echo "PASS"; else echo "FAIL: $(cat "$WORKDIR/wfj.log" 2>/dev/null)"; fail=1; fi

echo "=== Case 3: 2xx with empty job-less body -> no history, exit 1 ==="
img_import_status_api() { printf '{}\n200'; }
: > "$log_file"
( img_import_monitor "WS1" ) >/dev/null 2>&1
rc=$?
if [[ "$rc" == "1" ]] && grep -q "No import job history found" "$log_file"; then echo "PASS"; else echo "FAIL: rc=$rc log=$(cat "$log_file")"; fail=1; fi

echo "=== Case 4: 404 -> no history, exit 1 ==="
img_import_status_api() { printf '\n404'; }
: > "$log_file"
( img_import_monitor "WS1" ) >/dev/null 2>&1
rc=$?
if [[ "$rc" == "1" ]] && grep -q "No import job history found" "$log_file"; then echo "PASS"; else echo "FAIL: rc=$rc log=$(cat "$log_file")"; fail=1; fi

echo "=== Case 5: 401 -> authentication failed, exit 1 ==="
img_import_status_api() { printf '{"message":"invalid token"}\n401'; }
: > "$log_file"
( img_import_monitor "WS1" ) >/dev/null 2>&1
rc=$?
if [[ "$rc" == "1" ]] && grep -q "Authentication failed" "$log_file"; then echo "PASS"; else echo "FAIL: rc=$rc log=$(cat "$log_file")"; fail=1; fi

echo "=== Case 6: 403 -> not authorized, exit 1 ==="
img_import_status_api() { printf '{"message":"forbidden"}\n403'; }
: > "$log_file"
( img_import_monitor "WS1" ) >/dev/null 2>&1
rc=$?
if [[ "$rc" == "1" ]] && grep -q "Not authorized" "$log_file"; then echo "PASS"; else echo "FAIL: rc=$rc log=$(cat "$log_file")"; fail=1; fi

echo "=== Case 7: 500 -> service error, exit 1 ==="
img_import_status_api() { printf '{"message":"boom"}\n500'; }
: > "$log_file"
( img_import_monitor "WS1" ) >/dev/null 2>&1
rc=$?
if [[ "$rc" == "1" ]] && grep -q "PowerVS service error" "$log_file"; then echo "PASS"; else echo "FAIL: rc=$rc log=$(cat "$log_file")"; fail=1; fi

echo "=== Case 8: 400 -> invalid request, exit 1 ==="
img_import_status_api() { printf '{"message":"bad"}\n400'; }
: > "$log_file"
( img_import_monitor "WS1" ) >/dev/null 2>&1
rc=$?
if [[ "$rc" == "1" ]] && grep -q "Invalid request" "$log_file"; then echo "PASS"; else echo "FAIL: rc=$rc log=$(cat "$log_file")"; fail=1; fi

echo "=== Case 9: 502 (unclassified) -> generic failure message with status code, exit 1 ==="
img_import_status_api() { printf '{}\n502'; }
: > "$log_file"
( img_import_monitor "WS1" ) >/dev/null 2>&1
rc=$?
if [[ "$rc" == "1" ]] && grep -q "Failed to retrieve the last import job" "$log_file" && grep -q "502" "$log_file"; then echo "PASS"; else echo "FAIL: rc=$rc log=$(cat "$log_file")"; fail=1; fi

echo "=== Case 10: 2xx with status.state but NO Job ID -> exit 1, distinct message (never calls wait_for_job with an empty ID) ==="
img_import_status_api() { printf '{"status":{"state":"running"}}\n200'; }
wait_for_job() { echo "WAIT_FOR_JOB_CALLED: $1" > "$WORKDIR/wfj.log"; }
rm -f "$WORKDIR/wfj.log"
: > "$log_file"
( img_import_monitor "WS1" ) >/dev/null 2>&1
rc=$?
if [[ "$rc" == "1" ]] && grep -q "did not include a Job ID" "$log_file" && [[ ! -f "$WORKDIR/wfj.log" ]]; then echo "PASS"; else echo "FAIL: rc=$rc log=$(cat "$log_file") wfj=$(cat "$WORKDIR/wfj.log" 2>/dev/null)"; fail=1; fi

echo "=== Case 11: 2xx with Job ID but NO status.state -> Job ID alone is sufficient, wait_for_job called ==="
img_import_status_api() { printf '{"id":"job-noState"}\n200'; }
wait_for_job() { echo "WAIT_FOR_JOB_CALLED: $1" > "$WORKDIR/wfj.log"; }
rm -f "$WORKDIR/wfj.log"
( img_import_monitor "WS1" ) >/dev/null 2>&1
if [[ "$(cat "$WORKDIR/wfj.log" 2>/dev/null)" == "WAIT_FOR_JOB_CALLED: job-noState" ]]; then echo "PASS"; else echo "FAIL: $(cat "$WORKDIR/wfj.log" 2>/dev/null)"; fail=1; fi

echo "=== Case 12: 2xx with a non-JSON body -> exit 1, 'Invalid response' message, NOT treated as no-history ==="
img_import_status_api() { printf 'Service temporarily unavailable\n200'; }
: > "$log_file"
( img_import_monitor "WS1" ) >/dev/null 2>&1
rc=$?
if [[ "$rc" == "1" ]] && grep -q "Invalid response" "$log_file" && ! grep -q "No import job history found" "$log_file"; then echo "PASS"; else echo "FAIL: rc=$rc log=$(cat "$log_file")"; fail=1; fi

if [[ $fail -eq 0 ]]; then echo "ALL PASS"; else echo "SOME TESTS FAILED"; exit 1; fi
```

Run: `bash /tmp/test_img_import_monitor.sh`
Expected: 12 `PASS` lines then `ALL PASS`.

- [ ] **Step 7: Clean up the verification script**

Run: `rm -f /tmp/test_img_import_monitor.sh`

- [ ] **Step 8: Commit**

```bash
cd /home/rqmartins/Git/bluexport_api
git add bluexport_api.sh
git commit -m "$(cat <<'EOF'
Add -ji: re-attach monitoring to an existing image import job

img_import_status_api() GETs the same URL img_import_api() POSTs to
(PowerVS's "get last cos-image import job" endpoint, workspace-scoped -
confirmed against the official API reference). img_import_monitor()
resolves WORKSPACE the same way img_import() already does, dispatches
on the confirmed HTTP status codes (400/401/403/404/500/other each get
a distinct message - collapsing them into a single "no job history"
message would misreport an auth/permission failure as "never ran"),
extracts the Job ID, and hands off to the existing wait_for_job() -
unchanged. No job ID is ever stored locally; every invocation asks
PowerVS directly, so this works even monitoring from a different
machine than the one that submitted the import.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: `img_export_status_api()` + `img_export_monitor()` + `-je` dispatch

**Files:**
- Modify: `bluexport_api.sh` — new function `img_export_status_api()`, placed immediately after `img_import_status_api()` (Task 1's addition — confirm current line with `grep -n '^img_import_status_api() {' bluexport_api.sh` first)
- Modify: `bluexport_api.sh` — new function `img_export_monitor()`, placed immediately after `img_export()`'s closing `}` and its `#### END:FUNCTION` marker (confirm current line with `grep -n '^img_export() {' bluexport_api.sh` first — line numbers have shifted since Task 1)
- Modify: `bluexport_api.sh` — new `-je)` case block, placed immediately after Task 1's `-ji)` case block's closing `;;`

**Interfaces:**
- Consumes: `abort MESSAGE [EXIT_CODE]`, `wait_for_job JOB_ID LABEL`, `img_ls()` (existing, unchanged), globals `$allws`, `$bluexscrt`, `$header_auth`, `$header_json`, `$log_file`.
- Produces: `img_export_status_api()`, `img_export_monitor IMAGE_NAME`. Consumed only by this task's own `-je` dispatch.

- [ ] **Step 1: Confirm current line numbers**

Run: `grep -n '^img_import_status_api() {\|^img_export() {\|^   -ji)' bluexport_api.sh`

Read `img_export()`'s full body to confirm its exact workspace-search loop (used verbatim in Step 3) still matches what's quoted below.

- [ ] **Step 2: Add `img_export_status_api()` immediately after `img_import_status_api()`**

Insert immediately after `img_import_status_api()`'s closing `}`:

```bash

img_export_status_api() {
	curl -sX GET $base_url/pcloud/v2/cloud-instances/$CLOUD_INSTANCE_ID/images/$IMAGE_ID/export -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -w '\n%{http_code}'
}
```

- [ ] **Step 3: Add `img_export_monitor()` immediately after `img_export()`**

Insert immediately after `img_export()`'s closing `}` and its `#### END:FUNCTION` marker:

```bash

####  START:FUNCTION - Monitor Existing Image Export Job (img_export_monitor) ####
# img_export_monitor IMAGE_NAME
#   Re-attaches monitoring to the last export job PowerVS has on record for the given
#   image, without resubmitting anything. Uses PowerVS's "get last image export job"
#   endpoint (image-scoped, unlike import's workspace-scoped equivalent) - resolves
#   IMAGE_NAME to an IMAGE_ID by searching every workspace, same pattern as img_export().
img_export_monitor() {
	local img_name="$1"

	if [[ -z "$img_name" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many or too few arguments!! Syntax: bluexport_api.sh -je IMAGE_NAME" 1
	fi

	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - === Looking up last export job for image $img_name ===" "1"

	read -r -a allws_array <<< "$allws"
	local IMAGE_ID="" found_ws="" found_ws_name=""
	for ws in "${allws_array[@]}"
	do
		CRN=$(jq -r --arg ws "$ws" '.workspaces[$ws].crn' "$bluexscrt")
		CLOUD_INSTANCE_ID=$(jq -r --arg ws "$ws" '.workspaces[$ws].id' "$bluexscrt")
		full_ws_name=$(jq -r --arg ws "$ws" '.workspaces[$ws].name' "$bluexscrt" 2>>"$log_file")
		if [[ -z "$full_ws_name" || "$full_ws_name" == "null" ]]; then full_ws_name="$ws"; fi
		if [[ -z "$CRN" || "$CRN" == "null" || -z "$CLOUD_INSTANCE_ID" || "$CLOUD_INSTANCE_ID" == "null" ]]
		then
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Workspace $ws ($full_ws_name) missing CRN or ID in $bluexscrt, skipping." "1"
			continue
		fi
		region_api=$(echo "$CRN" | sed -n 's/.*power-iaas:\([^:]*\):.*/\1/p' | tr '-' '_')
		if [[ -z "$region_api" ]]
		then
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Could not parse region from CRN $CRN for workspace $full_ws_name, skipping." "1"
			continue
		fi
		base_url_var="base_${region_api}"
		base_url="${!base_url_var}"
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Checking for Image $img_name in Workspace $full_ws_name..." "1"
		local imgs_json
		imgs_json=$(img_ls 2>>"$log_file")
		if [[ -z "$imgs_json" ]]
		then
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Could not retrieve image list via API in workspace $full_ws_name, skipping." "1"
			continue
		fi
		IMAGE_ID=$(echo "$imgs_json" | jq -r --arg name "$img_name" '.images[]? | select(.name == $name) | .imageID' 2>>"$log_file" | head -n1)
		if [[ -n "$IMAGE_ID" && "$IMAGE_ID" != "null" ]]
		then
			found_ws="$ws"
			found_ws_name="$full_ws_name"
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Image $img_name found in Workspace $found_ws_name with ID: $IMAGE_ID" "1"
			break
		fi
	done
	if [[ -z "$IMAGE_ID" || "$IMAGE_ID" == "null" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Image with name $img_name not found in any Workspace." 1
	fi

	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Retrieving last image export job for image $img_name..." "1"

	local status_raw status_http_code status_resp job_id job_state
	status_raw=$(img_export_status_api 2>>"$log_file")
	status_http_code="${status_raw##*$'\n'}"
	status_resp="${status_raw%$'\n'*}"
	echo "$status_resp" >> "$log_file"

	case "$status_http_code" in
		2*)
			if [[ -z "$status_resp" ]]
			then
				abort "`date +%Y-%m-%d_%H:%M:%S` - No export job history found for image $img_name." 1
			fi
			if ! printf '%s' "$status_resp" | jq -e . >/dev/null 2>&1
			then
				abort "`date +%Y-%m-%d_%H:%M:%S` - Invalid response received while retrieving the last export job for image $img_name. Check $log_file." 1
			fi
			job_id=$(printf '%s' "$status_resp" | jq -r '.id // .jobID // .job.id // .jobReference.id // empty' 2>/dev/null)
			job_state=$(printf '%s' "$status_resp" | jq -r '.status.state // empty' 2>/dev/null)
			if [[ -z "$job_id" && -z "$job_state" ]]
			then
				abort "`date +%Y-%m-%d_%H:%M:%S` - No export job history found for image $img_name." 1
			elif [[ -z "$job_id" ]]
			then
				abort "`date +%Y-%m-%d_%H:%M:%S` - Export job history was returned, but the response did not include a Job ID. Check $log_file." 1
			fi
			;;
		404)
			abort "`date +%Y-%m-%d_%H:%M:%S` - No export job history found for image $img_name." 1
			;;
		400)
			abort "`date +%Y-%m-%d_%H:%M:%S` - Invalid request while retrieving the last export job for image $img_name." 1
			;;
		401)
			abort "`date +%Y-%m-%d_%H:%M:%S` - Authentication failed while retrieving the last export job for image $img_name." 1
			;;
		403)
			abort "`date +%Y-%m-%d_%H:%M:%S` - Not authorized to retrieve the last export job for image $img_name." 1
			;;
		500)
			abort "`date +%Y-%m-%d_%H:%M:%S` - PowerVS service error while retrieving the last export job for image $img_name." 1
			;;
		*)
			abort "`date +%Y-%m-%d_%H:%M:%S` - Failed to retrieve the last export job for image $img_name, HTTP status $status_http_code." 1
			;;
	esac

	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Last image export job found: $job_id" "1"
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Status: $job_state" "1"
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Attaching monitor..." "1"
	wait_for_job "$job_id" "Image export job for image $img_name"
}
####  END:FUNCTION - Monitor Existing Image Export Job ####
```

- [ ] **Step 4: Add the `-je` case dispatch**

Insert immediately after the `-ji)` case block's closing `;;` (Task 1's addition):

```bash

   -je)
	if [[ $# -ne 2 ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many or too few arguments!! Syntax: bluexport_api.sh -je IMAGE_NAME" 1
	fi
	img_export_monitor "$2"
    ;;
```

- [ ] **Step 5: Syntax check**

Run: `bash -n bluexport_api.sh`
Expected: no output.

- [ ] **Step 6: Write and run a mocked functional test**

Create `/tmp/test_img_export_monitor.sh`:

```bash
#!/bin/bash
set -uo pipefail
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

REPO=/home/rqmartins/Git/bluexport_api
source <(sed -n '/^abort() {/,/^}/p' "$REPO/bluexport_api.sh")
source <(sed -n '/^img_export_monitor() {/,/^}/p' "$REPO/bluexport_api.sh")

log_file="$WORKDIR/test.log"
end_log_file=""
: > "$log_file"
echoscreen() { echo "LOG: $1" >> "$WORKDIR/echoscreen.log"; }

bluexscrt="$WORKDIR/bluexscrt.json"
cat > "$bluexscrt" <<'EOF'
{
  "workspaces": {"WS1": {"crn":"crn:v1:bluemix:public:power-iaas:us-east:a/x:id1::", "id":"cloudinst1", "name":"Workspace One"}}
}
EOF
allws="WS1"
base_us_east="https://us-east.power-iaas.cloud.ibm.com"
header_auth="Authorization: Bearer faketoken"
header_json="Content-Type: application/json"

img_ls() { echo '{"images":[{"name":"myimage","imageID":"img-id-123"}]}'; }

fail=0

echo "=== Case 1: image not found -> abort 1 ==="
img_ls() { echo '{"images":[]}'; }
( img_export_monitor "nosuchimage" ) >/dev/null 2>&1
rc=$?
if [[ "$rc" == "1" ]]; then echo "PASS"; else echo "FAIL: rc=$rc"; fail=1; fi
img_ls() { echo '{"images":[{"name":"myimage","imageID":"img-id-123"}]}'; }

echo "=== Case 2: 2xx with valid job -> wait_for_job called with correct ID ==="
img_export_status_api() { printf '{"id":"job-xyz","status":{"state":"completed"}}\n200'; }
wait_for_job() { echo "WAIT_FOR_JOB_CALLED: $1" > "$WORKDIR/wfj.log"; }
rm -f "$WORKDIR/wfj.log"
( img_export_monitor "myimage" ) >/dev/null 2>&1
if [[ "$(cat "$WORKDIR/wfj.log" 2>/dev/null)" == "WAIT_FOR_JOB_CALLED: job-xyz" ]]; then echo "PASS"; else echo "FAIL: $(cat "$WORKDIR/wfj.log" 2>/dev/null)"; fail=1; fi

echo "=== Case 3: 2xx with empty job-less body -> no history, exit 1 ==="
img_export_status_api() { printf '{}\n200'; }
: > "$log_file"
( img_export_monitor "myimage" ) >/dev/null 2>&1
rc=$?
if [[ "$rc" == "1" ]] && grep -q "No export job history found" "$log_file"; then echo "PASS"; else echo "FAIL: rc=$rc log=$(cat "$log_file")"; fail=1; fi

echo "=== Case 4: 404 -> no history, exit 1 ==="
img_export_status_api() { printf '\n404'; }
: > "$log_file"
( img_export_monitor "myimage" ) >/dev/null 2>&1
rc=$?
if [[ "$rc" == "1" ]] && grep -q "No export job history found" "$log_file"; then echo "PASS"; else echo "FAIL: rc=$rc log=$(cat "$log_file")"; fail=1; fi

echo "=== Case 5: 401 -> authentication failed, exit 1 ==="
img_export_status_api() { printf '{"message":"invalid token"}\n401'; }
: > "$log_file"
( img_export_monitor "myimage" ) >/dev/null 2>&1
rc=$?
if [[ "$rc" == "1" ]] && grep -q "Authentication failed" "$log_file"; then echo "PASS"; else echo "FAIL: rc=$rc log=$(cat "$log_file")"; fail=1; fi

echo "=== Case 6: 403 -> not authorized, exit 1 ==="
img_export_status_api() { printf '{"message":"forbidden"}\n403'; }
: > "$log_file"
( img_export_monitor "myimage" ) >/dev/null 2>&1
rc=$?
if [[ "$rc" == "1" ]] && grep -q "Not authorized" "$log_file"; then echo "PASS"; else echo "FAIL: rc=$rc log=$(cat "$log_file")"; fail=1; fi

echo "=== Case 7: 500 -> service error, exit 1 ==="
img_export_status_api() { printf '{"message":"boom"}\n500'; }
: > "$log_file"
( img_export_monitor "myimage" ) >/dev/null 2>&1
rc=$?
if [[ "$rc" == "1" ]] && grep -q "PowerVS service error" "$log_file"; then echo "PASS"; else echo "FAIL: rc=$rc log=$(cat "$log_file")"; fail=1; fi

echo "=== Case 8: 400 -> invalid request, exit 1 ==="
img_export_status_api() { printf '{"message":"bad"}\n400'; }
: > "$log_file"
( img_export_monitor "myimage" ) >/dev/null 2>&1
rc=$?
if [[ "$rc" == "1" ]] && grep -q "Invalid request" "$log_file"; then echo "PASS"; else echo "FAIL: rc=$rc log=$(cat "$log_file")"; fail=1; fi

echo "=== Case 9: 502 (unclassified) -> generic failure message with status code, exit 1 ==="
img_export_status_api() { printf '{}\n502'; }
: > "$log_file"
( img_export_monitor "myimage" ) >/dev/null 2>&1
rc=$?
if [[ "$rc" == "1" ]] && grep -q "Failed to retrieve the last export job" "$log_file" && grep -q "502" "$log_file"; then echo "PASS"; else echo "FAIL: rc=$rc log=$(cat "$log_file")"; fail=1; fi

echo "=== Case 10: 2xx with status.state but NO Job ID -> exit 1, distinct message (never calls wait_for_job with an empty ID) ==="
img_export_status_api() { printf '{"status":{"state":"running"}}\n200'; }
wait_for_job() { echo "WAIT_FOR_JOB_CALLED: $1" > "$WORKDIR/wfj.log"; }
rm -f "$WORKDIR/wfj.log"
: > "$log_file"
( img_export_monitor "myimage" ) >/dev/null 2>&1
rc=$?
if [[ "$rc" == "1" ]] && grep -q "did not include a Job ID" "$log_file" && [[ ! -f "$WORKDIR/wfj.log" ]]; then echo "PASS"; else echo "FAIL: rc=$rc log=$(cat "$log_file") wfj=$(cat "$WORKDIR/wfj.log" 2>/dev/null)"; fail=1; fi

echo "=== Case 11: 2xx with Job ID but NO status.state -> Job ID alone is sufficient, wait_for_job called ==="
img_export_status_api() { printf '{"id":"job-noState"}\n200'; }
wait_for_job() { echo "WAIT_FOR_JOB_CALLED: $1" > "$WORKDIR/wfj.log"; }
rm -f "$WORKDIR/wfj.log"
( img_export_monitor "myimage" ) >/dev/null 2>&1
if [[ "$(cat "$WORKDIR/wfj.log" 2>/dev/null)" == "WAIT_FOR_JOB_CALLED: job-noState" ]]; then echo "PASS"; else echo "FAIL: $(cat "$WORKDIR/wfj.log" 2>/dev/null)"; fail=1; fi

echo "=== Case 12: 2xx with a non-JSON body -> exit 1, 'Invalid response' message, NOT treated as no-history ==="
img_export_status_api() { printf 'Service temporarily unavailable\n200'; }
: > "$log_file"
( img_export_monitor "myimage" ) >/dev/null 2>&1
rc=$?
if [[ "$rc" == "1" ]] && grep -q "Invalid response" "$log_file" && ! grep -q "No export job history found" "$log_file"; then echo "PASS"; else echo "FAIL: rc=$rc log=$(cat "$log_file")"; fail=1; fi

if [[ $fail -eq 0 ]]; then echo "ALL PASS"; else echo "SOME TESTS FAILED"; exit 1; fi
```

Run: `bash /tmp/test_img_export_monitor.sh`
Expected: 12 `PASS` lines then `ALL PASS`.

- [ ] **Step 7: Clean up the verification script**

Run: `rm -f /tmp/test_img_export_monitor.sh`

- [ ] **Step 8: Commit**

```bash
cd /home/rqmartins/Git/bluexport_api
git add bluexport_api.sh
git commit -m "$(cat <<'EOF'
Add -je: re-attach monitoring to an existing image export job

img_export_status_api() GETs the same URL img_export_api() POSTs to
(PowerVS's "get last image export job" endpoint - confirmed
image-scoped against the official API reference, unlike import's
workspace-scoped equivalent). img_export_monitor() resolves IMAGE_NAME
to an IMAGE_ID by searching every workspace (same pattern as
img_export()/do_img_delete()), dispatches on the same HTTP status
codes as -ji's img_import_monitor(), and hands off to wait_for_job().

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Documentation and version bump

**Files:**
- Modify: `bluexport_api.sh` — header comment block (around line 61-71, confirm with `grep -n 'Both -imgimport and -imgexport monitor' bluexport_api.sh`) and `help()` (around line 495-510, confirm with `grep -n 'Both -imgimport and -imgexport monitor the PowerVS' bluexport_api.sh`)
- Modify: `bluexport_api.sh:154` (`Version=`, confirm with `grep -n '^Version=' bluexport_api.sh`)
- Modify: `README.md`, `CHANGELOG.md`

**Interfaces:**
- Consumes: nothing (documentation/metadata only). Run this task last, after Tasks 1-2 are committed.

- [ ] **Step 1: Update the header comment block**

Find the line `#   target workspace - PowerVS only allows one at a time per workspace).` (end of the existing `-imgimport`/`-imgexport` header block) and insert immediately after it, before the blank `#` line that follows:

```bash
#
# Monitor an existing import/export job (re-attach without resubmitting):
#   bluexport_api.sh -ji WORKSPACE
#   bluexport_api.sh -je IMAGE_NAME
#
#   Looks up the last import/export job PowerVS has on record (via the API - no
#   local job-ID storage, works even from a different machine than the one that
#   submitted it) and monitors it to completion, exiting non-zero on failure.
```

- [ ] **Step 2: Update `help()`**

Find the existing `-imgimport`/`-imgexport` block's final lines in `help()` (`echoscreen "  Both -imgimport and -imgexport monitor the PowerVS job to completion and"` / `"  exit non-zero on failure, including if another import/export operation is"` / `"  already running in the target workspace."` / `echoscreen ""`) and insert immediately after that final blank `echoscreen ""`:

```bash
	echoscreen "Monitor an existing import/export job:"
	echoscreen "  bluexport_api.sh -ji WORKSPACE"
	echoscreen "  bluexport_api.sh -je IMAGE_NAME"
	echoscreen ""
	echoscreen "  Re-attaches monitoring to the last import/export job PowerVS has on"
	echoscreen "  record, without resubmitting anything - useful after a lost SSH"
	echoscreen "  session or a job submitted from a different machine. No job ID is"
	echoscreen "  stored locally; every call asks PowerVS directly."
	echoscreen ""
```

- [ ] **Step 3: Bump `Version=`**

Confirm current value first: `grep -n '^Version=' bluexport_api.sh`. Change to `Version=1.15.0`.

- [ ] **Step 4: Update `README.md`**

Read `README.md`'s existing "Export image to COS" section (search for it) and add a new "Monitor an existing import/export job" section right after it, documenting the `-ji WORKSPACE` / `-je IMAGE_NAME` syntax, that no job ID is stored locally (works cross-machine), and that both exit non-zero on failure just like `-imgimport`/`-imgexport`.

- [ ] **Step 5: Update `CHANGELOG.md`**

Read `CHANGELOG.md`'s most recent entries for formatting, then add a new entry:

```markdown
## [1.15.0] - 2026-08-06 (`bluexport_api.sh`)

### Added
- `-ji WORKSPACE`: re-attach monitoring to the last image import job PowerVS has on record for a workspace, without resubmitting - useful after a lost SSH session or when the import was submitted from a different machine. No job ID is stored locally; queries PowerVS's "get last cos-image import job" endpoint directly.
- `-je IMAGE_NAME`: same, for the last image export job for a given image (searches every workspace by name, same as `-imgexport`/`-imgdel`).
- Both distinguish `400`/`401`/`403`/`404`/`500`/other HTTP responses from PowerVS with a specific message each, rather than reporting every failure as "no job history found."
```

- [ ] **Step 6: Syntax check**

Run: `bash -n bluexport_api.sh`
Expected: no output.

- [ ] **Step 7: Commit**

```bash
cd /home/rqmartins/Git/bluexport_api
git add bluexport_api.sh README.md CHANGELOG.md
git commit -m "$(cat <<'EOF'
Version bump + docs for -ji/-je

bluexport_api.sh -> 1.15.0 (MINOR: purely additive, no existing
behavior changes).

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Real-world verification (required before calling this done)

Not a code task — acceptance checklist against the user's real IBM Cloud account. Sandbox tests above prove logic only, against mocked `img_import_status_api()`/`img_export_status_api()`, not the real PowerVS API. Do not report this feature as done without running this.

- [ ] **Step 1: `-ji` against a real, currently-running or recently-completed import**

Start a real `-imgimport` in one terminal (or use a recent one), then in a separate terminal/session run `-ji WORKSPACE` and confirm it finds the same job, shows the same status progression, and reaches the same completion/failure outcome.

- [ ] **Step 2: `-je` against a real, currently-running or recently-completed export**

Same as Step 1, for `-imgexport` / `-je IMAGE_NAME`.

- [ ] **Step 3: `-ji`/`-je` against a workspace/image with NO job history**

Confirm the actual HTTP status PowerVS returns for a workspace that has never run an import, and for an image that has never been exported (404? 200 with an empty body? something else?) — report back whatever it actually is, and adjust the "no job history" detection in Task 1/2 if it doesn't match either of the two cases already handled.

- [ ] **Step 4: Confirm the HTTP status dispatch table for at least one non-404 error case**

E.g., let the IAM token expire and confirm a genuine `401` produces "Authentication failed while retrieving the last import/export job," not the generic "no job history" message.

- [ ] **Step 5: Exit codes**

Run `-ji`/`-je` against something invalid and confirm `echo $?` is `1`, then against a real successful case and confirm `echo $?` is `0`.

- [ ] **Step 6: Real verification on IBM i PASE**

Repeat at least Steps 1 and 5 on the real IBM i PASE environment, per standing project guidance.

- [ ] **Step 7: Report results to the user**

Summarize what was confirmed, any deviations from the assumed schema/status codes, and get explicit sign-off.

---

## Self-Review Notes

- **Spec coverage:** Section A (status API functions) → Tasks 1/2 Step 2. Section B (orchestration functions) → Tasks 1/2 Step 3. Section C (HTTP status dispatch table, including the precise "200 empty/job-less" condition) → Tasks 1/2 Step 3's `case` statement. Section D (flags, no optional IMAGE_NAME on `-ji`, no WORKSPACE on `-je`) → Tasks 1/2 Step 4. Section E (`wait_for_job()` reuse, unmodified) → confirmed, no task touches it. Section F (documentation) → Task 3. Section G (versioning) → Task 3 Step 3. Non-goals: no local job-ID persistence (confirmed absent from all tasks), `job_monitor()`/`-j` untouched (confirmed), `-imgimport`/`-imgexport` themselves untouched (confirmed — only new functions/dispatch added). All spec sections have a task.
- **Placeholder scan:** no TBD/TODO; every step has literal code or an exact command.
- **Type/name consistency:** `img_import_monitor WORKSPACE` / `img_export_monitor IMAGE_NAME` signatures match their case-dispatch call sites exactly. `wait_for_job JOB_ID LABEL` called identically to how Tasks 3/4 of the prior `-imgexport` plan already call it. `status_http_code`/`status_resp`/`job_id`/`job_state` variable names consistent between both monitor functions' near-identical dispatch blocks (deliberate mirroring, not a shared abstraction — same YAGNI rationale the prior plan's final review explicitly endorsed for `img_import()`/`img_export()`).
- **Line numbers:** every task's Step 1 re-confirms current line numbers with `grep` before editing, since `bluexport_api.sh` shifts with each prior task in this plan.
- **Post-approval corrections (user technical review, 2026-08-06):** two logical bugs found in the first draft, now fixed in both Tasks 1 and 2: (1) the original `2*)` branch treated `.status.state` alone as sufficient to proceed, so a response with a state but no `.id` would call `wait_for_job ""` — an empty Job ID that can never resolve to anything. Fixed by requiring `.id` specifically; a state-without-id response now gets its own distinct "did not include a Job ID" message instead of either silently proceeding or being misreported as "no history." (2) A non-JSON 2xx body (e.g. a plain-text service error) was silently swallowed by the jq extraction (both fields would come back empty via `2>/dev/null`) and misreported as "no job history found," which is false — the job history might well exist. Fixed with an explicit `jq -e .` validity check before extraction, routing to a distinct "Invalid response received" message. Three new test cases added to both Task 1 and Task 2's test scripts to cover exactly these cases (state-without-id, id-without-state, non-JSON body).
