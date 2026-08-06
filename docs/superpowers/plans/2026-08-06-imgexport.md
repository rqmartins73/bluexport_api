# `-imgexport` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `-imgexport` (export a boot image from a workspace's image catalog to a COS bucket) to `bluexport_api.sh`, mirroring `-imgimport`'s design including `CURRACCOUNT`/`OTHERACCOUNT` support, while fixing a real pre-existing bug (`load_hmac_keys` called but never defined, so `-imgimport ... OTHERACCOUNT` has never worked) and adding job monitoring, 409/"already running" detection, and differentiated exit codes to both `-imgimport` and the new `-imgexport`.

**Architecture:** A new `load_hmac_keys()` fixes the OTHERACCOUNT credential path for both flags. A new, separate `wait_for_job()` (copies `job_monitor()`'s proven polling skeleton, but generic — `job_monitor()` itself is untouched) backs both flags' job monitoring. `abort()` gains a backward-compatible optional exit-code argument so genuine failures in this feature's code exit non-zero. `img_export()` mirrors `img_import()`'s structure closely, resolving an image name to an ID the same way `do_img_delete()` already does (search every workspace, first match wins).

**Tech Stack:** Bash (IBM i PASE-compatible), `jq`, `curl`. No new external dependencies.

## Global Constraints

- Must remain IBM i PASE/QShell-compatible — no Linux-only constructs, no GNU-only flags not already used elsewhere in this file.
- `abort()`'s existing call sites (no second argument) must be byte-for-byte unaffected by its new optional exit-code parameter — it must still default to `0`.
- The bucket/object COS pre-check for `-imgexport` must always use `--aws-sigv4` with the exact `$cos_accesskey`/`$cos_secretkey` resolved once per invocation (never a bearer-token branch, for either `CURRACCOUNT` or `OTHERACCOUNT`) — those are the same credentials sent to PowerVS in the export payload, and the pre-check must prove exactly those credentials work.
- 409/"already running" detection: HTTP status `409` **or** a case-insensitive match on `already running|in progress|conflict` in the error text — never rely on the status code alone, since the exact code IBM returns for this case is not confirmed in official docs.
- Error detection must never rely on `curl`'s exit code or on `.code`/`.error`/`.errors` JSON fields alone — `curl` exits `0` on HTTP 4xx/5xx unless `--fail` is used (not used here, since the body is needed either way), and a plausible error body like `{"message":"conflict"}` has none of those fields. Any non-2xx HTTP status (checked via the captured `-w '%{http_code}'`) must independently route into the error-handling branch, in both `img_import()` and `img_export()`.
- Exit code `1` on every genuine failure inside code this plan adds or touches (`load_hmac_keys()`, `wait_for_job()`, `img_export()`, the modified tail/error-handling of `img_import()`). Not extended to any other pre-existing flag or function.
- `job_monitor()` (capture/export-VSI flow) is not touched or refactored.
- Version bump: MINOR (`1.13.0` → `1.14.0`) — additive + bug fix + non-breaking behavior changes, no existing call syntax changes.
- Spec: `docs/superpowers/specs/2026-08-06-imgexport-design.md` (approved, read before starting if you need full rationale — especially the D.3/D.4 correction about aws-sigv4-only auth for the bucket pre-check).

---

## File Structure

- Modify `bluexport_api.sh` only:
  - `abort()` (line 217) — optional exit-code argument.
  - New `load_hmac_keys()` — placed immediately before `img_import()` (currently line 4327).
  - New `wait_for_job()` — placed immediately after `job_monitor()` (currently ends line 1269).
  - `img_import_api()` (line 797) — add HTTP status capture.
  - `img_import()`'s error-handling and tail (currently lines ~4488-4509) — 409 detection, exit codes, `wait_for_job` wiring.
  - New `img_export_api()` — placed next to `img_import_api()`.
  - New `img_export()` — placed next to `img_import()`.
  - New `-imgexport` case dispatch — placed next to the existing `-imgimport` case (currently line 5289).
  - Header comment block and `help()` — new `-imgexport` documentation.
  - `Version=` (line 143) — bump to `1.14.0`.
- New file `hmac_keys_example.json` at repo root.
- Modify `README.md`, `CHANGELOG.md`.

---

### Task 1: `abort()` exit code + `load_hmac_keys()` (fixes `-imgimport` OTHERACCOUNT bug)

**Files:**
- Modify: `bluexport_api.sh:217-225` (function `abort`)
- Modify: `bluexport_api.sh` — new function `load_hmac_keys()`, placed immediately before `img_import()` (confirm current line with `grep -n '^img_import()' bluexport_api.sh` first)

**Interfaces:**
- Produces: `abort MESSAGE [EXIT_CODE]` (exit code defaults to `0`, fully backward compatible). `load_hmac_keys HMAC_JSON_FILE` sets globals `hmac_access_key`/`hmac_secret_key`, or aborts (exit `1`) on any parse/missing-field failure. Both are consumed by every later task in this plan.

- [ ] **Step 1: Confirm current exact text**

Run: `grep -n '^abort()\|^img_import()' bluexport_api.sh`

Read `bluexport_api.sh` around the `abort()` line to confirm it still reads exactly as below before editing.

- [ ] **Step 2: Replace `abort()`**

Replace:
```bash
abort() {
        echo $1 >> $log_file
        if [ -t 1 ]
        then
                echo ""
                echo "   ### $1"
                echo ""
        fi
        timestamp=$(date +%F" "%T" "%Z)
        eval echo $end_log_file >> $log_file
        exit 0
}
```

With:
```bash
abort() {
        echo "$1" >> "$log_file"
        if [ -t 1 ]
        then
                echo ""
                echo "   ### $1"
                echo ""
        fi
        timestamp=$(date +%F" "%T" "%Z)
        eval echo $end_log_file >> $log_file
        exit "${2:-0}"
}
```

(Only two changes: `"$1" >> "$log_file"` now quoted, and `exit "${2:-0}"` instead of `exit 0`. The `eval echo $end_log_file >> $log_file` line is deliberately unchanged — do not touch it.)

- [ ] **Step 3: Add `load_hmac_keys()` immediately before `img_import()`**

Insert (confirm the exact line `img_import() {` first with `grep -n '^img_import()' bluexport_api.sh`, then insert directly above its `#### START:FUNCTION` comment marker):

```bash
####  START:FUNCTION - Load HMAC keys from a COS Service Credentials JSON file (OTHERACCOUNT)  ####
# load_hmac_keys HMAC_JSON_FILE
#   Reads .cos_hmac_keys.access_key_id / .cos_hmac_keys.secret_access_key from the given
#   JSON file (exact format IBM Cloud COS "Service credentials" gives you) and sets the
#   globals hmac_access_key / hmac_secret_key. Aborts (exit 1) on any parse failure or
#   missing field, instead of leaving the caller with silently empty keys.
load_hmac_keys() {
	local hmac_file="$1"
	hmac_access_key=""
	hmac_secret_key=""
	if ! jq -e . "$hmac_file" >/dev/null 2>&1
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - HMAC keys JSON file $hmac_file is not valid JSON. Aborting..." 1
	fi
	hmac_access_key=$(jq -r '.cos_hmac_keys.access_key_id // empty' "$hmac_file")
	hmac_secret_key=$(jq -r '.cos_hmac_keys.secret_access_key // empty' "$hmac_file")
	if [[ -z "$hmac_access_key" || -z "$hmac_secret_key" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - HMAC keys JSON file $hmac_file is missing .cos_hmac_keys.access_key_id or .cos_hmac_keys.secret_access_key. Aborting..." 1
	fi
}
####  END:FUNCTION - Load HMAC keys from a COS Service Credentials JSON file (OTHERACCOUNT)  ####

```

- [ ] **Step 4: Syntax check**

Run: `bash -n bluexport_api.sh`
Expected: no output.

- [ ] **Step 5: Write and run a standalone test for both functions**

Create `/tmp/test_abort_hmac.sh`:

```bash
#!/bin/bash
set -uo pipefail
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

REPO=/home/rqmartins/Git/bluexport_api
log_file="$WORKDIR/test.log"
end_log_file=""
: > "$log_file"

source <(sed -n '/^abort() {/,/^}/p' "$REPO/bluexport_api.sh")
source <(sed -n '/^load_hmac_keys() {/,/^}/p' "$REPO/bluexport_api.sh")

fail=0

echo "=== Case 1: abort with no exit-code arg -> exit 0 (backward compat) ==="
( abort "test message" )
rc=$?
if [[ "$rc" == "0" ]]; then echo "PASS: rc=0"; else echo "FAIL: rc=$rc"; fail=1; fi

echo "=== Case 2: abort with explicit 1 -> exit 1 ==="
( abort "test failure" 1 )
rc=$?
if [[ "$rc" == "1" ]]; then echo "PASS: rc=1"; else echo "FAIL: rc=$rc"; fail=1; fi

echo "=== Case 3: load_hmac_keys with valid JSON ==="
cat > "$WORKDIR/valid.json" <<'EOF'
{"cos_hmac_keys":{"access_key_id":"AKID123","secret_access_key":"SECRET456"}}
EOF
(
	source <(sed -n '/^abort() {/,/^}/p' "$REPO/bluexport_api.sh")
	source <(sed -n '/^load_hmac_keys() {/,/^}/p' "$REPO/bluexport_api.sh")
	log_file="$WORKDIR/test.log"
	load_hmac_keys "$WORKDIR/valid.json"
	if [[ "$hmac_access_key" == "AKID123" && "$hmac_secret_key" == "SECRET456" ]]; then
		echo "PASS: keys extracted correctly"
	else
		echo "FAIL: got access=$hmac_access_key secret=$hmac_secret_key"
		exit 1
	fi
)
[[ $? -eq 0 ]] || fail=1

echo "=== Case 4: load_hmac_keys with invalid JSON -> exit 1 ==="
echo "not json" > "$WORKDIR/invalid.json"
(
	source <(sed -n '/^abort() {/,/^}/p' "$REPO/bluexport_api.sh")
	source <(sed -n '/^load_hmac_keys() {/,/^}/p' "$REPO/bluexport_api.sh")
	log_file="$WORKDIR/test.log"
	load_hmac_keys "$WORKDIR/invalid.json"
)
rc=$?
if [[ "$rc" == "1" ]]; then echo "PASS: rc=1 for invalid JSON"; else echo "FAIL: rc=$rc"; fail=1; fi

echo "=== Case 5: load_hmac_keys with missing field -> exit 1 ==="
cat > "$WORKDIR/missing.json" <<'EOF'
{"cos_hmac_keys":{"access_key_id":"AKID123"}}
EOF
(
	source <(sed -n '/^abort() {/,/^}/p' "$REPO/bluexport_api.sh")
	source <(sed -n '/^load_hmac_keys() {/,/^}/p' "$REPO/bluexport_api.sh")
	log_file="$WORKDIR/test.log"
	load_hmac_keys "$WORKDIR/missing.json"
)
rc=$?
if [[ "$rc" == "1" ]]; then echo "PASS: rc=1 for missing secret_access_key"; else echo "FAIL: rc=$rc"; fail=1; fi

if [[ $fail -eq 0 ]]; then echo "ALL PASS"; else echo "SOME TESTS FAILED"; exit 1; fi
```

Run: `bash /tmp/test_abort_hmac.sh`
Expected: 5 `PASS:` lines then `ALL PASS`.

- [ ] **Step 6: Clean up the verification script**

Run: `rm -f /tmp/test_abort_hmac.sh`

- [ ] **Step 7: Commit**

```bash
cd /home/rqmartins/Git/bluexport_api
git add bluexport_api.sh
git commit -m "$(cat <<'EOF'
abort(): add optional exit-code arg; add load_hmac_keys() (fixes -imgimport OTHERACCOUNT)

abort() defaults to exit 0 exactly as before when called with one
argument; a second argument sets the exit code, for genuine failures
in code this task's follow-ups touch.

load_hmac_keys() was called by img_import()'s OTHERACCOUNT path but
never defined anywhere in the script - that path has therefore never
worked, always failing with "Missing COS HMAC accessKey/secretKey".
Now implemented: parses .cos_hmac_keys.access_key_id/.secret_access_key
from the HMAC JSON file (the exact format IBM Cloud COS Service
Credentials produces), sets hmac_access_key/hmac_secret_key.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: `wait_for_job()` — generic job poller

**Files:**
- Modify: `bluexport_api.sh` — new function, placed immediately after `job_monitor()` (currently ends at line 1269, confirm with `grep -n '^job_monitor() {' bluexport_api.sh` and read to its closing `}` first)

**Interfaces:**
- Consumes: `job_get()` (existing, unchanged), globals `$job_log`/`$job_monitor`/`$log_file`/`$iam_token_epoch`, `get_iam_token()`, `spin_wait()`, `abort()` (from Task 1, with its new optional exit-code arg).
- Produces: `wait_for_job JOB_ID LABEL` — polls until the job completes (exits 0) or fails/exhausts retries (exits 1). Consumed by Task 3 and Task 4.

- [ ] **Step 1: Confirm insertion point**

Run: `grep -n '^job_monitor() {' bluexport_api.sh` then read from there to the function's closing `}` (currently line 1269) and the `#### END:FUNCTION - Monitor Capture and Export Job  ####` marker right after it, to confirm the exact insertion point.

- [ ] **Step 2: Insert `wait_for_job()` right after `job_monitor()`'s closing marker**

Insert immediately after the `####  END:FUNCTION - Monitor Capture and Export Job  ####` line:

```bash

####  START:FUNCTION - Generic Job Wait (image import/export, and future non-capture jobs) ####
# wait_for_job JOB_ID LABEL
#   JOB_ID: PowerVS job ID to poll (GET /pcloud/v1/.../jobs/$JOB_ID - same unified jobs
#           queue used by captures, image import, and image export).
#   LABEL:  short description used in progress/completion/failure messages,
#           e.g. "Image import of myimage" or "Image export of myimage to bucket mybucket".
# Same polling/retry logic as job_monitor() (proven in production for captures), but
# without anything capture-specific (no capture_name/vsi/destination, no delete_previous_img,
# no operid_file reuse, no per-capture permanent log file) - job_monitor() itself is left
# untouched. Exits 0 on success, 1 on failure (job failed, or transient-failure retries
# exhausted) - unlike abort()'s historical default, callers can check $? after this.
wait_for_job() {
	local job_id="$1"
	local label="$2"
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Job log in file $job_log" "1"
	echo "Job Monitoring of $label - Job ID: $job_id" >> "$job_log"

	# The job may take a few seconds to actually register after being submitted;
	# a poll that lands too early can see "not found" and burn a retry attempt
	# for no reason. Give it a moment before the first check.
	spin_wait 10 "Waiting for job to register"

	local operation_before="" job_get_fail_count=0 job_get_max_fail=10 token_refresh_secs=2700

	while true
	do
		JOB_ID="$job_id"

		if [[ -n "$iam_token_epoch" ]] && (( $(date +%s) - iam_token_epoch >= token_refresh_secs ))
		then
			get_iam_token refresh
		fi

		local job_raw http_code job_json job_status
		job_raw=$(job_get)
		http_code="${job_raw##*$'\n'}"
		job_json="${job_raw%$'\n'*}"
		job_status=$(printf '%s' "$job_json" | jq -r '.status.state // empty' 2>/dev/null)

		if [[ -z "$job_status" ]]
		then
			job_get_fail_count=$((job_get_fail_count + 1))
			echo "$(date +%Y-%m-%d_%H:%M:%S) - WARNING - Could not read Job $job_id status (HTTP ${http_code:-?}, attempt $job_get_fail_count/$job_get_max_fail). Response: $job_json" >> "$job_log"
			if [[ "$http_code" == "401" ]]
			then
				echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - IAM token was rejected (HTTP 401). Refreshing token..." "1"
				get_iam_token refresh
			fi
			if [[ "$job_get_fail_count" -ge "$job_get_max_fail" ]]
			then
				echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - FAILED Getting Job ID or no Job Running after $job_get_max_fail consecutive attempts!" "1"
				abort "$(date +%Y-%m-%d_%H:%M:%S) - Check file $job_monitor and $job_log for more details." 1
			fi
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - WARNING - Transient error reading Job $job_id status (HTTP ${http_code:-?}). Retrying in 30s ($job_get_fail_count/$job_get_max_fail)..." "1"
			spin_wait 30 "Retrying job status check"
			continue
		fi
		job_get_fail_count=0

		printf '%s\n' "$job_json" | tee "$job_monitor" >>"$job_log"
		local message operation
		message=$(jq -r '.status.message // empty'    "$job_monitor")
		operation=$(jq -r '.status.progress // empty' "$job_monitor")

		if [[ "$job_status" == "completed" ]]
		then
			echo "$(date +%Y-%m-%d_%H:%M:%S) - Finished Successfully!!" >> "$job_log"
			abort "$(date +%Y-%m-%d_%H:%M:%S) - $label completed successfully!!"
		elif [[ "$job_status" == "failed" ]]
		then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Job ID $job_id Status: ${job_status^^}" "1"
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Message: $message" "1"
			abort "$(date +%Y-%m-%d_%H:%M:%S) - $label failed, check message!!" 1
		elif [[ "$job_status" == "queued" ]]
		then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Job ID $job_id Status: ${job_status^^}" "1"
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Message: $message" "1"
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Waiting for Operation Change... Operation Running Now: ${operation^^}" "1"
			echo "$(date +%Y-%m-%d_%H:%M:%S) - Running ${operation^^}... Sleeping 60 seconds..." >> "$job_log"
			spin_wait 60 "Running ${operation^^}"
			operation_before="$operation"
		else
			if [[ "$operation" != "$operation_before" ]]
			then
				echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Job ID $job_id Status: ${job_status^^}" "1"
				echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Message: $message" "1"
				echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Waiting for Operation Change... Operation Running Now: ${operation^^}" "1"
				echo "$(date +%Y-%m-%d_%H:%M:%S) - Running ${operation^^}... Sleeping 60 seconds..." >> "$job_log"
				spin_wait 60 "Running ${operation^^}"
				operation_before="$operation"
			else
				echo "$(date +%Y-%m-%d_%H:%M:%S) - Still Running ${operation^^}... Sleeping 60 seconds..." >> "$job_log"
				spin_wait 60 "Still running ${operation^^}"
			fi
		fi
	done
}
####  END:FUNCTION - Generic Job Wait ####
```

- [ ] **Step 3: Syntax check**

Run: `bash -n bluexport_api.sh`
Expected: no output.

- [ ] **Step 4: Write and run a mocked functional test**

Create `/tmp/test_wait_for_job.sh`:

```bash
#!/bin/bash
set -uo pipefail
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

REPO=/home/rqmartins/Git/bluexport_api

source <(sed -n '/^abort() {/,/^}/p' "$REPO/bluexport_api.sh")
source <(sed -n '/^wait_for_job() {/,/^}/p' "$REPO/bluexport_api.sh")

echoscreen() { echo "LOG: $1"; }
spin_wait() { echo "SPIN_WAIT_CALLED: $1 $2" >> "$WORKDIR/spinwait.log"; }
get_iam_token() { :; }

log_file="$WORKDIR/test.log"
job_log="$WORKDIR/job.log"
job_monitor="$WORKDIR/job_monitor.tmp"
iam_token_epoch=""
end_log_file=""
: > "$log_file"
: > "$job_log"

fail=0

echo "=== Case 1: job completes -> exit 0 ==="
: > "$WORKDIR/spinwait.log"
call_count_file="$WORKDIR/calls1"
echo 0 > "$call_count_file"
job_get() {
	local n
	n=$(cat "$call_count_file")
	n=$((n + 1))
	echo "$n" > "$call_count_file"
	if [[ "$n" -eq 1 ]]; then
		printf '{"status":{"state":"running","progress":"IMAGEEXPORT","message":"in progress"}}\n200'
	else
		printf '{"status":{"state":"completed","progress":"IMAGEEXPORT","message":"done"}}\n200'
	fi
}
( wait_for_job "job-abc" "Test completion" )
rc=$?
if [[ "$rc" == "0" ]]; then echo "PASS: completed -> exit 0"; else echo "FAIL: exit $rc"; fail=1; fi
if grep -q "Waiting for job to register" "$WORKDIR/spinwait.log"; then
	echo "PASS: pre-poll spin_wait called"
else
	echo "FAIL: pre-poll spin_wait not called"; fail=1
fi

echo "=== Case 2: job fails -> exit 1 ==="
job_get() {
	printf '{"status":{"state":"failed","message":"something broke"}}\n200'
}
( wait_for_job "job-xyz" "Test failure" )
rc=$?
if [[ "$rc" == "1" ]]; then echo "PASS: failed -> exit 1"; else echo "FAIL: exit $rc"; fail=1; fi

if [[ $fail -eq 0 ]]; then echo "ALL PASS"; else echo "SOME TESTS FAILED"; exit 1; fi
```

Run: `bash /tmp/test_wait_for_job.sh`
Expected: 3 `PASS:` lines then `ALL PASS`. This should run in a few seconds (spin_wait is stubbed to a no-op that only logs, so the real 10s/60s waits are skipped).

- [ ] **Step 5: Clean up the verification script**

Run: `rm -f /tmp/test_wait_for_job.sh`

- [ ] **Step 6: Commit**

```bash
cd /home/rqmartins/Git/bluexport_api
git add bluexport_api.sh
git commit -m "$(cat <<'EOF'
Add wait_for_job(): generic PowerVS job poller for non-capture flags

job_monitor() is tightly coupled to the capture/export-VSI flow and
isn't safely reusable for image import/export. wait_for_job() copies
its proven polling/retry skeleton (same job_get(), same transient-
failure backoff, same IAM token refresh) without any capture-specific
behavior, and exits 0/1 based on job outcome so callers can check $?.
job_monitor() itself is untouched.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Update `-imgimport` — 409 detection, exit codes, `wait_for_job` wiring

**Files:**
- Modify: `bluexport_api.sh:797-799` (function `img_import_api`)
- Modify: `bluexport_api.sh` — `img_import()`'s validation, error-handling, and tail (confirm current line numbers with `grep -n '^img_import() {' bluexport_api.sh` first — this task touches most of the function's `abort` calls, not just the tail)

**Interfaces:**
- Consumes: `load_hmac_keys()`, `abort MESSAGE [EXIT_CODE]` (Task 1), `wait_for_job()` (Task 2).
- Produces: `-imgimport`'s OTHERACCOUNT path now works (Task 1 already fixes this at the `load_hmac_keys` call site — no change needed here beyond what Task 1 did). `-imgimport` now monitors its job to completion and exits 1 on any genuine failure. This task's error-handling pattern (409 detection, HTTP status capture) is what Task 4 mirrors for `-imgexport`.

- [ ] **Step 1: Confirm current exact text**

Run: `grep -n '^img_import() {\|^img_import_api() {' bluexport_api.sh`

Read the full `img_import()` function body (from its `#### START:FUNCTION` marker to `#### END:FUNCTION`) to confirm it still matches what's quoted below before editing — this function has many `abort` calls throughout (argument validation, region/storage-type/account-type validation, workspace resolution, duplicate-image check, credential resolution, bucket/object HEAD check) and this task adds `1` as the second argument to every one of them, not just the ones near the API call.

- [ ] **Step 2: Add HTTP status capture to `img_import_api()`**

Replace:
```bash
img_import_api() {
	curl -sX POST $base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/cos-images -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -d "{$ACTIONS}"
}
```

With:
```bash
img_import_api() {
	curl -sX POST $base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/cos-images -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -d "{$ACTIONS}" -w '\n%{http_code}'
}
```

- [ ] **Step 3: Add `1` as the exit code to every `abort` call inside `img_import()` that represents a genuine failure**

There are many such calls throughout the function — argument count/emptiness check, invalid `BUCKET_REGION` format, invalid `storage_type`, invalid `account_type`, the three HMAC-argument-combination checks, workspace-not-found, workspace-missing-CRN-or-ID, base-URL-not-resolved, image-already-exists-in-catalog, missing-COS-credentials (both branches), and all five branches of the bucket/object HEAD-check `case` statement (`301|302|307|308`, `403`, `404`, `*` — **not** the `200|204` success branch, which isn't an `abort`).

For each, append a literal ` 1` as a second argument to the `abort "..."` call, e.g.:

```bash
abort "`date +%Y-%m-%d_%H:%M:%S` - Too many or too few arguments!! Syntax: bluexport_api.sh -imgimport IMGNAME BUCKET BUCKET_REGION WORKSPACE_TO_IMPORT IMGNAME_WS STORAGE_TYPE CURRACCOUNT|OTHERACCOUNT [HMACKEYS-JSON-FILE-PATH-NAME]" 1
```

Do this for every genuine-failure `abort` call in the function body — do not skip any, and do not add `1` to anything that isn't inside `img_import()` (in particular, do not touch `do_img_delete()` or any other function above/below it).

- [ ] **Step 4: Replace the error-handling and tail block**

Replace (the block right after the `ACTIONS=$(jq -n ...)` assignment, through the end of the function):
```bash
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Calling PowerVS COS Image Import API for object $img_name as image $img_name_ws into Workspace $full_ws_name..." "1"
	local import_resp import_rc import_job_id import_error
	import_resp=$(img_import_api 2>>"$log_file")
	import_rc=$?
	echo "$import_resp" >> "$log_file"
	if [ $import_rc -ne 0 ] || echo "$import_resp" | jq -e '.code? != null or .error? != null or .errors? != null' >/dev/null 2>&1
	then
		import_error=$(echo "$import_resp" | jq -r '.message // .error // (.errors[0].message?) // .description // "Unknown error"' 2>/dev/null)
		if echo "$import_error $import_resp" | grep -Eiq 'hmac|access.?key|secret.?key|signature|credential|forbidden|not authorized|access denied'
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - PowerVS image import rejected the COS credentials/HMAC keys: $import_error"
		fi
		abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Error calling PowerVS image import API for $img_name_ws from COS object $img_name: $import_error"
	fi

	import_job_id=$(echo "$import_resp" | jq -r '.jobID // .id // .job.id // .jobReference.id // empty' 2>>"$log_file" | head -n1)
	if [[ -n "$import_job_id" ]]
	then
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Image import submitted successfully. Job ID: $import_job_id" "1"
	else
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Image import submitted successfully. Response saved in $log_file" "1"
	fi
	abort "`date +%Y-%m-%d_%H:%M:%S` - === Image import request for COS object $img_name as image $img_name_ws submitted successfully to Workspace $full_ws_name. ==="
```

With:
```bash
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Calling PowerVS COS Image Import API for object $img_name as image $img_name_ws into Workspace $full_ws_name..." "1"
	local import_raw import_http_code import_resp import_rc import_job_id import_error
	import_raw=$(img_import_api 2>>"$log_file")
	import_rc=$?
	import_http_code="${import_raw##*$'\n'}"
	import_resp="${import_raw%$'\n'*}"
	echo "$import_resp" >> "$log_file"
	if [ "$import_rc" -ne 0 ] || [[ ! "$import_http_code" =~ ^2[0-9][0-9]$ ]] || echo "$import_resp" | jq -e '.code? != null or .error? != null or .errors? != null' >/dev/null 2>&1
	then
		import_error=$(echo "$import_resp" | jq -r '.message // .error // (.errors[0].message?) // .description // "Unknown error"' 2>/dev/null)
		if [[ "$import_http_code" == "409" ]] || echo "$import_error $import_resp" | grep -Eiq 'already running|in progress|conflict'
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Another import/export operation is already running in this workspace. Wait for it to complete before starting a new one." 1
		fi
		if echo "$import_error $import_resp" | grep -Eiq 'hmac|access.?key|secret.?key|signature|credential|forbidden|not authorized|access denied'
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - PowerVS image import rejected the COS credentials/HMAC keys: $import_error" 1
		fi
		abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Error calling PowerVS image import API for $img_name_ws from COS object $img_name: $import_error" 1
	fi

	import_job_id=$(echo "$import_resp" | jq -r '.jobID // .id // .job.id // .jobReference.id // empty' 2>>"$log_file" | head -n1)
	if [[ -n "$import_job_id" ]]
	then
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Image import submitted successfully. Job ID: $import_job_id" "1"
		wait_for_job "$import_job_id" "Image import of $img_name_ws"
	else
		abort "`date +%Y-%m-%d_%H:%M:%S` - Image import submitted, but no Job ID was returned by the API. Response saved in $log_file. Check the Boot images page or -imglsall to confirm it completed." 1
	fi
```

- [ ] **Step 5: Syntax check**

Run: `bash -n bluexport_api.sh`
Expected: no output.

- [ ] **Step 6: Write and run a mocked functional test for the error-handling/dispatch logic**

This isolates `img_import()`'s new error-handling branch logic (409 detection, credential-error detection, generic-error fallback, job-ID dispatch) without needing the full function's argument-parsing/workspace-resolution machinery — those parts are unchanged from before and already implicitly covered by the fact that `img_import()` still parses (Step 5's syntax check) and by Task 1's tests already covering `abort`'s exit-code behavior.

Create `/tmp/test_imgimport_dispatch.sh`:

```bash
#!/bin/bash
set -uo pipefail
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

REPO=/home/rqmartins/Git/bluexport_api
source <(sed -n '/^abort() {/,/^}/p' "$REPO/bluexport_api.sh")

log_file="$WORKDIR/test.log"
end_log_file=""
: > "$log_file"
echoscreen() { echo "LOG: $1"; }

# Replicates the exact dispatch block from img_import() (Step 4), parameterized
# over a canned import_raw response, to test it in isolation.
run_dispatch() {
	local import_raw="$1"
	local wait_for_job_called_file="$WORKDIR/wfj_called"
	rm -f "$wait_for_job_called_file"
	wait_for_job() { echo "$1" > "$wait_for_job_called_file"; }

	local import_rc=0
	local import_http_code="${import_raw##*$'\n'}"
	local import_resp="${import_raw%$'\n'*}"
	echo "$import_resp" >> "$log_file"
	if [ "$import_rc" -ne 0 ] || [[ ! "$import_http_code" =~ ^2[0-9][0-9]$ ]] || echo "$import_resp" | jq -e '.code? != null or .error? != null or .errors? != null' >/dev/null 2>&1
	then
		local import_error
		import_error=$(echo "$import_resp" | jq -r '.message // .error // (.errors[0].message?) // .description // "Unknown error"' 2>/dev/null)
		if [[ "$import_http_code" == "409" ]] || echo "$import_error $import_resp" | grep -Eiq 'already running|in progress|conflict'
		then
			abort "FAILED - Another import/export operation is already running in this workspace. Wait for it to complete before starting a new one." 1
		fi
		if echo "$import_error $import_resp" | grep -Eiq 'hmac|access.?key|secret.?key|signature|credential|forbidden|not authorized|access denied'
		then
			abort "FAILED - PowerVS image import rejected the COS credentials/HMAC keys: $import_error" 1
		fi
		abort "FAILED - Error calling PowerVS image import API: $import_error" 1
	fi

	local import_job_id
	import_job_id=$(echo "$import_resp" | jq -r '.jobID // .id // .job.id // .jobReference.id // empty' 2>>"$log_file" | head -n1)
	if [[ -n "$import_job_id" ]]
	then
		wait_for_job "$import_job_id" "Image import test"
	else
		abort "Image import submitted, but no Job ID was returned." 1
	fi
}

fail=0

# abort() only echoes to stdout when stdout is a terminal ([ -t 1 ]); inside
# command substitution stdout is never a terminal, so the message only ever
# reaches $log_file. Assertions below check the log, not captured stdout -
# checking stdout here would let a broken abort() call still report PASS.

echo "=== Case 1: 409 status -> abort 1, specific message ==="
: > "$log_file"
( run_dispatch $'{"message":"conflict"}\n409' ) >/dev/null 2>&1
rc=$?
if [[ "$rc" == "1" ]] && grep -q "already running" "$log_file"; then echo "PASS"; else echo "FAIL: rc=$rc log=$(cat "$log_file")"; fail=1; fi

echo "=== Case 2: non-2xx status with 'already running' text but not literally 409 -> same message ==="
: > "$log_file"
( run_dispatch $'{"message":"another export is already running"}\n400' ) >/dev/null 2>&1
rc=$?
if [[ "$rc" == "1" ]] && grep -q "already running" "$log_file"; then echo "PASS"; else echo "FAIL: rc=$rc log=$(cat "$log_file")"; fail=1; fi

echo "=== Case 3: credential error -> credential message, exit 1 ==="
: > "$log_file"
( run_dispatch $'{"message":"invalid access key"}\n403' ) >/dev/null 2>&1
rc=$?
if [[ "$rc" == "1" ]] && grep -q "HMAC keys" "$log_file"; then echo "PASS"; else echo "FAIL: rc=$rc log=$(cat "$log_file")"; fail=1; fi

echo "=== Case 4: generic error -> generic message, exit 1 ==="
: > "$log_file"
( run_dispatch $'{"message":"disk full"}\n500' ) >/dev/null 2>&1
rc=$?
if [[ "$rc" == "1" ]] && grep -q "Error calling" "$log_file"; then echo "PASS"; else echo "FAIL: rc=$rc log=$(cat "$log_file")"; fail=1; fi

echo "=== Case 5: success with job ID -> wait_for_job called ==="
rm -f "$WORKDIR/wfj_called"
run_dispatch $'{"jobID":"job-123"}\n202'
if [[ "$(cat "$WORKDIR/wfj_called" 2>/dev/null)" == "job-123" ]]; then echo "PASS"; else echo "FAIL: wait_for_job not called correctly"; fail=1; fi

echo "=== Case 6: success but no job ID -> abort 1 ==="
: > "$log_file"
( run_dispatch $'{}\n202' ) >/dev/null 2>&1
rc=$?
if [[ "$rc" == "1" ]] && grep -q "no Job ID" "$log_file"; then echo "PASS"; else echo "FAIL: rc=$rc log=$(cat "$log_file")"; fail=1; fi

if [[ $fail -eq 0 ]]; then echo "ALL PASS"; else echo "SOME TESTS FAILED"; exit 1; fi
```

Run: `bash /tmp/test_imgimport_dispatch.sh`
Expected: 6 `PASS:` lines then `ALL PASS`.

- [ ] **Step 7: Clean up the verification script**

Run: `rm -f /tmp/test_imgimport_dispatch.sh`

- [ ] **Step 8: Commit**

```bash
cd /home/rqmartins/Git/bluexport_api
git add bluexport_api.sh
git commit -m "$(cat <<'EOF'
-imgimport: 409/"already running" detection, exit 1 on failure, monitor job

img_import_api() now captures HTTP status. A 409 (or an error message
matching "already running"/"in progress"/"conflict") gets a specific,
clear abort message instead of a generic one. Every genuine-failure
abort() call in img_import() now exits 1. On success, the tail now
calls wait_for_job() instead of firing-and-forgetting; if no Job ID
comes back, this is now a failure (exit 1) rather than a false success.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: `img_export_api()` + `img_export()` + `-imgexport` case dispatch

**Files:**
- Modify: `bluexport_api.sh` — new function `img_export_api()`, placed immediately after `img_import_api()` (confirm current line with `grep -n '^img_import_api() {' bluexport_api.sh` first)
- Modify: `bluexport_api.sh` — new function `img_export()`, placed immediately after `img_import()` (confirm current line with `grep -n '^img_import() {' bluexport_api.sh` first — line numbers have shifted since Task 3)
- Modify: `bluexport_api.sh` — new `-imgexport` case block, placed immediately after the existing `-imgimport` case (confirm current line with `grep -n '^   -imgimport)' bluexport_api.sh` first)

**Interfaces:**
- Consumes: `load_hmac_keys()`, `abort MESSAGE [EXIT_CODE]` (Task 1), `wait_for_job()` (Task 2), the 409-detection pattern established in Task 3, `do_img_delete()`'s workspace-search loop shape (read, not modified), `img_ls()` (existing, unchanged), globals `$allws`, `$accesskey`/`$secretkey`, `$bluexscrt`, `$header_auth`.
- Produces: `-imgexport IMGNAME BUCKET BUCKET_REGION CURRACCOUNT|OTHERACCOUNT [HMAC_JSON_FILE]`.

- [ ] **Step 1: Confirm current line numbers**

Run: `grep -n '^img_import_api() {\|^img_import() {\|^   -imgimport)' bluexport_api.sh`

- [ ] **Step 2: Add `img_export_api()` next to `img_import_api()`**

Insert immediately after `img_import_api()`'s closing `}`:

```bash

img_export_api() {
	curl -sX POST $base_url/pcloud/v2/cloud-instances/$CLOUD_INSTANCE_ID/images/$IMAGE_ID/export -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -d "{$ACTIONS}" -w '\n%{http_code}'
}
```

- [ ] **Step 3: Add `img_export()` next to `img_import()`**

Insert immediately after `img_import()`'s closing `}` and its `#### END:FUNCTION` marker:

```bash

####  START:FUNCTION - Export Image to COS (img_export) ####
img_export() {
	local img_name="$1"
	local export_bucket="$2"
	local export_bucket_region="$3"
	local account_type="$4"
	local hmac_file="$5"

	if [[ -z "$img_name" || -z "$export_bucket" || -z "$export_bucket_region" || -z "$account_type" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many or too few arguments!! Syntax: bluexport_api.sh -imgexport IMGNAME BUCKET BUCKET_REGION CURRACCOUNT|OTHERACCOUNT [HMACKEYS-JSON-FILE-PATH-NAME]" 1
	fi

	export_bucket_region=${export_bucket_region,,}
	if ! echo "$export_bucket_region" | grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*$'
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Invalid BUCKET_REGION: $export_bucket_region. Use the IBM COS S3 endpoint region, for example eu-es, eu-de, us-east or us-south." 1
	fi

	account_type=${account_type^^}
	if [[ "$account_type" != "CURRACCOUNT" && "$account_type" != "OTHERACCOUNT" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Invalid account type: $account_type. Valid values are CURRACCOUNT or OTHERACCOUNT." 1
	fi
	if [[ "$account_type" == "CURRACCOUNT" && -n "$hmac_file" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! HMACKEYS-JSON-FILE-PATH-NAME is only valid with OTHERACCOUNT." 1
	fi
	if [[ "$account_type" == "OTHERACCOUNT" && -z "$hmac_file" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - HMACKEYS-JSON-FILE-PATH-NAME is mandatory when using OTHERACCOUNT." 1
	fi
	if [[ "$account_type" == "OTHERACCOUNT" && ! -f "$hmac_file" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - HMAC keys JSON file $hmac_file not found. Aborting..." 1
	fi

	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - === Starting Image Export to COS ===" "1"
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Image to export: $img_name" "1"
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Target Bucket: $export_bucket" "1"
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Target Bucket Region: $export_bucket_region" "1"
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Account Type: $account_type" "1"

	# Procurar a imagem por nome em todas as workspaces (mesmo padrão do do_img_delete)
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

	local cos_accesskey cos_secretkey cos_region
	cos_region="$export_bucket_region"
	if [[ "$account_type" == "CURRACCOUNT" ]]
	then
		cos_accesskey="$accesskey"
		cos_secretkey="$secretkey"
	else
		load_hmac_keys "$hmac_file"
		cos_accesskey="$hmac_access_key"
		cos_secretkey="$hmac_secret_key"
	fi
	if [[ -z "$cos_accesskey" || -z "$cos_secretkey" || "$cos_accesskey" == "null" || "$cos_secretkey" == "null" ]]
	then
		if [[ "$account_type" == "OTHERACCOUNT" ]]
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` - Missing COS HMAC accessKey/secretKey. Check $hmac_file." 1
		else
			abort "`date +%Y-%m-%d_%H:%M:%S` - Missing COS HMAC accessKey/secretKey. Check $bluexscrt." 1
		fi
	fi

	# Pré-validar a bucket de destino (só a bucket em si - o objecto ainda não existe,
	# o nome final é decidido pela API). Ignora qualquer prefixo/pasta em BUCKET.
	# Usa SEMPRE --aws-sigv4 com as mesmas credenciais que vão para o payload do PowerVS
	# (nunca IAM bearer, mesmo em CURRACCOUNT), para que este pré-check valide mesmo as
	# HMAC keys que importam - ver spec 2026-08-06, correcção D.4.
	local bucket_root="${export_bucket%%/*}"
	local cos_endpoint head_http head_body
	cos_endpoint="https://s3.${cos_region}.cloud-object-storage.appdomain.cloud/${bucket_root}"
	head_body="/tmp/bluexport_imgexport_head_$$.out"
	head_http=$(curl -sS -o "$head_body" -w "%{http_code}" --connect-timeout 30 --max-time 120 --aws-sigv4 "aws:amz:${cos_region}:s3" --user "${cos_accesskey}:${cos_secretkey}" -I "$cos_endpoint" 2>>"$log_file")
	cat "$head_body" >> "$log_file" 2>/dev/null
	rm -f "$head_body"
	case "$head_http" in
		200|204)
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - COS bucket check OK: $bucket_root in region $cos_region." "1"
			;;
		301|302|307|308)
			abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - COS bucket validation was redirected. This usually means BUCKET_REGION is wrong. Bucket: $bucket_root, region used: $cos_region." 1
			;;
		403)
			abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - COS access denied for bucket $bucket_root in region $cos_region. This normally means invalid HMAC keys, wrong bucket region, or missing COS permissions." 1
			;;
		404)
			abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - COS bucket not found: $bucket_root in region $cos_region." 1
			;;
		*)
			abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Unable to validate COS bucket $bucket_root. HTTP status: $head_http." 1
			;;
	esac

	ACTIONS=$(jq -n \
		--arg bucketName "$export_bucket" \
		--arg region "$cos_region" \
		--arg accessKey "$cos_accesskey" \
		--arg secretKey "$cos_secretkey" \
		'{bucketName:$bucketName,region:$region,accessKey:$accessKey,secretKey:$secretKey}' \
		| sed 's/^{//; s/}$//')

	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Calling PowerVS Image Export API for $img_name (ID $IMAGE_ID) from Workspace $found_ws_name to bucket $export_bucket..." "1"
	local export_raw export_http_code export_resp export_rc export_error export_job_id
	export_raw=$(img_export_api 2>>"$log_file")
	export_rc=$?
	export_http_code="${export_raw##*$'\n'}"
	export_resp="${export_raw%$'\n'*}"
	printf '%s\n' "$export_resp" >> "$log_file"
	if [ "$export_rc" -ne 0 ] || [[ ! "$export_http_code" =~ ^2[0-9][0-9]$ ]] || printf '%s' "$export_resp" | jq -e '.code? != null or .error? != null or .errors? != null' >/dev/null 2>&1
	then
		export_error=$(printf '%s' "$export_resp" | jq -r '.message // .error // (.errors[0].message?) // .description // "Unknown error"' 2>/dev/null)
		if [[ "$export_http_code" == "409" ]] || echo "$export_error $export_resp" | grep -Eiq 'already running|in progress|conflict'
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Another import/export operation is already running in this workspace. Wait for it to complete before starting a new one." 1
		fi
		if echo "$export_error $export_resp" | grep -Eiq 'hmac|access.?key|secret.?key|signature|credential|forbidden|not authorized|access denied'
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - PowerVS image export rejected the COS credentials/HMAC keys: $export_error" 1
		fi
		abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Error calling PowerVS image export API for $img_name: $export_error" 1
	fi

	export_job_id=$(printf '%s' "$export_resp" | jq -r '.jobID // .id // .job.id // .jobReference.id // empty' 2>>"$log_file" | head -n1)
	if [[ -n "$export_job_id" ]]
	then
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Image export submitted successfully. Job ID: $export_job_id" "1"
		wait_for_job "$export_job_id" "Image export of $img_name to bucket $export_bucket"
	else
		abort "`date +%Y-%m-%d_%H:%M:%S` - Image export submitted, but no Job ID was returned by the API. Response saved in $log_file. Check the Boot images page or -imglsall to confirm it completed." 1
	fi
}
####  END:FUNCTION - Export Image to COS (img_export) ####
```

- [ ] **Step 4: Add the `-imgexport` case dispatch**

Insert immediately after the existing `-imgimport)` case block's closing `;;`:

```bash

   -imgexport)
	if [[ $# -lt 5 || $# -gt 6 ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many or too few arguments!! Syntax: bluexport_api.sh -imgexport IMGNAME BUCKET BUCKET_REGION CURRACCOUNT|OTHERACCOUNT [HMAC_JSON_FILE]" 1
	fi
	img_export "$2" "$3" "$4" "$5" "$6"
    ;;
```

- [ ] **Step 5: Syntax check**

Run: `bash -n bluexport_api.sh`
Expected: no output.

- [ ] **Step 6: Write and run a mocked functional test**

Tests argument validation, the aws-sigv4-only invariant (the key correction from spec review), 409 detection, and successful dispatch to `wait_for_job`, all with mocked `img_ls`/`img_export_api`/`curl`/`load_hmac_keys` — without needing real network access or a real `bluexscrt` JSON.

Create `/tmp/test_img_export.sh`:

```bash
#!/bin/bash
set -uo pipefail
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT
mkdir -p "$WORKDIR/bin"

REPO=/home/rqmartins/Git/bluexport_api

# Fake curl: logs every invocation's args to a file, and returns canned
# responses based on whether it's a bucket-HEAD call (-I flag present) or
# something else. The test overrides img_export_api directly (see below),
# so this fake curl only needs to handle the bucket-HEAD pre-check.
cat > "$WORKDIR/bin/curl" <<'CURLEOF'
#!/bin/bash
echo "CURL_CALL: $*" >> "$CURL_LOG"
# Bucket HEAD pre-check: find -o and -w targets, write status to stdout per -w.
for a in "$@"; do :; done
echo -n "200"
CURLEOF
chmod +x "$WORKDIR/bin/curl"
export CURL_LOG="$WORKDIR/curl.log"
: > "$CURL_LOG"
export PATH="$WORKDIR/bin:$PATH"

source <(sed -n '/^abort() {/,/^}/p' "$REPO/bluexport_api.sh")
source <(sed -n '/^load_hmac_keys() {/,/^}/p' "$REPO/bluexport_api.sh")
source <(sed -n '/^img_export() {/,/^}/p' "$REPO/bluexport_api.sh")

log_file="$WORKDIR/test.log"
end_log_file=""
: > "$log_file"
echoscreen() { echo "LOG: $1" >> "$WORKDIR/echoscreen.log"; }

bluexscrt="$WORKDIR/bluexscrt.json"
cat > "$bluexscrt" <<'EOF'
{
  "workspaces": {"WS1": {"crn":"crn:v1:bluemix:public:power-iaas:us-east:a/x:id1::", "id":"cloudinst1", "name":"Workspace One"}},
  "systems": []
}
EOF
allws="WS1"
accesskey="curr-access"
secretkey="curr-secret"
header_auth="Authorization: Bearer faketoken"
header_json="Content-Type: application/json"
base_us_east="https://us-east.power-iaas.cloud.ibm.com"

img_ls() {
	echo '{"images":[{"name":"myimage","imageID":"img-id-123"}]}'
}

fail=0

echo "=== Case 1: wrong arg count -> abort 1 ==="
( img_export "" "bucket" "us-east" "CURRACCOUNT" "" ) 2>&1 >/dev/null
rc=$?
if [[ "$rc" == "1" ]]; then echo "PASS"; else echo "FAIL: rc=$rc"; fail=1; fi

echo "=== Case 2: invalid account type -> abort 1 ==="
( img_export "myimage" "bucket" "us-east" "BADTYPE" "" ) 2>&1 >/dev/null
rc=$?
if [[ "$rc" == "1" ]]; then echo "PASS"; else echo "FAIL: rc=$rc"; fail=1; fi

echo "=== Case 3: image not found -> abort 1 ==="
img_ls() { echo '{"images":[]}'; }
( img_export "nosuchimage" "bucket" "us-east" "CURRACCOUNT" "" ) 2>&1 >/dev/null
rc=$?
if [[ "$rc" == "1" ]]; then echo "PASS"; else echo "FAIL: rc=$rc"; fail=1; fi
img_ls() { echo '{"images":[{"name":"myimage","imageID":"img-id-123"}]}'; }

echo "=== Case 4: CURRACCOUNT bucket HEAD check uses --aws-sigv4, NOT bearer auth ==="
: > "$CURL_LOG"
img_export_api() { echo -e '{"jobID":"job-999"}\n202'; }
wait_for_job() { echo "WAIT_FOR_JOB_CALLED: $1" > "$WORKDIR/wfj.log"; }
( img_export "myimage" "mybucket" "us-east" "CURRACCOUNT" "" ) >/dev/null 2>&1
if grep -q -- "--aws-sigv4" "$CURL_LOG"; then
	echo "PASS: aws-sigv4 used for CURRACCOUNT bucket check"
else
	echo "FAIL: aws-sigv4 NOT used for CURRACCOUNT - curl log: $(cat "$CURL_LOG")"
	fail=1
fi
if grep -q -- "aws:amz:us-east:s3" "$CURL_LOG" && grep -q -- "curr-access:curr-secret" "$CURL_LOG"; then
	echo "PASS: bucket check used the CURRACCOUNT accesskey/secretkey (not bearer)"
else
	echo "FAIL: bucket check did not use the expected CURRACCOUNT credentials"
	fail=1
fi
if [[ "$(cat "$WORKDIR/wfj.log" 2>/dev/null)" == "WAIT_FOR_JOB_CALLED: job-999" ]]; then
	echo "PASS: wait_for_job called with correct job ID"
else
	echo "FAIL: wait_for_job not called correctly"
	fail=1
fi

echo "=== Case 5: 409 from export API -> specific message, exit 1 ==="
img_export_api() { echo -e '{"message":"conflict"}\n409'; }
: > "$log_file"
( img_export "myimage" "mybucket" "us-east" "CURRACCOUNT" "" ) >/dev/null 2>&1
rc=$?
if [[ "$rc" == "1" ]] && grep -q "already running" "$log_file"; then
	echo "PASS"
else
	echo "FAIL: rc=$rc log=$(cat "$log_file")"
	fail=1
fi

if [[ $fail -eq 0 ]]; then echo "ALL PASS"; else echo "SOME TESTS FAILED"; exit 1; fi
```

Run: `bash /tmp/test_img_export.sh`
Expected: 7 `PASS:` lines then `ALL PASS`. Pay particular attention to Case 4's two checks — they verify the exact correction from the spec review (aws-sigv4 always, never bearer, for the bucket pre-check).

- [ ] **Step 7: Clean up the verification script**

Run: `rm -f /tmp/test_img_export.sh`

- [ ] **Step 8: Commit**

```bash
cd /home/rqmartins/Git/bluexport_api
git add bluexport_api.sh
git commit -m "$(cat <<'EOF'
Add -imgexport: export a boot image from a workspace catalog to COS

Mirrors -imgimport in reverse: img_export_api() POSTs to the v2
/images/{id}/export endpoint; img_export() resolves an image NAME to
an ID by searching every workspace (same pattern as do_img_delete()),
supports CURRACCOUNT/OTHERACCOUNT, pre-validates the target bucket
via HTTP HEAD, and monitors the resulting job via wait_for_job().

The bucket pre-check always uses --aws-sigv4 with the exact
accessKey/secretKey that get sent to PowerVS, for both account types
- never IAM bearer auth, even for CURRACCOUNT - so a pre-check pass
actually proves those specific HMAC credentials work.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Documentation, `hmac_keys_example.json`, version bump

**Files:**
- Modify: `bluexport_api.sh` — header comment block (lines ~30-59) and `help()` (lines ~460-483)
- Modify: `bluexport_api.sh:143` (`Version=`)
- Create: `hmac_keys_example.json` (repo root)
- Modify: `README.md`, `CHANGELOG.md`

**Interfaces:**
- Consumes: nothing (documentation/metadata only). Run this task last, after Tasks 1-4 are committed.

- [ ] **Step 1: Create `hmac_keys_example.json`**

Create `/home/rqmartins/Git/bluexport_api/hmac_keys_example.json`:

```json
{
    "cos_hmac_keys": {
        "access_key_id": "COLOCAR_ACCESS_KEY_AQUI",
        "secret_access_key": "COLOCAR_SECRET_KEY_AQUI"
    }
}
```

- [ ] **Step 2: Validate it's valid JSON**

Run: `jq empty hmac_keys_example.json && echo "VALID JSON"`
Expected: `VALID JSON`.

- [ ] **Step 3: Update the header comment block**

Read `bluexport_api.sh` around the existing `-imgimport` header comment (find it with `grep -n 'Import image from COS' bluexport_api.sh`) and add a mirrored block for `-imgexport` immediately after it:

```bash
# Export image to COS:
#   bluexport_api.sh -imgexport IMGNAME BUCKET BUCKET_REGION CURRACCOUNT|OTHERACCOUNT [HMAC_JSON_FILE]
#
#   BUCKET_REGION is the IBM COS S3 endpoint region where the destination bucket exists.
#   Same HMAC JSON file format as -imgimport for OTHERACCOUNT (see above, or copy
#   hmac_keys_example.json in this repo and fill in your keys).
#   Both -imgimport and -imgexport monitor their PowerVS job to completion and exit
#   non-zero on failure (including if another import/export is already running in the
#   target workspace - PowerVS only allows one at a time per workspace).
```

- [ ] **Step 4: Update `help()`**

Find the existing `-imgimport` block in `help()` (`grep -n 'Import image from COS:' bluexport_api.sh`) and add a mirrored block immediately after it:

```bash
	echoscreen "Export image to COS:"
	echoscreen "  bluexport_api.sh -imgexport IMGNAME BUCKET BUCKET_REGION CURRACCOUNT|OTHERACCOUNT [HMAC_JSON_FILE]"
	echoscreen ""
	echoscreen "  BUCKET_REGION:"
	echoscreen "    IBM COS S3 endpoint region where the destination bucket exists."
	echoscreen "    Examples: eu-es, eu-de, us-east, us-south."
	echoscreen ""
	echoscreen "  OTHERACCOUNT:"
	echoscreen "    Same HMAC JSON file format as -imgimport - copy hmac_keys_example.json"
	echoscreen "    in this repo and fill in your keys."
	echoscreen ""
	echoscreen "  Both -imgimport and -imgexport monitor the PowerVS job to completion and"
	echoscreen "  exit non-zero on failure, including if another import/export operation is"
	echoscreen "  already running in the target workspace."
	echoscreen ""
```

- [ ] **Step 5: Bump `Version=`**

Confirm current value first: `grep -n '^Version=' bluexport_api.sh`. Change to `Version=1.14.0`.

- [ ] **Step 6: Update `README.md`**

Read `README.md`'s existing "Import image from COS" section (search for it) and add a new "Export image to COS" section right after it, documenting the syntax, `CURRACCOUNT`/`OTHERACCOUNT`, the `hmac_keys_example.json` file, and that both flags now monitor the job to completion (mention the `load_hmac_keys` fix if there's an existing note that OTHERACCOUNT import didn't work — check first).

- [ ] **Step 7: Update `CHANGELOG.md`**

Read `CHANGELOG.md`'s `## [Unreleased]` section and the most recent entries for formatting, then add a new entry:

```markdown
## [1.14.0] - 2026-08-06 (`bluexport_api.sh`)

### Added
- `-imgexport IMGNAME BUCKET BUCKET_REGION CURRACCOUNT|OTHERACCOUNT [HMAC_JSON_FILE]`: export a boot image from a workspace's image catalog to a COS bucket, mirroring `-imgimport` in reverse (image resolved by name, searched across every workspace, same as `-imgdel`). Supports cross-account export via HMAC keys, same JSON format as `-imgimport` (see new `hmac_keys_example.json`).
- `wait_for_job()`: new generic PowerVS job poller (copies `job_monitor()`'s proven polling/retry logic without any capture-specific behavior) now backs both `-imgimport` and `-imgexport` - both flags monitor their job to completion instead of only confirming submission, and exit `1` on failure instead of always exiting `0`.
- 409/"already running" detection for both `-imgimport` and `-imgexport`: PowerVS only allows one import/export operation per workspace at a time; a rejection for this reason now gets a specific, clear message instead of a generic API error.

### Fixed
- `-imgimport ... OTHERACCOUNT`: `load_hmac_keys()` was called but never defined anywhere in the script, so this path has never worked - it always failed with "Missing COS HMAC accessKey/secretKey". Now implemented.
- `abort()` gained an optional exit-code argument (default `0`, fully backward compatible with every existing call site) so genuine failures in `-imgimport`/`-imgexport` can be distinguished from success via `$?`.
```

- [ ] **Step 8: Syntax check both changed files**

Run: `bash -n bluexport_api.sh && jq empty hmac_keys_example.json && echo "ALL OK"`
Expected: `ALL OK`

- [ ] **Step 9: Commit**

```bash
cd /home/rqmartins/Git/bluexport_api
git add bluexport_api.sh hmac_keys_example.json README.md CHANGELOG.md
git commit -m "$(cat <<'EOF'
Version bump + docs for -imgexport

bluexport_api.sh -> 1.14.0 (MINOR: additive -imgexport, real bug fix
in load_hmac_keys, non-breaking behavior changes to -imgimport).

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Real-world verification (required before calling this done)

Not a code task — acceptance checklist against the user's real IBM Cloud account. Sandbox tests above prove logic only; they use mocked `curl`/`img_ls`/`job_get`, not the real PowerVS API. Do not report this feature as done without running this.

- [ ] **Step 1: Confirm `-imgimport ... OTHERACCOUNT` now actually works**

Ask the user for (or use, if already available) a real HMAC JSON file and a COS bucket/object to import from, in `OTHERACCOUNT` mode specifically (the path that was silently broken before this plan). Confirm it no longer fails with "Missing COS HMAC accessKey/secretKey", and that the job is monitored to completion.

- [ ] **Step 2: Run `-imgexport` for real against `CURRACCOUNT`**

Export a real (ideally small/disposable) boot image from a workspace's catalog to a COS bucket in the same account. Confirm: the bucket pre-check passes, the job is submitted and monitored to completion, and the exported object actually appears in the bucket afterward (check via console or `-bucketlsobjs`).

- [ ] **Step 3: Run `-imgexport` for real against `OTHERACCOUNT`**

Same as Step 2, but exporting to a bucket in a different account via HMAC keys (`hmac_keys_example.json` filled in). Confirm it works end-to-end.

- [ ] **Step 4: Confirm 409 detection with a real "already running" collision**

Start a real import or export, then immediately attempt a second one against the same workspace before the first completes. Confirm the second one gets the specific "already running" message (or note if PowerVS actually returns a different status/message shape than expected, and report this back — the keyword fallback exists precisely because this wasn't verifiable from docs alone).

- [ ] **Step 5: Confirm exit codes from a shell**

Run `-imgimport`/`-imgexport` with an intentionally invalid argument (e.g., a nonexistent bucket) and check `echo $?` afterward — confirm it's `1`, not `0`. Run a real successful case and confirm `echo $?` is `0`.

- [ ] **Step 6: Real verification on IBM i PASE**

Repeat at least Steps 2 and 5 on the real IBM i PASE environment (not just wherever this plan was implemented), per standing project guidance — sandbox/local testing proves logic, not PASE execution. Report explicitly whether this ran on PASE or only elsewhere.

- [ ] **Step 7: Report results to the user**

Summarize what was confirmed at each step, any deviations from expected behavior (especially the actual HTTP status PowerVS uses for "already running", if discovered), and get explicit sign-off before considering this feature complete.

---

## Self-Review Notes

- **Spec coverage:** Section A (`load_hmac_keys`) → Task 1. Section A.1 (`abort()` exit code) → Task 1. Section B (`wait_for_job`) → Task 2. Section C (`-imgimport` wiring) → Task 3. Section C.1 (409 detection) → Task 3 (import) and Task 4 (export). Section D (`img_export`/`-imgexport`, including the D.3/D.4 aws-sigv4-only correction) → Task 4. Section E (docs) → Task 5. Section F (versioning) → Task 5. Non-goals: no disambiguation logic added (confirmed absent from all tasks), no export filename control added (confirmed absent), `job_monitor()` untouched (confirmed — no task modifies it). All spec sections have a task.
- **Placeholder scan:** no TBD/TODO; every step has literal code or an exact command.
- **Type/name consistency:** `wait_for_job JOB_ID LABEL` signature identical everywhere it's called (Task 3's `img_import()`, Task 4's `img_export()`). `abort MESSAGE [EXIT_CODE]` used consistently. `cos_accesskey`/`cos_secretkey` variable names match between Task 4's design and its test. `load_hmac_keys` → `hmac_access_key`/`hmac_secret_key` global names consistent between Task 1 and Task 4.
- **Line numbers:** every task's Step 1 re-confirms current line numbers with `grep` before editing, since `bluexport_api.sh` shifts with each prior task in this plan — do not trust line numbers cited in prose, only the exact `old_string`/`new_string`/insertion-point content blocks.
- **Post-approval corrections (user technical review, 2026-08-06):** three issues found in the first draft of this plan, now fixed throughout: (1) the error-detection condition in both `img_import()` and `img_export()` originally relied only on `curl`'s exit code and `.code`/`.error`/`.errors` JSON fields — since `curl` exits `0` on HTTP error statuses and a plausible error body may carry only `.message`, a 409/403/500 could fall through undetected; fixed by also checking the captured HTTP status is 2xx (now reflected in Global Constraints). (2) Every test script that asserts on an `abort()` message text was reading captured stdout, but `abort()` only echoes to the terminal when `[ -t 1 ]` — false inside command substitution — so the message only ever reaches `$log_file`; all such assertions now `grep` the log file instead. (3) Every test script that sources the real `abort()` must set `end_log_file=""` before any call, or `abort()`'s `eval echo $end_log_file >> $log_file` line trips "unbound variable" under `set -u` and produces a coincidentally-correct exit code for the wrong reason; this is now set in every test script's setup (Task 1's already had it; Tasks 2-4 added).
