# Per-Flag Usage Detail (usage_X()) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every flag in `bluexport_api.sh` and `bluexscrt_config_api.sh` that takes at least one argument gets a dedicated `usage_<flag>()` function printing a per-parameter breakdown, shown both when the user gets the argument count wrong and via a new `-h -FLAG` detailed-help mode.

**Architecture:** One small `usage_X()` function per argument-taking flag, defined in a new section right before each script's `case` dispatcher (functions must be defined before the dispatcher runs). Each function `echoscreen`s (or, in `bluexscrt_config_api.sh`, plain `echo >&2` — see Task 7) a nested two-line-per-parameter breakdown, screen-only. Two call sites use it: the flag's own existing argument-count-mismatch `abort()`/`exit` call (function runs immediately before it, log behavior unchanged), and a new `-h -FLAG` branch inside the existing `-h | --help | -help)` case that looks the flag up (including all its aliases) and calls the matching function.

**Tech Stack:** Bash (IBM i PASE-compatible).

## Global Constraints

- Must remain IBM i PASE/QShell-compatible — no Linux-only constructs, no GNU-only flags not already used elsewhere in these files.
- Every `echoscreen` call inside a `usage_X()` function in `bluexport_api.sh` is made WITHOUT the second `"1"` argument — screen-only, never written to the log file. This is deliberate: the detail is only useful interactively; the log stays exactly as concise as it is today.
- `usage_X()` functions in `bluexscrt_config_api.sh` use plain `echo "..." >&2` instead (see Task 7 for why — that script's `-dellpar`/`-addlpar` error paths don't use `echoscreen`/`abort()` today, and this plan does not migrate them to it).
- No change to any flag's existing argument-count validation logic (`-lt`/`-gt`/`-ne`/`-eq` checks) or its existing `abort()`/`echo+exit` call's message or exit code — only a new `usage_X` call inserted immediately before it.
- No change to `abort()`, `echoscreen()`, or the general `help()`/`usage()` functions themselves.
- `-h | --help | -help` (both scripts) accepts at most one additional argument. `-h` alone → full help, exit 0 (unchanged). `-h -FLAG` → detailed flag help via `usage_<flag>`, exit 0. `-h -FLAG EXTRA` (2+ extra args) → error, exit 1. `-h -UNKNOWNFLAG` (not recognized, or a zero-argument flag with no `usage_X()`) → error, exit 1, message: `"Unknown flag for detailed help: X. Run bluexport_api.sh -h for the full command list."` (adapt the binary name for `bluexscrt_config_api.sh`).
- For shared case aliases (`-a | -ta`, `-x | -tx`), every accepted alias must be recognized by the `-h -FLAG` lookup and dispatch to the same `usage_X()` function (e.g. both `-h -a` and `-h -ta` call `usage_a`).
- Optional parameters must say so explicitly in their description (e.g. "Optional; required only for X" / "Optional; defaults to Y if omitted"). Enum-style parameters list their valid values explicitly.
- Zero-argument flags get no `usage_X()` function: `bluexport_api.sh`: `-h`/`--help`/`-help`, `-v`/`--version`, `-viewscrt`, `-snaplsall`, `-imglsall`, `-vclonelsall`, `-bucketslsall`, `-bucketlsobjs`, `-bucketdelobj`. `bluexscrt_config_api.sh`: `-h`/`--help`, `-createconfig`, `-updlpars`, `-updws`.
- Two pre-existing, real inconsistencies must be called out explicitly in the relevant descriptions, not silently "fixed": (1) `-vclone`'s VOLUMES parameter is volume **names** (a stale code comment nearby says "IDs" — a prior user correction, recorded in project memory, confirms names); (2) `-vchtier`/`-insvchtier`'s TIER parameter is a bare digit/suffix (`0|1|3|5k`, the script prepends `tier`) while `-vclone`'s TARGET_TIER is already prefixed (`tier0|tier1|tier3|tier5k`) — the opposite convention.
- Version bump: MINOR for both scripts (purely additive, no existing behavior changed) — `bluexport_api.sh` 1.15.0 → 1.16.0, `bluexscrt_config_api.sh` 2.0 → 2.1.
- Spec: `docs/superpowers/specs/2026-08-10-per-flag-usage-detail-design.md` (approved).

---

## File Structure

- Modify `bluexport_api.sh` only (Tasks 1-6):
  - New section "usage_X() — per-flag parameter detail" inserted immediately before `case $1 in` (currently line 5102) — grows across Tasks 1-6, each task appending its own group's functions.
  - The `-h | --help | -help)` case block (currently lines 5103-5106) — rewritten once in Task 1 to add the arg-count limit and the `-h -FLAG` inner dispatch; Tasks 2-6 each add their own group's entries to that inner dispatch's `case "$2" in`.
  - Each flag's own case block — one `usage_X` call inserted before each existing arg-count-mismatch `abort()` call (some flags have two: a `-lt`/`-gt` pair).
- Modify `bluexscrt_config_api.sh` (Task 7): new `usage_dellpar()`/`usage_addlpar()` functions, `-h | --help)` case block rewritten for the `-h -FLAG` mode, `usage_X` calls inserted before `-dellpar`/`-addlpar`'s existing `echo "ERROR..." >&2; exit 1` blocks.
- Modify `README.md`, `CHANGELOG.md`, and both scripts' `Version=`/`VERSION=` (Task 8).

---

### Task 1: `bluexport_api.sh` — Capture/Export/Job-Monitor group + `-h -FLAG` infrastructure

**Files:**
- Modify: `bluexport_api.sh` — new functions section before `case $1 in`; the `-h | --help | -help)` block; the `-j`, `-a | -ta`, `-x | -tx`, `-imgdel`, `-imgimport`, `-imgexport`, `-ji`, `-je` case blocks.

**Interfaces:**
- Produces: `usage_j()`, `usage_a()` (covers `-a`/`-ta`), `usage_x()` (covers `-x`/`-tx`), `usage_imgdel()`, `usage_imgimport()`, `usage_imgexport()`, `usage_ji()`, `usage_je()` — all zero-argument functions, no return value, `echoscreen`-only side effects. Establishes the `-h -FLAG` inner `case "$2" in ... esac` dispatch pattern that Tasks 2-6 extend by inserting more arms before its `*)` catch-all.

- [ ] **Step 1: Confirm current line numbers**

Run: `grep -n '^case \$1 in\|^   -h | --help | -help)\|^   -j)\|^   -a | -ta)\|^   -x | -tx)\|^   -imgdel)\|^   -imgimport)\|^   -imgexport)\|^   -ji)\|^   -je)' bluexport_api.sh`

Read from `case $1 in` through the `-je)` block's closing `;;` to confirm the text below still matches exactly.

- [ ] **Step 2: Insert the new functions section immediately before `case $1 in`**

Insert immediately before the line `case $1 in`:

```bash
#### START: usage_X() - per-flag parameter detail (shown on argument-count error and via -h -FLAG) ####
usage_j() {
	echoscreen "  VSI_NAME:"
	echoscreen "    Name of the VSI whose capture job to monitor."
	echoscreen "  IMAGE_NAME:"
	echoscreen "    Capture image name (as passed to -a/-x when the capture was started)."
}

usage_a() {
	echoscreen "  VSI_NAME:"
	echoscreen "    Name of the VSI to capture."
	echoscreen "  IMAGE_NAME:"
	echoscreen "    Base name for the capture image; a timestamp suffix is appended."
	echoscreen "  DESTINATION:"
	echoscreen "    both|image-catalog|cloud-storage - where the capture ends up."
	echoscreen "    hourly/daily only allow image-catalog (not cloud-storage or both)."
	echoscreen "  RECURRENCE:"
	echoscreen "    hourly|daily|weekly|monthly|single - controls the retention window"
	echoscreen "    used to identify the previous capture to clean up."
	echoscreen "  Note: -ta runs the same flow in test mode - it validates and logs"
	echoscreen "  everything but does not actually run the capture."
}

usage_x() {
	echoscreen "  EXCLUDE_NAME:"
	echoscreen "    Volume name pattern(s) to exclude from the capture (space separated;"
	echoscreen "    matched case-insensitively as a substring against each volume name)."
	echoscreen "  VSI_NAME:"
	echoscreen "    Name of the VSI to capture."
	echoscreen "  IMAGE_NAME:"
	echoscreen "    Base name for the capture image; a timestamp suffix is appended."
	echoscreen "  DESTINATION:"
	echoscreen "    both|image-catalog|cloud-storage - where the capture ends up."
	echoscreen "    hourly/daily only allow image-catalog (not cloud-storage or both)."
	echoscreen "  RECURRENCE:"
	echoscreen "    hourly|daily|weekly|monthly|single - controls the retention window"
	echoscreen "    used to identify the previous capture to clean up."
	echoscreen "  Note: -tx runs the same flow in test mode - it validates and logs"
	echoscreen "  everything but does not actually run the capture."
}

usage_imgdel() {
	echoscreen "  IMG_NAME:"
	echoscreen "    Name of the captured image to delete (searched across all workspaces)."
}

usage_imgimport() {
	echoscreen "  IMGNAME:"
	echoscreen "    COS object filename to import (e.g. myimage.ova.gz)."
	echoscreen "  BUCKET:"
	echoscreen "    COS bucket name where the object is stored."
	echoscreen "  BUCKET_REGION:"
	echoscreen "    IBM COS S3 endpoint region where the source bucket exists."
	echoscreen "    Examples: eu-es, eu-de, us-east, us-south."
	echoscreen "    Do not use the PowerVS datacenter name here (e.g. mad02)."
	echoscreen "  WORKSPACE_TO_IMPORT:"
	echoscreen "    Target PowerVS workspace, short or full name."
	echoscreen "  IMGNAME_WS:"
	echoscreen "    Name to give the imported image in the workspace's image catalog."
	echoscreen "  STORAGE_TYPE:"
	echoscreen "    tier0|tier1|tier3|tier5k."
	echoscreen "  CURRACCOUNT|OTHERACCOUNT:"
	echoscreen "    COS account type. OTHERACCOUNT requires HMAC JSON file from IBM"
	echoscreen "    Cloud COS Service Credentials (.cos_hmac_keys.access_key_id and"
	echoscreen "    .cos_hmac_keys.secret_access_key)."
	echoscreen "  HMAC_JSON_FILE:"
	echoscreen "    Optional; required only for OTHERACCOUNT."
}

usage_imgexport() {
	echoscreen "  IMGNAME:"
	echoscreen "    Name of the captured image (in the workspace catalog) to export."
	echoscreen "  BUCKET:"
	echoscreen "    COS bucket name to export to; may include a folder prefix"
	echoscreen "    (bucketName/optional/folder)."
	echoscreen "  BUCKET_REGION:"
	echoscreen "    IBM COS S3 endpoint region where the destination bucket exists."
	echoscreen "    Examples: eu-es, eu-de, us-east, us-south."
	echoscreen "  CURRACCOUNT|OTHERACCOUNT:"
	echoscreen "    COS account type. OTHERACCOUNT requires the same HMAC JSON file"
	echoscreen "    format as -imgimport - copy hmac_keys_example.json to a file"
	echoscreen "    outside this repository and fill in your keys."
	echoscreen "  HMAC_JSON_FILE:"
	echoscreen "    Optional; required only for OTHERACCOUNT."
}

usage_ji() {
	echoscreen "  WORKSPACE:"
	echoscreen "    PowerVS workspace (short or full name) whose last image import job"
	echoscreen "    to re-attach monitoring to. No image name needed - PowerVS tracks"
	echoscreen "    one import job per workspace."
}

usage_je() {
	echoscreen "  IMAGE_NAME:"
	echoscreen "    Name of the image (searched across every workspace) whose last"
	echoscreen "    export job to re-attach monitoring to."
}
#### END: usage_X() functions (Task 1 - more appended by later tasks) ####

```

- [ ] **Step 3: Rewrite the `-h | --help | -help)` block**

Replace:
```bash
   -h | --help | -help)
	help
	abort "`date +%Y-%m-%d_%H:%M:%S` - Help requested!!"
    ;;
```

With:
```bash
   -h | --help | -help)
	if [ $# -gt 2 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport_api.sh -h [-FLAG]" 1
	fi
	if [ $# -eq 2 ]
	then
		case "$2" in
			-j) usage_j ;;
			-a|-ta) usage_a ;;
			-x|-tx) usage_x ;;
			-imgdel) usage_imgdel ;;
			-imgimport) usage_imgimport ;;
			-imgexport) usage_imgexport ;;
			-ji) usage_ji ;;
			-je) usage_je ;;
			*)
				abort "`date +%Y-%m-%d_%H:%M:%S` - Unknown flag for detailed help: $2. Run bluexport_api.sh -h for the full command list." 1
				;;
		esac
		abort "`date +%Y-%m-%d_%H:%M:%S` - Detailed help for $2 shown above."
	fi
	help
	abort "`date +%Y-%m-%d_%H:%M:%S` - Help requested!!"
    ;;
```

(Tasks 2-6 each insert more `case "$2" in` arms right before the `*)` line above — never remove or reorder existing arms.)

- [ ] **Step 4: Wire `usage_j` into `-j`'s two argument-count checks**

Replace:
```bash
	if [ $# -lt 3 ]
	then
		echoscreen "Flag -j selected, but Arguments Missing!! Syntax: bluexport_api.sh -j VSI_NAME IMAGE_NAME"
		abort "`date +%Y-%m-%d_%H:%M:%S` - Flag -j selected, but Arguments Missing!! Syntax: bluexport_api.sh -j VSI_NAME IMAGE_NAME"
	fi
	if [ $# -gt 3 ]
	then
		echoscreen "Flag -j selected, but too many arguments!! Syntax: bluexport_api.sh -j VSI_NAME IMAGE_NAME"
		abort "`date +%Y-%m-%d_%H:%M:%S` - Flag -j selected, but too many arguments!! Syntax: bluexport_api.sh -j VSI_NAME IMAGE_NAME"
	fi
```

With:
```bash
	if [ $# -lt 3 ]
	then
		echoscreen "Flag -j selected, but Arguments Missing!! Syntax: bluexport_api.sh -j VSI_NAME IMAGE_NAME"
		usage_j
		abort "`date +%Y-%m-%d_%H:%M:%S` - Flag -j selected, but Arguments Missing!! Syntax: bluexport_api.sh -j VSI_NAME IMAGE_NAME"
	fi
	if [ $# -gt 3 ]
	then
		echoscreen "Flag -j selected, but too many arguments!! Syntax: bluexport_api.sh -j VSI_NAME IMAGE_NAME"
		usage_j
		abort "`date +%Y-%m-%d_%H:%M:%S` - Flag -j selected, but too many arguments!! Syntax: bluexport_api.sh -j VSI_NAME IMAGE_NAME"
	fi
```

- [ ] **Step 5: Wire `usage_a` into `-a | -ta`'s two argument-count checks**

Replace:
```bash
   -a | -ta)
	if [ $# -lt 5 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Arguments Missing!! Syntax: bluexport_api.sh $1 VSI_NAME IMAGE_NAME both|image-catalog|cloud-storage hourly|daily|weekly|monthly|single"
	fi
	if [ $# -gt 5 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport_api.sh $1 VSI_NAME IMAGE_NAME both|image-catalog|cloud-storage hourly|daily|weekly|monthly|single"
	fi
```

With:
```bash
   -a | -ta)
	if [ $# -lt 5 ]
	then
		usage_a
		abort "`date +%Y-%m-%d_%H:%M:%S` - Arguments Missing!! Syntax: bluexport_api.sh $1 VSI_NAME IMAGE_NAME both|image-catalog|cloud-storage hourly|daily|weekly|monthly|single"
	fi
	if [ $# -gt 5 ]
	then
		usage_a
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport_api.sh $1 VSI_NAME IMAGE_NAME both|image-catalog|cloud-storage hourly|daily|weekly|monthly|single"
	fi
```

- [ ] **Step 6: Wire `usage_x` into `-x | -tx`'s two argument-count checks**

Replace:
```bash
   -x | -tx)
	if [ $# -lt 6 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Arguments Missing!! Syntax: bluexport_api.sh $1 EXCLUDE_NAME VSI_NAME IMAGE_NAME both|image-catalog|cloud-storage hourly|daily|weekly|monthly|single"
	fi
	if [ $# -gt 6 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport_api.sh $1 EXCLUDE_NAME VSI_NAME IMAGE_NAME both|image-catalog|cloud-storage hourly|daily|weekly|monthly|single"
	fi
```

With:
```bash
   -x | -tx)
	if [ $# -lt 6 ]
	then
		usage_x
		abort "`date +%Y-%m-%d_%H:%M:%S` - Arguments Missing!! Syntax: bluexport_api.sh $1 EXCLUDE_NAME VSI_NAME IMAGE_NAME both|image-catalog|cloud-storage hourly|daily|weekly|monthly|single"
	fi
	if [ $# -gt 6 ]
	then
		usage_x
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport_api.sh $1 EXCLUDE_NAME VSI_NAME IMAGE_NAME both|image-catalog|cloud-storage hourly|daily|weekly|monthly|single"
	fi
```

- [ ] **Step 7: Wire `usage_imgdel`, `usage_imgimport`, `usage_imgexport`, `usage_ji`, `usage_je`**

Replace:
```bash
   -imgdel)
	if [ $# -ne 2 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many or too few arguments!! Syntax: bluexport_api.sh -imgdel IMG_NAME"
	fi
```

With:
```bash
   -imgdel)
	if [ $# -ne 2 ]
	then
		usage_imgdel
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many or too few arguments!! Syntax: bluexport_api.sh -imgdel IMG_NAME"
	fi
```

Replace:
```bash
   -imgimport)
	if [[ $# -lt 8 || $# -gt 9 ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many or too few arguments!! Syntax: bluexport_api.sh -imgimport IMGNAME BUCKET BUCKET_REGION WORKSPACE_TO_IMPORT IMGNAME_WS STORAGE_TYPE CURRACCOUNT|OTHERACCOUNT [HMAC_JSON_FILE]" 1
	fi
```

With:
```bash
   -imgimport)
	if [[ $# -lt 8 || $# -gt 9 ]]
	then
		usage_imgimport
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many or too few arguments!! Syntax: bluexport_api.sh -imgimport IMGNAME BUCKET BUCKET_REGION WORKSPACE_TO_IMPORT IMGNAME_WS STORAGE_TYPE CURRACCOUNT|OTHERACCOUNT [HMAC_JSON_FILE]" 1
	fi
```

Replace:
```bash
   -imgexport)
	if [[ $# -lt 5 || $# -gt 6 ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many or too few arguments!! Syntax: bluexport_api.sh -imgexport IMGNAME BUCKET BUCKET_REGION CURRACCOUNT|OTHERACCOUNT [HMAC_JSON_FILE]" 1
	fi
```

With:
```bash
   -imgexport)
	if [[ $# -lt 5 || $# -gt 6 ]]
	then
		usage_imgexport
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many or too few arguments!! Syntax: bluexport_api.sh -imgexport IMGNAME BUCKET BUCKET_REGION CURRACCOUNT|OTHERACCOUNT [HMAC_JSON_FILE]" 1
	fi
```

Replace:
```bash
   -ji)
	if [[ $# -ne 2 ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many or too few arguments!! Syntax: bluexport_api.sh -ji WORKSPACE" 1
	fi
```

With:
```bash
   -ji)
	if [[ $# -ne 2 ]]
	then
		usage_ji
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many or too few arguments!! Syntax: bluexport_api.sh -ji WORKSPACE" 1
	fi
```

Replace:
```bash
   -je)
	if [[ $# -ne 2 ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many or too few arguments!! Syntax: bluexport_api.sh -je IMAGE_NAME" 1
	fi
```

With:
```bash
   -je)
	if [[ $# -ne 2 ]]
	then
		usage_je
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many or too few arguments!! Syntax: bluexport_api.sh -je IMAGE_NAME" 1
	fi
```

- [ ] **Step 8: Syntax check**

Run: `bash -n bluexport_api.sh`
Expected: no output.

- [ ] **Step 9: Function-level test**

Create `/tmp/test_usage_group1.sh`:

```bash
#!/bin/bash
set -uo pipefail
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

REPO=/home/rqmartins/Git/bluexport_api
log_file="$WORKDIR/test.log"
: > "$log_file"

echoscreen() {
	echo "SCREEN: $1"
	if [[ "${2:-}" == "1" ]]; then echo "$1" >> "$log_file"; fi
}

for fn in usage_j usage_a usage_x usage_imgdel usage_imgimport usage_imgexport usage_ji usage_je; do
	source <(sed -n "/^${fn}() {/,/^}/p" "$REPO/bluexport_api.sh")
done

fail=0

echo "=== Case 1: usage_j prints VSI_NAME/IMAGE_NAME, writes nothing to log ==="
: > "$log_file"
out=$(usage_j)
if [[ "$out" == *"VSI_NAME"* && "$out" == *"IMAGE_NAME"* ]] && [[ ! -s "$log_file" ]]; then echo "PASS"; else echo "FAIL: out=$out log=$(cat "$log_file")"; fail=1; fi

echo "=== Case 2: usage_a mentions DESTINATION and RECURRENCE enums, writes nothing to log ==="
: > "$log_file"
out=$(usage_a)
if [[ "$out" == *"both|image-catalog|cloud-storage"* && "$out" == *"hourly|daily|weekly|monthly|single"* ]] && [[ ! -s "$log_file" ]]; then echo "PASS"; else echo "FAIL: out=$out"; fail=1; fi

echo "=== Case 3: usage_x mentions EXCLUDE_NAME, writes nothing to log ==="
: > "$log_file"
out=$(usage_x)
if [[ "$out" == *"EXCLUDE_NAME"* ]] && [[ ! -s "$log_file" ]]; then echo "PASS"; else echo "FAIL: out=$out"; fail=1; fi

echo "=== Case 4: usage_imgimport mentions all 7 params, writes nothing to log ==="
: > "$log_file"
out=$(usage_imgimport)
for p in IMGNAME BUCKET BUCKET_REGION WORKSPACE_TO_IMPORT IMGNAME_WS STORAGE_TYPE CURRACCOUNT; do
	if [[ "$out" != *"$p"* ]]; then echo "FAIL: missing $p in: $out"; fail=1; fi
done
[[ -s "$log_file" ]] && { echo "FAIL: log file was written to"; fail=1; }
[[ $fail -eq 0 ]] && echo "PASS"

echo "=== Case 5: usage_je mentions IMAGE_NAME, writes nothing to log ==="
: > "$log_file"
out=$(usage_je)
if [[ "$out" == *"IMAGE_NAME"* ]] && [[ ! -s "$log_file" ]]; then echo "PASS"; else echo "FAIL: out=$out"; fail=1; fi

if [[ $fail -eq 0 ]]; then echo "ALL PASS"; else echo "SOME TESTS FAILED"; exit 1; fi
```

Run: `bash /tmp/test_usage_group1.sh`
Expected: 5 `PASS` lines then `ALL PASS`.

- [ ] **Step 10: Structural wiring check**

Run this to confirm every error-path call site and the `-h -FLAG` dispatch entries are wired:

```bash
grep -c 'usage_j$\|usage_a$\|usage_x$\|usage_imgdel$\|usage_imgimport$\|usage_imgexport$\|usage_ji$\|usage_je$' bluexport_api.sh
```
Expected: at least 10 (2 call sites each for `-j`/`-a`/`-x`, 1 each for the other 5, plus the `-h -FLAG` dispatch's own references — exact count isn't the point, zero would mean the wiring didn't take).

```bash
grep -n 'usage_j ;;\|usage_a ;;\|usage_x ;;\|usage_imgdel ;;\|usage_imgimport ;;\|usage_imgexport ;;\|usage_ji ;;\|usage_je ;;' bluexport_api.sh
```
Expected: 8 lines (one per `case "$2" in` arm added in Step 3).

- [ ] **Step 11: Clean up the verification script**

Run: `rm -f /tmp/test_usage_group1.sh`

- [ ] **Step 12: Commit**

```bash
cd /home/rqmartins/Git/bluexport_api
git add bluexport_api.sh
git commit -m "$(cat <<'EOF'
Add usage_X() parameter detail for capture/export/job-monitor flags

Introduces the usage_<flag>() pattern: a small function per
argument-taking flag that echoscreen's (screen-only, never logged) a
per-parameter breakdown. Wired into two call sites - the flag's
existing argument-count-mismatch error (called immediately before the
existing abort(), which is otherwise untouched), and a new
"-h -FLAG" detailed-help mode inside the -h|--help|-help case block
(exit 0 on success, exit 1 on an unrecognized flag or extra arguments).

This task covers -j, -a/-ta, -x/-tx, -imgdel, -imgimport, -imgexport,
-ji, -je and establishes the -h -FLAG dispatch skeleton that later
tasks extend with their own flags.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: `bluexport_api.sh` — Snapshots group

**Files:**
- Modify: `bluexport_api.sh` — the usage_X() functions section (append); the `-h | --help | -help)` block's inner dispatch (append arms); the `-snapcr`, `-snapupd`, `-snapdel`, `-snapres` case blocks.

**Interfaces:**
- Consumes: the usage_X() functions section and `-h -FLAG` dispatch skeleton from Task 1 (already merged into `bluexport_api.sh`).
- Produces: `usage_snapcr()`, `usage_snapupd()`, `usage_snapdel()`, `usage_snapres()`.

- [ ] **Step 1: Confirm current line numbers**

Run: `grep -n '^#### END: usage_X() functions\|^  -snapcr)\|^  -snapupd)\|^  -snapdel)\|^  -snapres)\|usage_je) ;;\|\*)\s*$' bluexport_api.sh`

Read the four case blocks to confirm they still match the text below (line numbers will have shifted since Task 1).

- [ ] **Step 2: Append the new functions to the usage_X() section**

Insert immediately before the line `#### END: usage_X() functions (Task 1 - more appended by later tasks) ####`:

```bash
usage_snapcr() {
	echoscreen "  VSI_NAME:"
	echoscreen "    Name of the VSI to snapshot."
	echoscreen "  SNAPSHOT_NAME:"
	echoscreen "    Name for the new snapshot; must not already exist for this VSI."
	echoscreen "  DESCRIPTION:"
	echoscreen "    Optional. Pass 0 to omit, or a quoted description string."
	echoscreen "  VOLUMES:"
	echoscreen "    Optional. Pass 0 for all attached volumes, or a comma-separated"
	echoscreen "    list of volume names or IDs to snapshot only those."
}

usage_snapupd() {
	echoscreen "  SNAPSHOT_NAME:"
	echoscreen "    Name of the existing snapshot to update (searched across all"
	echoscreen "    workspaces)."
	echoscreen "  NEW_SNAPSHOT_NAME:"
	echoscreen "    Optional. Pass 0 to keep the current name, or a new name."
	echoscreen "  DESCRIPTION:"
	echoscreen "    Optional. Pass 0 to keep the current description, or a quoted"
	echoscreen "    new description."
	echoscreen "  At least one of NEW_SNAPSHOT_NAME/DESCRIPTION must differ from 0."
}

usage_snapdel() {
	echoscreen "  SNAPSHOT_NAME:"
	echoscreen "    Name of the snapshot to delete (searched across all workspaces)."
}

usage_snapres() {
	echoscreen "  VSI_NAME:"
	echoscreen "    VSI to restore the snapshot onto."
	echoscreen "  SNAPSHOT_NAME:"
	echoscreen "    Name of the snapshot to restore."
}

```

- [ ] **Step 3: Append entries to the `-h -FLAG` inner dispatch**

Replace:
```bash
			-je) usage_je ;;
			*)
				abort "`date +%Y-%m-%d_%H:%M:%S` - Unknown flag for detailed help: $2. Run bluexport_api.sh -h for the full command list." 1
				;;
```

With:
```bash
			-je) usage_je ;;
			-snapcr) usage_snapcr ;;
			-snapupd) usage_snapupd ;;
			-snapdel) usage_snapdel ;;
			-snapres) usage_snapres ;;
			*)
				abort "`date +%Y-%m-%d_%H:%M:%S` - Unknown flag for detailed help: $2. Run bluexport_api.sh -h for the full command list." 1
				;;
```

- [ ] **Step 4: Wire `usage_snapcr`**

Replace:
```bash
  -snapcr)
	# Args: VSI_NAME SNAPSHOT_NAME 0|"DESCRIPTION" 0|[VOLUMES (comma separated names or IDs)]
	if [ $# -lt 5 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments Missing!! Syntax: bluexport_api.sh $1 VSI_NAME SNAPSHOT_NAME 0|\"DESCRIPTION\" 0|\"VOL1,VOL2,...\""
	fi
	if [ $# -gt 5 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments!! Syntax: bluexport_api.sh $1 VSI_NAME SNAPSHOT_NAME 0|\"DESCRIPTION\" 0|\"VOL1,VOL2,...\""
	fi
```

With:
```bash
  -snapcr)
	# Args: VSI_NAME SNAPSHOT_NAME 0|"DESCRIPTION" 0|[VOLUMES (comma separated names or IDs)]
	if [ $# -lt 5 ]
	then
		usage_snapcr
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments Missing!! Syntax: bluexport_api.sh $1 VSI_NAME SNAPSHOT_NAME 0|\"DESCRIPTION\" 0|\"VOL1,VOL2,...\""
	fi
	if [ $# -gt 5 ]
	then
		usage_snapcr
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments!! Syntax: bluexport_api.sh $1 VSI_NAME SNAPSHOT_NAME 0|\"DESCRIPTION\" 0|\"VOL1,VOL2,...\""
	fi
```

- [ ] **Step 5: Wire `usage_snapupd`**

Replace:
```bash
  -snapupd)
	# Sintaxe: bluexport_api.sh -snapupd SNAPSHOT_NAME 0|[NEW_SNAPSHOT_NAME] 0|["DESCRIPTION"]
	if [ $# -lt 4 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments Missing!! Syntax: bluexport_api.sh $1 SNAPSHOT_NAME 0|[NEW_SNAPSHOT_NAME] 0|[\"DESCRIPTION\"]"
	fi
	if [ $# -gt 4 ]
	then
	abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments!! Syntax: bluexport_api.sh $1 SNAPSHOT_NAME 0|[NEW_SNAPSHOT_NAME] 0|[\"DESCRIPTION\"]"
	fi
```

With:
```bash
  -snapupd)
	# Sintaxe: bluexport_api.sh -snapupd SNAPSHOT_NAME 0|[NEW_SNAPSHOT_NAME] 0|["DESCRIPTION"]
	if [ $# -lt 4 ]
	then
		usage_snapupd
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments Missing!! Syntax: bluexport_api.sh $1 SNAPSHOT_NAME 0|[NEW_SNAPSHOT_NAME] 0|[\"DESCRIPTION\"]"
	fi
	if [ $# -gt 4 ]
	then
	usage_snapupd
	abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments!! Syntax: bluexport_api.sh $1 SNAPSHOT_NAME 0|[NEW_SNAPSHOT_NAME] 0|[\"DESCRIPTION\"]"
	fi
```

- [ ] **Step 6: Wire `usage_snapdel` and `usage_snapres`**

Replace:
```bash
  -snapdel)
	# Validate arguments
	if [ $# -lt 2 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments Missing!! Syntax: bluexport_api.sh $1 SNAPSHOT_NAME"
	fi
	if [ $# -gt 2 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments!! Syntax: bluexport_api.sh $1 SNAPSHOT_NAME"
	fi
```

With:
```bash
  -snapdel)
	# Validate arguments
	if [ $# -lt 2 ]
	then
		usage_snapdel
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments Missing!! Syntax: bluexport_api.sh $1 SNAPSHOT_NAME"
	fi
	if [ $# -gt 2 ]
	then
		usage_snapdel
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments!! Syntax: bluexport_api.sh $1 SNAPSHOT_NAME"
	fi
```

Replace:
```bash
  -snapres)
	# Syntax: bluexport_api.sh -snapres VSI_NAME SNAPSHOT_NAME
	if [ $# -lt 3 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments Missing!! Syntax: bluexport_api.sh $1 VSI_NAME SNAPSHOT_NAME"
	fi
	if [ $# -gt 3 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments!! Syntax: bluexport_api.sh $1 VSI_NAME SNAPSHOT_NAME"
	fi
```

With:
```bash
  -snapres)
	# Syntax: bluexport_api.sh -snapres VSI_NAME SNAPSHOT_NAME
	if [ $# -lt 3 ]
	then
		usage_snapres
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments Missing!! Syntax: bluexport_api.sh $1 VSI_NAME SNAPSHOT_NAME"
	fi
	if [ $# -gt 3 ]
	then
		usage_snapres
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments!! Syntax: bluexport_api.sh $1 VSI_NAME SNAPSHOT_NAME"
	fi
```

- [ ] **Step 7: Syntax check**

Run: `bash -n bluexport_api.sh`
Expected: no output.

- [ ] **Step 8: Function-level test**

Create `/tmp/test_usage_group2.sh`:

```bash
#!/bin/bash
set -uo pipefail
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT
REPO=/home/rqmartins/Git/bluexport_api
log_file="$WORKDIR/test.log"
: > "$log_file"
echoscreen() {
	echo "SCREEN: $1"
	if [[ "${2:-}" == "1" ]]; then echo "$1" >> "$log_file"; fi
}
for fn in usage_snapcr usage_snapupd usage_snapdel usage_snapres; do
	source <(sed -n "/^${fn}() {/,/^}/p" "$REPO/bluexport_api.sh")
done

fail=0

echo "=== Case 1: usage_snapcr mentions DESCRIPTION and VOLUMES optionality, no log write ==="
: > "$log_file"
out=$(usage_snapcr)
if [[ "$out" == *"Optional"* && "$out" == *"VOLUMES"* ]] && [[ ! -s "$log_file" ]]; then echo "PASS"; else echo "FAIL: out=$out"; fail=1; fi

echo "=== Case 2: usage_snapupd mentions both optional fields, no log write ==="
: > "$log_file"
out=$(usage_snapupd)
if [[ "$out" == *"NEW_SNAPSHOT_NAME"* && "$out" == *"DESCRIPTION"* ]] && [[ ! -s "$log_file" ]]; then echo "PASS"; else echo "FAIL: out=$out"; fail=1; fi

echo "=== Case 3: usage_snapdel mentions SNAPSHOT_NAME, no log write ==="
: > "$log_file"
out=$(usage_snapdel)
if [[ "$out" == *"SNAPSHOT_NAME"* ]] && [[ ! -s "$log_file" ]]; then echo "PASS"; else echo "FAIL: out=$out"; fail=1; fi

echo "=== Case 4: usage_snapres mentions VSI_NAME and SNAPSHOT_NAME, no log write ==="
: > "$log_file"
out=$(usage_snapres)
if [[ "$out" == *"VSI_NAME"* && "$out" == *"SNAPSHOT_NAME"* ]] && [[ ! -s "$log_file" ]]; then echo "PASS"; else echo "FAIL: out=$out"; fail=1; fi

if [[ $fail -eq 0 ]]; then echo "ALL PASS"; else echo "SOME TESTS FAILED"; exit 1; fi
```

Run: `bash /tmp/test_usage_group2.sh`
Expected: 4 `PASS` lines then `ALL PASS`.

- [ ] **Step 9: Structural wiring check**

Run: `grep -n 'usage_snapcr ;;\|usage_snapupd ;;\|usage_snapdel ;;\|usage_snapres ;;' bluexport_api.sh`
Expected: 4 lines (the new `-h -FLAG` dispatch arms).

- [ ] **Step 10: Clean up the verification script**

Run: `rm -f /tmp/test_usage_group2.sh`

- [ ] **Step 11: Commit**

```bash
cd /home/rqmartins/Git/bluexport_api
git add bluexport_api.sh
git commit -m "$(cat <<'EOF'
Add usage_X() parameter detail for snapshot flags

Covers -snapcr, -snapupd, -snapdel, -snapres. Same pattern as the
capture/export group (Task 1): usage_X() called before the existing
argument-count abort(), plus a -h -FLAG dispatch entry.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: `bluexport_api.sh` — Volume-Clone-and-Tier group

**Files:**
- Modify: `bluexport_api.sh` — usage_X() section (append); `-h -FLAG` dispatch (append); the `-vclone`, `-vclonedel`, `-vchtier`, `-insvchtier` case blocks.

**Interfaces:**
- Consumes: Task 1's skeleton (merged).
- Produces: `usage_vclone()`, `usage_vclonedel()`, `usage_vchtier()`, `usage_insvchtier()`.

- [ ] **Step 1: Confirm current line numbers**

Run: `grep -n '^#### END: usage_X() functions\|^  -vclone)\|^  -vclonedel)\|^  -vchtier)\|^  -insvchtier)\|-snapres) usage_snapres ;;' bluexport_api.sh`

Read the four case blocks to confirm the text below still matches.

- [ ] **Step 2: Append the new functions**

Insert immediately before `#### END: usage_X() functions (Task 1 - more appended by later tasks) ####`:

```bash
usage_vclone() {
	echoscreen "  REQUEST_CLONE_NAME:"
	echoscreen "    Name for the new volume clone request; must not already exist."
	echoscreen "  VOLUME_BASE_NAME:"
	echoscreen "    Common name/prefix used to label the cloned volumes."
	echoscreen "  LPAR_NAME:"
	echoscreen "    VSI that owns the source volumes to clone."
	echoscreen "  REPLICATION:"
	echoscreen "    True|False - whether to enable replication on the clone."
	echoscreen "  ROLLBACK:"
	echoscreen "    True|False - whether to prepare the clone for rollback."
	echoscreen "  TARGET_TIER:"
	echoscreen "    tier0|tier1|tier3|tier5k. (Unlike -vchtier's TIER_TO_CHANGE_TO,"
	echoscreen "    this DOES need the \"tier\" prefix.)"
	echoscreen "  VOLUMES:"
	echoscreen "    ALL for every volume attached to LPAR_NAME, or a comma-separated"
	echoscreen "    list of volume names to clone only those (at least 2 required)."
}

usage_vclonedel() {
	echoscreen "  REQUEST_CLONE_NAME:"
	echoscreen "    Name of the volume clone request to delete (searched across all"
	echoscreen "    workspaces)."
	echoscreen "  MODE:"
	echoscreen "    Optional (defaults to 0). Pass 0 to delete only the clone request,"
	echoscreen "    or delete_volumes to also delete the cloned volumes themselves."
}

usage_vchtier() {
	echoscreen "  VSI_NAME:"
	echoscreen "    VSI that owns the volumes to change tier."
	echoscreen "  VOLUMES_NAME:"
	echoscreen "    Common name/pattern (space-separated if more than one) matched"
	echoscreen "    against volume names attached to VSI_NAME."
	echoscreen "  TIER_TO_CHANGE_TO:"
	echoscreen "    0|1|3|5k - the script prepends \"tier\" automatically."
	echoscreen "    (Note: unlike -vclone's TARGET_TIER, do NOT include the \"tier\""
	echoscreen "    prefix yourself here.)"
}

usage_insvchtier() {
	echoscreen "  VSI_NAME:"
	echoscreen "    VSI whose ALL attached volumes will change tier."
	echoscreen "  TIER_TO_CHANGE_TO:"
	echoscreen "    0|1|3|5k - the script prepends \"tier\" automatically, same as"
	echoscreen "    -vchtier (see that flag's note about the prefix)."
}

```

- [ ] **Step 3: Append entries to the `-h -FLAG` inner dispatch**

Replace:
```bash
			-snapres) usage_snapres ;;
			*)
				abort "`date +%Y-%m-%d_%H:%M:%S` - Unknown flag for detailed help: $2. Run bluexport_api.sh -h for the full command list." 1
				;;
```

With:
```bash
			-snapres) usage_snapres ;;
			-vclone) usage_vclone ;;
			-vclonedel) usage_vclonedel ;;
			-vchtier) usage_vchtier ;;
			-insvchtier) usage_insvchtier ;;
			*)
				abort "`date +%Y-%m-%d_%H:%M:%S` - Unknown flag for detailed help: $2. Run bluexport_api.sh -h for the full command list." 1
				;;
```

- [ ] **Step 4: Wire `usage_vclone`**

Replace:
```bash
  -vclone)
	# Args: REQUEST_CLONE_NAME VOLUME_BASE_NAME LPAR_NAME Replication(True|False) Rollback(True|False) TARGET_TIER volumes(ALL|id1,id2,...)
	if [ $# -lt 8 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments Missing!! Syntax: bluexport_api.sh $1 REQUEST_CLONE_NAME VOLUME_BASE_NAME LPAR_NAME True|False(replication-enabled) True|False(rollback-prepare) tier0|tier1|tier3|tier5k ALL|\"VOL1,VOL2,...\""
	fi
	if [ $# -gt 8 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments!! Syntax: bluexport_api.sh $1 REQUEST_CLONE_NAME VOLUME_BASE_NAME LPAR_NAME True|False(replication-enabled) True|False(rollback-prepare) tier0|tier1|tier3|tier5k ALL|\"VOL1,VOL2,...\""
	fi
```

With:
```bash
  -vclone)
	# Args: REQUEST_CLONE_NAME VOLUME_BASE_NAME LPAR_NAME Replication(True|False) Rollback(True|False) TARGET_TIER volumes(ALL|id1,id2,...)
	if [ $# -lt 8 ]
	then
		usage_vclone
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments Missing!! Syntax: bluexport_api.sh $1 REQUEST_CLONE_NAME VOLUME_BASE_NAME LPAR_NAME True|False(replication-enabled) True|False(rollback-prepare) tier0|tier1|tier3|tier5k ALL|\"VOL1,VOL2,...\""
	fi
	if [ $# -gt 8 ]
	then
		usage_vclone
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments!! Syntax: bluexport_api.sh $1 REQUEST_CLONE_NAME VOLUME_BASE_NAME LPAR_NAME True|False(replication-enabled) True|False(rollback-prepare) tier0|tier1|tier3|tier5k ALL|\"VOL1,VOL2,...\""
	fi
```

- [ ] **Step 5: Wire `usage_vclonedel`**

Replace:
```bash
  -vclonedel)
	# Syntax: bluexport_api.sh -vclonedel REQUEST_CLONE_NAME 0|delete_volumes
	if [ $# -lt 2 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Arguments Missing!! Syntax: bluexport_api.sh $1 REQUEST_CLONE_NAME 0|delete_volumes"
	fi
	if [ $# -gt 3 ]
	then
	abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport_api.sh $1 REQUEST_CLONE_NAME 0|delete_volumes"
	fi
```

With:
```bash
  -vclonedel)
	# Syntax: bluexport_api.sh -vclonedel REQUEST_CLONE_NAME 0|delete_volumes
	if [ $# -lt 2 ]
	then
		usage_vclonedel
		abort "`date +%Y-%m-%d_%H:%M:%S` - Arguments Missing!! Syntax: bluexport_api.sh $1 REQUEST_CLONE_NAME 0|delete_volumes"
	fi
	if [ $# -gt 3 ]
	then
	usage_vclonedel
	abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport_api.sh $1 REQUEST_CLONE_NAME 0|delete_volumes"
	fi
```

- [ ] **Step 6: Wire `usage_vchtier` and `usage_insvchtier`**

Replace:
```bash
	if [ $# -lt 4 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments missing! Syntax: bluexport_api.sh $1 VSI_NAME VOLUMES_NAME TIER_TO_CHANGE_TO"
	fi
	if [ $# -gt 4 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments! Syntax: bluexport_api.sh $1 VSI_NAME VOLUMES_NAME TIER_TO_CHANGE_TO"
	fi
```

With:
```bash
	if [ $# -lt 4 ]
	then
		usage_vchtier
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments missing! Syntax: bluexport_api.sh $1 VSI_NAME VOLUMES_NAME TIER_TO_CHANGE_TO"
	fi
	if [ $# -gt 4 ]
	then
		usage_vchtier
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments! Syntax: bluexport_api.sh $1 VSI_NAME VOLUMES_NAME TIER_TO_CHANGE_TO"
	fi
```

Replace:
```bash
	if [ $# -lt 3 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments missing! Syntax: bluexport_api.sh $1 VSI_NAME TIER_TO_CHANGE_TO"
	fi
	if [ $# -gt 3 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments! Syntax: bluexport_api.sh $1 VSI_NAME TIER_TO_CHANGE_TO"
	fi
```

With:
```bash
	if [ $# -lt 3 ]
	then
		usage_insvchtier
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments missing! Syntax: bluexport_api.sh $1 VSI_NAME TIER_TO_CHANGE_TO"
	fi
	if [ $# -gt 3 ]
	then
		usage_insvchtier
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments! Syntax: bluexport_api.sh $1 VSI_NAME TIER_TO_CHANGE_TO"
	fi
```

**Note for the implementer:** `-vchtier`'s and `-insvchtier`'s arg-count blocks look textually similar (both are "VSI_NAME ... TIER_TO_CHANGE_TO" shaped) but have different variable counts (4 vs 3) and different flag names in their Syntax text — use the surrounding case label (`-vchtier)` at the block starting with `tier="tier$4"`, `-insvchtier)` at the block starting with `tier="tier$3"`) to confirm you're editing the right one; do not use `replace_all`.

- [ ] **Step 7: Syntax check**

Run: `bash -n bluexport_api.sh`
Expected: no output.

- [ ] **Step 8: Function-level test**

Create `/tmp/test_usage_group3.sh`:

```bash
#!/bin/bash
set -uo pipefail
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT
REPO=/home/rqmartins/Git/bluexport_api
log_file="$WORKDIR/test.log"
: > "$log_file"
echoscreen() {
	echo "SCREEN: $1"
	if [[ "${2:-}" == "1" ]]; then echo "$1" >> "$log_file"; fi
}
for fn in usage_vclone usage_vclonedel usage_vchtier usage_insvchtier; do
	source <(sed -n "/^${fn}() {/,/^}/p" "$REPO/bluexport_api.sh")
done

fail=0

echo "=== Case 1: usage_vclone's TARGET_TIER is prefixed (tier0|tier1|...), no log write ==="
: > "$log_file"
out=$(usage_vclone)
if [[ "$out" == *"tier0|tier1|tier3|tier5k"* ]] && [[ ! -s "$log_file" ]]; then echo "PASS"; else echo "FAIL: out=$out"; fail=1; fi

echo "=== Case 2: usage_vchtier's TIER_TO_CHANGE_TO is the bare-digit convention (0|1|3|5k), no log write ==="
: > "$log_file"
out=$(usage_vchtier)
if [[ "$out" == *"0|1|3|5k"* ]] && [[ ! -s "$log_file" ]]; then echo "PASS"; else echo "FAIL: out=$out"; fail=1; fi

echo "=== Case 3: usage_insvchtier also documents the bare-digit convention, no log write ==="
: > "$log_file"
out=$(usage_insvchtier)
if [[ "$out" == *"0|1|3|5k"* ]] && [[ ! -s "$log_file" ]]; then echo "PASS"; else echo "FAIL: out=$out"; fail=1; fi

echo "=== Case 4: usage_vclonedel mentions delete_volumes, no log write ==="
: > "$log_file"
out=$(usage_vclonedel)
if [[ "$out" == *"delete_volumes"* ]] && [[ ! -s "$log_file" ]]; then echo "PASS"; else echo "FAIL: out=$out"; fail=1; fi

if [[ $fail -eq 0 ]]; then echo "ALL PASS"; else echo "SOME TESTS FAILED"; exit 1; fi
```

Run: `bash /tmp/test_usage_group3.sh`
Expected: 4 `PASS` lines then `ALL PASS`.

- [ ] **Step 9: Structural wiring check**

Run: `grep -n 'usage_vclone ;;\|usage_vclonedel ;;\|usage_vchtier ;;\|usage_insvchtier ;;' bluexport_api.sh`
Expected: 4 lines.

- [ ] **Step 10: Clean up the verification script**

Run: `rm -f /tmp/test_usage_group3.sh`

- [ ] **Step 11: Commit**

```bash
cd /home/rqmartins/Git/bluexport_api
git add bluexport_api.sh
git commit -m "$(cat <<'EOF'
Add usage_X() parameter detail for volume-clone-and-tier flags

Covers -vclone, -vclonedel, -vchtier, -insvchtier. usage_vclone() and
usage_vchtier() each explicitly flag the pre-existing tier-prefix
inconsistency between the two flags (bare 0|1|3|5k for -vchtier /
-insvchtier vs already-prefixed tier0|tier1|... for -vclone), and
usage_vclone() documents VOLUMES as taking names (not the stale
"IDs" wording in a nearby code comment).

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: `bluexport_api.sh` — GRS-Replication group

**Files:**
- Modify: `bluexport_api.sh` — usage_X() section (append); `-h -FLAG` dispatch (append); the `-creategrs`, `-deletegrs`, `-grsfailover`, `-grscancelfailover`, `-grsfailback`, `-grsreversereplica` case blocks.

**Interfaces:**
- Consumes: Task 1's skeleton (merged).
- Produces: `usage_creategrs()`, `usage_deletegrs()`, `usage_grsfailover()`, `usage_grscancelfailover()`, `usage_grsfailback()`, `usage_grsreversereplica()`.

- [ ] **Step 1: Confirm current line numbers**

Run: `grep -n '^#### END: usage_X() functions\|^   -creategrs)\|^  -deletegrs)\|^  -grsfailover)\|^  -grscancelfailover)\|^  -grsfailback)\|^  -grsreversereplica)\|-insvchtier) usage_insvchtier ;;' bluexport_api.sh`

Read all six case blocks to confirm the text below still matches.

- [ ] **Step 2: Append the new functions**

Insert immediately before `#### END: usage_X() functions (Task 1 - more appended by later tasks) ####`:

```bash
usage_creategrs() {
	echoscreen "  SOURCE_VSI:"
	echoscreen "    VSI whose volumes are the replication source."
	echoscreen "  TARGET_VSI:"
	echoscreen "    VSI that will receive the replicated volumes."
	echoscreen "  VG_NAME:"
	echoscreen "    Name for the new volume group (replication group)."
	echoscreen "  SOURCE_VOLUMES_NAME:"
	echoscreen "    Common name/prefix matched against SOURCE_VSI's volume names to"
	echoscreen "    select which volumes join the replication group."
	echoscreen "  Fails if any selected source volume already has a snapshot -"
	echoscreen "  delete those snapshots first."
}

usage_deletegrs() {
	echoscreen "  SOURCE_VSI:"
	echoscreen "    VSI on the source side of the replication group."
	echoscreen "  TARGET_VSI:"
	echoscreen "    VSI on the target side of the replication group."
	echoscreen "  VG_NAME:"
	echoscreen "    Name of the volume group (replication group) to delete."
	echoscreen "  SOURCE_VOLUME_NAMES:"
	echoscreen "    Common name/prefix matched against SOURCE_VSI's volume names -"
	echoscreen "    same value used when the group was created with -creategrs (also"
	echoscreen "    used to match the corresponding volumes on the target side)."
}

usage_grsfailover() {
	echoscreen "  SOURCE_VSI:"
	echoscreen "    VSI on the source side of the replication group."
	echoscreen "  VG_NAME:"
	echoscreen "    Name of the volume group to fail over."
	echoscreen "  MODE:"
	echoscreen "    NO_ATTACH|ATTACH - whether to also attach the failed-over volumes"
	echoscreen "    to a VSI immediately."
	echoscreen "  TARGET_VSI:"
	echoscreen "    Required only when MODE=ATTACH; VSI to attach the volumes to."
}

usage_grscancelfailover() {
	echoscreen "  SOURCE_VSI:"
	echoscreen "    VSI on the source side of the replication group."
	echoscreen "  VG_NAME:"
	echoscreen "    Name of the volume group to cancel failover on."
	echoscreen "  MODE:"
	echoscreen "    NO_DETACH|DETACH - whether to also detach the volumes from"
	echoscreen "    TARGET_VSI before cancelling."
	echoscreen "  TARGET_VSI:"
	echoscreen "    VSI the failed-over volumes are currently attached to."
}

usage_grsfailback() {
	echoscreen "  SOURCE_VSI:"
	echoscreen "    VSI on the source side of the replication group."
	echoscreen "  TARGET_VSI:"
	echoscreen "    VSI on the target side of the replication group."
	echoscreen "  VG_NAME:"
	echoscreen "    Name of the volume group to fail back to the source."
}

usage_grsreversereplica() {
	echoscreen "  SOURCE_VSI:"
	echoscreen "    VSI currently on the source side of the replication group."
	echoscreen "  TARGET_VSI:"
	echoscreen "    VSI currently on the target side of the replication group."
	echoscreen "  VG_NAME:"
	echoscreen "    Name of the volume group whose replication direction to reverse."
}

```

- [ ] **Step 3: Append entries to the `-h -FLAG` inner dispatch**

Replace:
```bash
			-insvchtier) usage_insvchtier ;;
			*)
				abort "`date +%Y-%m-%d_%H:%M:%S` - Unknown flag for detailed help: $2. Run bluexport_api.sh -h for the full command list." 1
				;;
```

With:
```bash
			-insvchtier) usage_insvchtier ;;
			-creategrs) usage_creategrs ;;
			-deletegrs) usage_deletegrs ;;
			-grsfailover) usage_grsfailover ;;
			-grscancelfailover) usage_grscancelfailover ;;
			-grsfailback) usage_grsfailback ;;
			-grsreversereplica) usage_grsreversereplica ;;
			*)
				abort "`date +%Y-%m-%d_%H:%M:%S` - Unknown flag for detailed help: $2. Run bluexport_api.sh -h for the full command list." 1
				;;
```

- [ ] **Step 4: Wire `usage_creategrs`**

Replace:
```bash
   -creategrs)
	# Syntax: bluexport_api.sh -creategrs SOURCE_VSI TARGET_VSI VG_NAME SOURCE_VOLUMES_NAME
	if [ $# -lt 5 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Arguments Missing!! Syntax: bluexport_api.sh $1 SOURCE_VSI TARGET_VSI VG_NAME SOURCE_VOLUMES_NAME"
	fi
	if [ $# -gt 5 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport_api.sh $1 SOURCE_VSI TARGET_VSI VG_NAME SOURCE_VOLUMES_NAME"
	fi
```

With:
```bash
   -creategrs)
	# Syntax: bluexport_api.sh -creategrs SOURCE_VSI TARGET_VSI VG_NAME SOURCE_VOLUMES_NAME
	if [ $# -lt 5 ]
	then
		usage_creategrs
		abort "`date +%Y-%m-%d_%H:%M:%S` - Arguments Missing!! Syntax: bluexport_api.sh $1 SOURCE_VSI TARGET_VSI VG_NAME SOURCE_VOLUMES_NAME"
	fi
	if [ $# -gt 5 ]
	then
		usage_creategrs
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport_api.sh $1 SOURCE_VSI TARGET_VSI VG_NAME SOURCE_VOLUMES_NAME"
	fi
```

- [ ] **Step 5: Wire `usage_deletegrs`**

Replace:
```bash
  -deletegrs)
	# Syntax: bluexport_api.sh -deletegrs SOURCE_VSI TARGET_VSI VG_NAME SOURCE_VOLUME_NAMES
	if [ $# -lt 5 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments Missing!! Syntax: bluexport_api.sh $1 SOURCE_VSI TARGET_VSI VG_NAME SOURCE_VOLUME_NAMES"
	fi
	if [ $# -gt 5 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments!! Syntax: bluexport_api.sh $1 SOURCE_VSI TARGET_VSI VG_NAME SOURCE_VOLUME_NAMES"
	fi
```

With:
```bash
  -deletegrs)
	# Syntax: bluexport_api.sh -deletegrs SOURCE_VSI TARGET_VSI VG_NAME SOURCE_VOLUME_NAMES
	if [ $# -lt 5 ]
	then
		usage_deletegrs
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments Missing!! Syntax: bluexport_api.sh $1 SOURCE_VSI TARGET_VSI VG_NAME SOURCE_VOLUME_NAMES"
	fi
	if [ $# -gt 5 ]
	then
		usage_deletegrs
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments!! Syntax: bluexport_api.sh $1 SOURCE_VSI TARGET_VSI VG_NAME SOURCE_VOLUME_NAMES"
	fi
```

- [ ] **Step 6: Wire `usage_grsfailover`**

Replace:
```bash
  -grsfailover)
	# Syntax: bluexport_api.sh -grsfailover SOURCE_VSI VG_NAME NO_ATTACH|ATTACH [TARGET_VSI]
	if [ $# -lt 4 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments Missing!! Syntax: bluexport_api.sh $1 SOURCE_VSI VG_NAME NO_ATTACH|ATTACH [TARGET_VSI]"
	fi
	if [ $# -gt 5 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments!! Syntax: bluexport_api.sh $1 SOURCE_VSI VG_NAME NO_ATTACH|ATTACH [TARGET_VSI]"
	fi
```

With:
```bash
  -grsfailover)
	# Syntax: bluexport_api.sh -grsfailover SOURCE_VSI VG_NAME NO_ATTACH|ATTACH [TARGET_VSI]
	if [ $# -lt 4 ]
	then
		usage_grsfailover
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments Missing!! Syntax: bluexport_api.sh $1 SOURCE_VSI VG_NAME NO_ATTACH|ATTACH [TARGET_VSI]"
	fi
	if [ $# -gt 5 ]
	then
		usage_grsfailover
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments!! Syntax: bluexport_api.sh $1 SOURCE_VSI VG_NAME NO_ATTACH|ATTACH [TARGET_VSI]"
	fi
```

(This flag also has a third, conditional check for `attach_mode == "ATTACH"` requiring exactly 5 args — leave that one untouched; it is a semantic validation, not the generic argument-count check this plan targets.)

- [ ] **Step 7: Wire `usage_grscancelfailover`, `usage_grsfailback`, `usage_grsreversereplica`**

These three each have a single combined `-ne` check (not a `-lt`/`-gt` pair) — one `usage_X` insertion each.

Replace:
```bash
  -grscancelfailover)
	# Syntax: bluexport_api.sh -grscancelfailover SOURCE_VSI VG_NAME NO_DETACH|DETACH TARGET_VSI
	if [ $# -ne 5 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments Missing/Invalid!! Syntax: bluexport_api.sh $1 SOURCE_VSI VG_NAME NO_DETACH|DETACH TARGET_VSI"
	fi
```

With:
```bash
  -grscancelfailover)
	# Syntax: bluexport_api.sh -grscancelfailover SOURCE_VSI VG_NAME NO_DETACH|DETACH TARGET_VSI
	if [ $# -ne 5 ]
	then
		usage_grscancelfailover
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments Missing/Invalid!! Syntax: bluexport_api.sh $1 SOURCE_VSI VG_NAME NO_DETACH|DETACH TARGET_VSI"
	fi
```

Replace:
```bash
  -grsfailback)
	# Syntax: bluexport_api.sh -grsfailback SOURCE_VSI TARGET_VSI VG_NAME
	if [ $# -ne 4 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments Missing/Invalid!! Syntax: bluexport_api.sh $1 SOURCE_VSI TARGET_VSI VG_NAME"
	fi
```

With:
```bash
  -grsfailback)
	# Syntax: bluexport_api.sh -grsfailback SOURCE_VSI TARGET_VSI VG_NAME
	if [ $# -ne 4 ]
	then
		usage_grsfailback
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments Missing/Invalid!! Syntax: bluexport_api.sh $1 SOURCE_VSI TARGET_VSI VG_NAME"
	fi
```

Replace:
```bash
  -grsreversereplica)
	# Syntax: bluexport_api.sh -grsreversereplica SOURCE_VSI TARGET_VSI VG_NAME
	if [ $# -ne 4 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments Missing/Invalid!! Syntax: bluexport_api.sh $1 SOURCE_VSI TARGET_VSI VG_NAME"
	fi
```

With:
```bash
  -grsreversereplica)
	# Syntax: bluexport_api.sh -grsreversereplica SOURCE_VSI TARGET_VSI VG_NAME
	if [ $# -ne 4 ]
	then
		usage_grsreversereplica
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments Missing/Invalid!! Syntax: bluexport_api.sh $1 SOURCE_VSI TARGET_VSI VG_NAME"
	fi
```

- [ ] **Step 8: Syntax check**

Run: `bash -n bluexport_api.sh`
Expected: no output.

- [ ] **Step 9: Function-level test**

Create `/tmp/test_usage_group4.sh`:

```bash
#!/bin/bash
set -uo pipefail
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT
REPO=/home/rqmartins/Git/bluexport_api
log_file="$WORKDIR/test.log"
: > "$log_file"
echoscreen() {
	echo "SCREEN: $1"
	if [[ "${2:-}" == "1" ]]; then echo "$1" >> "$log_file"; fi
}
for fn in usage_creategrs usage_deletegrs usage_grsfailover usage_grscancelfailover usage_grsfailback usage_grsreversereplica; do
	source <(sed -n "/^${fn}() {/,/^}/p" "$REPO/bluexport_api.sh")
done

fail=0

echo "=== Case 1: usage_creategrs mentions SOURCE_VOLUMES_NAME, no log write ==="
: > "$log_file"
out=$(usage_creategrs)
if [[ "$out" == *"SOURCE_VOLUMES_NAME"* ]] && [[ ! -s "$log_file" ]]; then echo "PASS"; else echo "FAIL: out=$out"; fail=1; fi

echo "=== Case 2: usage_grsfailover mentions NO_ATTACH|ATTACH and conditional TARGET_VSI, no log write ==="
: > "$log_file"
out=$(usage_grsfailover)
if [[ "$out" == *"NO_ATTACH|ATTACH"* && "$out" == *"Required only when MODE=ATTACH"* ]] && [[ ! -s "$log_file" ]]; then echo "PASS"; else echo "FAIL: out=$out"; fail=1; fi

echo "=== Case 3: usage_grscancelfailover mentions NO_DETACH|DETACH, no log write ==="
: > "$log_file"
out=$(usage_grscancelfailover)
if [[ "$out" == *"NO_DETACH|DETACH"* ]] && [[ ! -s "$log_file" ]]; then echo "PASS"; else echo "FAIL: out=$out"; fail=1; fi

echo "=== Case 4: usage_grsfailback and usage_grsreversereplica both mention VG_NAME, no log write ==="
: > "$log_file"
out1=$(usage_grsfailback)
out2=$(usage_grsreversereplica)
if [[ "$out1" == *"VG_NAME"* && "$out2" == *"VG_NAME"* ]] && [[ ! -s "$log_file" ]]; then echo "PASS"; else echo "FAIL: out1=$out1 out2=$out2"; fail=1; fi

if [[ $fail -eq 0 ]]; then echo "ALL PASS"; else echo "SOME TESTS FAILED"; exit 1; fi
```

Run: `bash /tmp/test_usage_group4.sh`
Expected: 4 `PASS` lines then `ALL PASS`.

- [ ] **Step 10: Structural wiring check**

Run: `grep -n 'usage_creategrs ;;\|usage_deletegrs ;;\|usage_grsfailover ;;\|usage_grscancelfailover ;;\|usage_grsfailback ;;\|usage_grsreversereplica ;;' bluexport_api.sh`
Expected: 6 lines.

- [ ] **Step 11: Clean up the verification script**

Run: `rm -f /tmp/test_usage_group4.sh`

- [ ] **Step 12: Commit**

```bash
cd /home/rqmartins/Git/bluexport_api
git add bluexport_api.sh
git commit -m "$(cat <<'EOF'
Add usage_X() parameter detail for GRS replication flags

Covers -creategrs, -deletegrs, -grsfailover, -grscancelfailover,
-grsfailback, -grsreversereplica.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: `bluexport_api.sh` — VSI-Operations group

**Files:**
- Modify: `bluexport_api.sh` — usage_X() section (append); `-h -FLAG` dispatch (append); the `-vsistart`, `-vsioper`, `-vsitask`, `-vsisrcmon`, `-attachvolumes`, `-detachvolumes` case blocks.

**Interfaces:**
- Consumes: Task 1's skeleton (merged).
- Produces: `usage_vsistart()`, `usage_vsioper()`, `usage_vsitask()`, `usage_vsisrcmon()`, `usage_attachvolumes()`, `usage_detachvolumes()`.

- [ ] **Step 1: Confirm current line numbers**

Run: `grep -n '^#### END: usage_X() functions\|^   -vsistart)\|^   -vsioper)\|^   -vsitask)\|^   -vsisrcmon)\|^   -attachvolumes)\|^   -detachvolumes)\|-grsreversereplica) usage_grsreversereplica ;;' bluexport_api.sh`

Read all six case blocks to confirm the text below still matches.

- [ ] **Step 2: Append the new functions**

Insert immediately before `#### END: usage_X() functions (Task 1 - more appended by later tasks) ####`:

```bash
usage_vsistart() {
	echoscreen "  VSI_NAME:"
	echoscreen "    Name of the VSI to start."
}

usage_vsioper() {
	echoscreen "  VSI_NAME:"
	echoscreen "    Name of the VSI to change boot/operating mode for."
	echoscreen "  BOOT_MODE:"
	echoscreen "    a|b|c|d."
	echoscreen "  OPERATING_MODE:"
	echoscreen "    normal|manual."
}

usage_vsitask() {
	echoscreen "  VSI_NAME:"
	echoscreen "    Name of the VSI to run the task on."
	echoscreen "  TASK:"
	echoscreen "    dston|retrydump|consoleservice|iopreset|remotedstoff|remotedston|"
	echoscreen "    iopdump|dumprestart."
}

usage_vsisrcmon() {
	echoscreen "  VSI_NAME:"
	echoscreen "    Name of the VSI whose SRC (reference code) to monitor."
	echoscreen "  MODE:"
	echoscreen "    START|SHUTOFF - which state transition to wait for."
}

usage_attachvolumes() {
	echoscreen "  VOLUMES_COMMON_NAME:"
	echoscreen "    Common name/pattern matched against existing volume names -"
	echoscreen "    every match gets attached."
	echoscreen "  VSI_NAME:"
	echoscreen "    Target VSI to attach the volumes to; must be SHUTOFF."
}

usage_detachvolumes() {
	echoscreen "  VSI_NAME:"
	echoscreen "    VSI to detach ALL currently attached volumes from."
}

```

- [ ] **Step 3: Append entries to the `-h -FLAG` inner dispatch**

Replace:
```bash
			-grsreversereplica) usage_grsreversereplica ;;
			*)
				abort "`date +%Y-%m-%d_%H:%M:%S` - Unknown flag for detailed help: $2. Run bluexport_api.sh -h for the full command list." 1
				;;
```

With:
```bash
			-grsreversereplica) usage_grsreversereplica ;;
			-vsistart) usage_vsistart ;;
			-vsioper) usage_vsioper ;;
			-vsitask) usage_vsitask ;;
			-vsisrcmon) usage_vsisrcmon ;;
			-attachvolumes) usage_attachvolumes ;;
			-detachvolumes) usage_detachvolumes ;;
			*)
				abort "`date +%Y-%m-%d_%H:%M:%S` - Unknown flag for detailed help: $2. Run bluexport_api.sh -h for the full command list." 1
				;;
```

- [ ] **Step 4: Wire all six flags (each has a single `-ne` check)**

Replace:
```bash
   -vsistart)
	if [ $# -ne 2 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many or too few arguments!! Syntax: bluexport_api.sh -vsistart VSI_NAME"
	fi
```

With:
```bash
   -vsistart)
	if [ $# -ne 2 ]
	then
		usage_vsistart
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many or too few arguments!! Syntax: bluexport_api.sh -vsistart VSI_NAME"
	fi
```

Replace:
```bash
   -vsioper)
	# Syntax: -vsioper VSI_NAME BOOT_MODE OPERATING_MODE
	if [ $# -ne 4 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many or too few arguments!! Syntax: bluexport_api.sh -vsioper VSI_NAME BOOT_MODE OPERATING_MODE. BOOT_MODE: a | b | c | d  -  OPERATING_MODE: normal | manual"
	fi
```

With:
```bash
   -vsioper)
	# Syntax: -vsioper VSI_NAME BOOT_MODE OPERATING_MODE
	if [ $# -ne 4 ]
	then
		usage_vsioper
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many or too few arguments!! Syntax: bluexport_api.sh -vsioper VSI_NAME BOOT_MODE OPERATING_MODE. BOOT_MODE: a | b | c | d  -  OPERATING_MODE: normal | manual"
	fi
```

Replace:
```bash
   -vsitask)
	if [ $# -ne 3 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many or too few arguments!! Syntax: bluexport_api.sh -vsitask VSI_NAME TASK. TASK: dston | retrydump | consoleservice | iopreset | remotedstoff | remotedston | iopdump | dumprestart"
	fi
```

With:
```bash
   -vsitask)
	if [ $# -ne 3 ]
	then
		usage_vsitask
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many or too few arguments!! Syntax: bluexport_api.sh -vsitask VSI_NAME TASK. TASK: dston | retrydump | consoleservice | iopreset | remotedstoff | remotedston | iopdump | dumprestart"
	fi
```

Replace:
```bash
   -vsisrcmon)
	if [ $# -ne 3 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many or too few arguments!! Syntax: bluexport_api.sh -vsisrcmon VSI_NAME START|SHUTOFF"
	fi
```

With:
```bash
   -vsisrcmon)
	if [ $# -ne 3 ]
	then
		usage_vsisrcmon
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many or too few arguments!! Syntax: bluexport_api.sh -vsisrcmon VSI_NAME START|SHUTOFF"
	fi
```

Replace:
```bash
   -attachvolumes)
	# Syntax: bluexport_api.sh -attachvolumes VOLUMES_COMMON_NAME VSI_NAME
	if [ $# -ne 3 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many or too few arguments!! Syntax: bluexport_api.sh -attachvolumes VOLUMES_COMMON_NAME VSI_NAME"
	fi
```

With:
```bash
   -attachvolumes)
	# Syntax: bluexport_api.sh -attachvolumes VOLUMES_COMMON_NAME VSI_NAME
	if [ $# -ne 3 ]
	then
		usage_attachvolumes
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many or too few arguments!! Syntax: bluexport_api.sh -attachvolumes VOLUMES_COMMON_NAME VSI_NAME"
	fi
```

Replace:
```bash
   -detachvolumes)
	# Syntax: bluexport_api.sh -detachvolumes VSI_NAME
	if [ $# -ne 2 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many or too few arguments!! Syntax: bluexport_api.sh -detachvolumes VSI_NAME"
	fi
```

With:
```bash
   -detachvolumes)
	# Syntax: bluexport_api.sh -detachvolumes VSI_NAME
	if [ $# -ne 2 ]
	then
		usage_detachvolumes
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many or too few arguments!! Syntax: bluexport_api.sh -detachvolumes VSI_NAME"
	fi
```

- [ ] **Step 5: Syntax check**

Run: `bash -n bluexport_api.sh`
Expected: no output.

- [ ] **Step 6: Function-level test**

Create `/tmp/test_usage_group5.sh`:

```bash
#!/bin/bash
set -uo pipefail
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT
REPO=/home/rqmartins/Git/bluexport_api
log_file="$WORKDIR/test.log"
: > "$log_file"
echoscreen() {
	echo "SCREEN: $1"
	if [[ "${2:-}" == "1" ]]; then echo "$1" >> "$log_file"; fi
}
for fn in usage_vsistart usage_vsioper usage_vsitask usage_vsisrcmon usage_attachvolumes usage_detachvolumes; do
	source <(sed -n "/^${fn}() {/,/^}/p" "$REPO/bluexport_api.sh")
done

fail=0

echo "=== Case 1: usage_vsioper mentions BOOT_MODE and OPERATING_MODE enums, no log write ==="
: > "$log_file"
out=$(usage_vsioper)
if [[ "$out" == *"a|b|c|d"* && "$out" == *"normal|manual"* ]] && [[ ! -s "$log_file" ]]; then echo "PASS"; else echo "FAIL: out=$out"; fail=1; fi

echo "=== Case 2: usage_vsitask lists TASK values, no log write ==="
: > "$log_file"
out=$(usage_vsitask)
if [[ "$out" == *"dston"* && "$out" == *"dumprestart"* ]] && [[ ! -s "$log_file" ]]; then echo "PASS"; else echo "FAIL: out=$out"; fail=1; fi

echo "=== Case 3: usage_vsisrcmon mentions START|SHUTOFF, no log write ==="
: > "$log_file"
out=$(usage_vsisrcmon)
if [[ "$out" == *"START|SHUTOFF"* ]] && [[ ! -s "$log_file" ]]; then echo "PASS"; else echo "FAIL: out=$out"; fail=1; fi

echo "=== Case 4: usage_attachvolumes and usage_detachvolumes both mention VSI_NAME, no log write ==="
: > "$log_file"
out1=$(usage_attachvolumes)
out2=$(usage_detachvolumes)
if [[ "$out1" == *"VSI_NAME"* && "$out2" == *"VSI_NAME"* ]] && [[ ! -s "$log_file" ]]; then echo "PASS"; else echo "FAIL: out1=$out1 out2=$out2"; fail=1; fi

if [[ $fail -eq 0 ]]; then echo "ALL PASS"; else echo "SOME TESTS FAILED"; exit 1; fi
```

Run: `bash /tmp/test_usage_group5.sh`
Expected: 4 `PASS` lines then `ALL PASS`.

- [ ] **Step 7: Structural wiring check**

Run: `grep -n 'usage_vsistart ;;\|usage_vsioper ;;\|usage_vsitask ;;\|usage_vsisrcmon ;;\|usage_attachvolumes ;;\|usage_detachvolumes ;;' bluexport_api.sh`
Expected: 6 lines.

- [ ] **Step 8: Clean up the verification script**

Run: `rm -f /tmp/test_usage_group5.sh`

- [ ] **Step 9: Commit**

```bash
cd /home/rqmartins/Git/bluexport_api
git add bluexport_api.sh
git commit -m "$(cat <<'EOF'
Add usage_X() parameter detail for VSI operation flags

Covers -vsistart, -vsioper, -vsitask, -vsisrcmon, -attachvolumes,
-detachvolumes.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: `bluexport_api.sh` — COS-Buckets + Config group

**Files:**
- Modify: `bluexport_api.sh` — usage_X() section (append); `-h -FLAG` dispatch (append); the `-restorefromarchive` and `-chscrt` case blocks.

**Interfaces:**
- Consumes: Task 1's skeleton (merged).
- Produces: `usage_restorefromarchive()`, `usage_chscrt()`.

- [ ] **Step 1: Confirm current line numbers**

Run: `grep -n '^#### END: usage_X() functions\|^   -restorefromarchive)\|^   -chscrt)\|-detachvolumes) usage_detachvolumes ;;' bluexport_api.sh`

Read both case blocks to confirm the text below still matches.

- [ ] **Step 2: Append the new functions**

Insert immediately before `#### END: usage_X() functions (Task 1 - more appended by later tasks) ####`:

```bash
usage_restorefromarchive() {
	echoscreen "  BUCKET:"
	echoscreen "    COS bucket name containing the archived object."
	echoscreen "  OBJECT:"
	echoscreen "    Key/path of the archived object to restore."
	echoscreen "  DAYS:"
	echoscreen "    Optional; number of days the restored copy stays available."
	echoscreen "    Defaults to 3 if omitted."
	echoscreen "  ARCHIVE_TYPE:"
	echoscreen "    Optional; Bulk|Standard|Accelerated. Defaults to Accelerated"
	echoscreen "    if omitted."
}

usage_chscrt() {
	echoscreen "  SECRETS_FILE:"
	echoscreen "    Optional; full path to a bluexscrt_*.json file to switch to."
	echoscreen "    If omitted, lists available bluexscrt*.json files and prompts"
	echoscreen "    interactively (also then prompts for a new log file path)."
}

```

- [ ] **Step 3: Append entries to the `-h -FLAG` inner dispatch**

Replace:
```bash
			-detachvolumes) usage_detachvolumes ;;
			*)
				abort "`date +%Y-%m-%d_%H:%M:%S` - Unknown flag for detailed help: $2. Run bluexport_api.sh -h for the full command list." 1
				;;
```

With:
```bash
			-detachvolumes) usage_detachvolumes ;;
			-restorefromarchive) usage_restorefromarchive ;;
			-chscrt) usage_chscrt ;;
			*)
				abort "`date +%Y-%m-%d_%H:%M:%S` - Unknown flag for detailed help: $2. Run bluexport_api.sh -h for the full command list." 1
				;;
```

- [ ] **Step 4: Wire `usage_restorefromarchive`**

Replace:
```bash
   -restorefromarchive)
	# Restore an archived object from COS bucket (S3 Restore)
	if [ $# -lt 3 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments Missing!! Syntax: bluexport_api.sh -restorefromarchive BUCKET OBJECT [DAYS] [ARCHIVE_TYPE]"
	fi
	if [ $# -gt 5 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments!! Syntax: bluexport_api.sh -restorefromarchive BUCKET OBJECT [DAYS] [ARCHIVE_TYPE]"
	fi
```

With:
```bash
   -restorefromarchive)
	# Restore an archived object from COS bucket (S3 Restore)
	if [ $# -lt 3 ]
	then
		usage_restorefromarchive
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments Missing!! Syntax: bluexport_api.sh -restorefromarchive BUCKET OBJECT [DAYS] [ARCHIVE_TYPE]"
	fi
	if [ $# -gt 5 ]
	then
		usage_restorefromarchive
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments!! Syntax: bluexport_api.sh -restorefromarchive BUCKET OBJECT [DAYS] [ARCHIVE_TYPE]"
	fi
```

- [ ] **Step 5: Wire `usage_chscrt`**

`-chscrt`'s only argument-count check is the "too many" branch inside its `if [ $# -ge 2 ]` direct-path-mode block (per Global Constraints, this flag's single argument is fully optional — the check fires only when 3+ total args are given in direct-path mode).

Replace:
```bash
		if [ $# -gt 2 ]
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport_api.sh -chscrt bluexscrt_file_name  (use full path, e.g. /home/user/bluexscrt_new.json)"
		fi
```

With:
```bash
		if [ $# -gt 2 ]
		then
			usage_chscrt
			abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport_api.sh -chscrt bluexscrt_file_name  (use full path, e.g. /home/user/bluexscrt_new.json)"
		fi
```

- [ ] **Step 6: Syntax check**

Run: `bash -n bluexport_api.sh`
Expected: no output.

- [ ] **Step 7: Function-level test**

Create `/tmp/test_usage_group6.sh`:

```bash
#!/bin/bash
set -uo pipefail
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT
REPO=/home/rqmartins/Git/bluexport_api
log_file="$WORKDIR/test.log"
: > "$log_file"
echoscreen() {
	echo "SCREEN: $1"
	if [[ "${2:-}" == "1" ]]; then echo "$1" >> "$log_file"; fi
}
for fn in usage_restorefromarchive usage_chscrt; do
	source <(sed -n "/^${fn}() {/,/^}/p" "$REPO/bluexport_api.sh")
done

fail=0

echo "=== Case 1: usage_restorefromarchive mentions both optional defaults, no log write ==="
: > "$log_file"
out=$(usage_restorefromarchive)
if [[ "$out" == *"Defaults to 3"* && "$out" == *"Defaults to Accelerated"* ]] && [[ ! -s "$log_file" ]]; then echo "PASS"; else echo "FAIL: out=$out"; fail=1; fi

echo "=== Case 2: usage_chscrt explains the interactive fallback, no log write ==="
: > "$log_file"
out=$(usage_chscrt)
if [[ "$out" == *"Optional"* && "$out" == *"interactively"* ]] && [[ ! -s "$log_file" ]]; then echo "PASS"; else echo "FAIL: out=$out"; fail=1; fi

if [[ $fail -eq 0 ]]; then echo "ALL PASS"; else echo "SOME TESTS FAILED"; exit 1; fi
```

Run: `bash /tmp/test_usage_group6.sh`
Expected: 2 `PASS` lines then `ALL PASS`.

- [ ] **Step 8: Structural wiring check**

Run: `grep -n 'usage_restorefromarchive ;;\|usage_chscrt ;;' bluexport_api.sh`
Expected: 2 lines.

- [ ] **Step 9: Clean up the verification script**

Run: `rm -f /tmp/test_usage_group6.sh`

- [ ] **Step 10: Commit**

```bash
cd /home/rqmartins/Git/bluexport_api
git add bluexport_api.sh
git commit -m "$(cat <<'EOF'
Add usage_X() parameter detail for COS/config flags

Covers -restorefromarchive and -chscrt (the latter's single argument
is fully optional - see Global Constraints). This completes the
usage_X()/-h -FLAG coverage for every argument-taking flag in
bluexport_api.sh.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: `bluexscrt_config_api.sh` — `-dellpar`/`-addlpar` + its own `-h -FLAG`

**Files:**
- Modify: `bluexscrt_config_api.sh` — new `usage_dellpar()`/`usage_addlpar()` functions (placed immediately before `case "$flag" in`); the `-h | --help)` block; the `-dellpar` and `-addlpar` case blocks.

**Interfaces:**
- Produces: `usage_dellpar()`, `usage_addlpar()` — plain `echo "..." >&2` (not `echoscreen`), matching this script's existing convention in these two branches. Independent `-h -FLAG` dispatch skeleton for this script (separate from `bluexport_api.sh`'s).

**Why `echo >&2` instead of `echoscreen`:** `bluexscrt_config_api.sh` does define `echoscreen()`/`abort()` (used elsewhere in the script, e.g. `ensure_config_exists`), but `-dellpar`/`-addlpar`'s existing error paths use plain `echo "..." >&2; exit 1` — not those functions. Per this plan's Global Constraints, existing argument-count validation/error mechanisms are not migrated to a different convention; only a new `usage_X` call is added, using the same output style already in place at that exact call site.

- [ ] **Step 1: Confirm current line numbers**

Run: `grep -n '^case "\$flag" in\|^  -h | --help)\|^  -dellpar)\|^  -addlpar)' bluexscrt_config_api.sh`

Read from `case "$flag" in` through the `-addlpar)` block's closing `;;` to confirm the text below still matches.

- [ ] **Step 2: Insert the new functions immediately before `case "$flag" in`**

Insert immediately before the line `case "$flag" in`:

```bash
#### START: usage_X() - per-flag parameter detail (shown on argument-count error and via -h -FLAG) ####
usage_dellpar() {
	echo "  NAME:" >&2
	echo "    Logical system name to remove from .systems[] (case-insensitive)." >&2
}

usage_addlpar() {
	echo "  NAME:" >&2
	echo "    Logical system name (e.g. ibmi75m2)." >&2
	echo "  IP:" >&2
	echo "    IP address used for SSH and bluexport operations." >&2
	echo "  PVM_ID:" >&2
	echo "    PowerVS pvmInstanceID of the LPAR." >&2
	echo "  WORKSPACE_SHORT:" >&2
	echo "    Workspace key as defined under .workspaces in the JSON (e.g. WSMAD2)." >&2
	echo "  OS:" >&2
	echo "    ibmi|aix|linux|other - determines whether operations that flush ASPs" >&2
	echo "    (CHGASPACT) run for this LPAR (ibmi only)." >&2
}
#### END: usage_X() functions ####

```

- [ ] **Step 3: Rewrite the `-h | --help)` block**

Replace:
```bash
  -h | --help)
    usage
    exit 0
    ;;
```

With:
```bash
  -h | --help)
    if [ $# -gt 2 ]; then
      echo "ERROR: Too many arguments!! Syntax: $(basename "$0") -h [-FLAG]" >&2
      exit 1
    fi
    if [ $# -eq 2 ]; then
      case "$2" in
        -dellpar) usage_dellpar ;;
        -addlpar) usage_addlpar ;;
        *)
          echo "ERROR: Unknown flag for detailed help: $2. Run $(basename "$0") -h for the full command list." >&2
          exit 1
          ;;
      esac
      exit 0
    fi
    usage
    exit 0
    ;;
```

- [ ] **Step 4: Wire `usage_dellpar`**

Replace:
```bash
  -dellpar)
    if [[ $# -ne 2 ]]; then
      echo "ERROR: Wrong syntax." >&2
      echo "Usage: $(basename "$0") -dellpar NAME" >&2
      exit 1
    fi
```

With:
```bash
  -dellpar)
    if [[ $# -ne 2 ]]; then
      echo "ERROR: Wrong syntax." >&2
      echo "Usage: $(basename "$0") -dellpar NAME" >&2
      usage_dellpar
      exit 1
    fi
```

- [ ] **Step 5: Wire `usage_addlpar`**

Replace:
```bash
  -addlpar)
    # Now: NAME IP PVM_ID WORKSPACE_SHORT OS
    if [[ $# -ne 6 ]]; then
      echo "ERROR: Wrong syntax." >&2
      echo "Usage: $(basename "$0") -addlpar NAME IP PVM_ID WORKSPACE_SHORT OS" >&2
      echo "  OS must be one of: ibmi | aix | linux | other" >&2
      exit 1
    fi
```

With:
```bash
  -addlpar)
    # Now: NAME IP PVM_ID WORKSPACE_SHORT OS
    if [[ $# -ne 6 ]]; then
      echo "ERROR: Wrong syntax." >&2
      echo "Usage: $(basename "$0") -addlpar NAME IP PVM_ID WORKSPACE_SHORT OS" >&2
      echo "  OS must be one of: ibmi | aix | linux | other" >&2
      usage_addlpar
      exit 1
    fi
```

(Do not touch the separate `case "$lpar_os" in ... esac` validation further down in this same block, which handles an invalid `OS` *value* rather than a wrong argument *count* — out of scope, per this plan's Global Constraints.)

- [ ] **Step 6: Syntax check**

Run: `bash -n bluexscrt_config_api.sh`
Expected: no output.

- [ ] **Step 7: Function-level test**

Create `/tmp/test_usage_bluexscrt.sh`:

```bash
#!/bin/bash
set -uo pipefail
REPO=/home/rqmartins/Git/bluexport_api
for fn in usage_dellpar usage_addlpar; do
	source <(sed -n "/^${fn}() {/,/^}/p" "$REPO/bluexscrt_config_api.sh")
done

fail=0

echo "=== Case 1: usage_dellpar mentions NAME, writes to stderr ==="
out=$(usage_dellpar 2>&1 1>/dev/null)
if [[ "$out" == *"NAME"* ]]; then echo "PASS"; else echo "FAIL: out=$out"; fail=1; fi

echo "=== Case 2: usage_addlpar mentions all 5 params and the OS enum, writes to stderr ==="
out=$(usage_addlpar 2>&1 1>/dev/null)
for p in NAME IP PVM_ID WORKSPACE_SHORT "ibmi|aix|linux|other"; do
	if [[ "$out" != *"$p"* ]]; then echo "FAIL: missing $p in: $out"; fail=1; fi
done
[[ $fail -eq 0 ]] && echo "PASS"

if [[ $fail -eq 0 ]]; then echo "ALL PASS"; else echo "SOME TESTS FAILED"; exit 1; fi
```

Run: `bash /tmp/test_usage_bluexscrt.sh`
Expected: 2 `PASS` lines then `ALL PASS`.

- [ ] **Step 8: Structural wiring check**

Run: `grep -n 'usage_dellpar\|usage_addlpar' bluexscrt_config_api.sh`
Expected: 6 lines total (2 function definitions, 2 `-h -FLAG` dispatch arms, 2 call-site insertions).

- [ ] **Step 9: Clean up the verification script**

Run: `rm -f /tmp/test_usage_bluexscrt.sh`

- [ ] **Step 10: Commit**

```bash
cd /home/rqmartins/Git/bluexport_api
git add bluexscrt_config_api.sh
git commit -m "$(cat <<'EOF'
Add usage_X() parameter detail for -dellpar/-addlpar

Same usage_<flag>()/-h -FLAG pattern as bluexport_api.sh, adapted to
this script's own error-handling convention: usage_dellpar()/
usage_addlpar() use plain "echo ... >&2" (matching what -dellpar/
-addlpar's existing error paths already use) rather than echoscreen(),
since this plan does not migrate that existing mechanism.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: Documentation and version bump

**Files:**
- Modify: `bluexport_api.sh` — header comment block, `Version=`.
- Modify: `bluexscrt_config_api.sh` — `usage()` heredoc, `VERSION=`.
- Modify: `README.md`, `CHANGELOG.md`.

**Interfaces:**
- Consumes: nothing (documentation/metadata only). Run this task last, after Tasks 1-7 are committed.

- [ ] **Step 1: Confirm current versions**

Run: `grep -n '^Version=' bluexport_api.sh; grep -n '^VERSION=' bluexscrt_config_api.sh`

- [ ] **Step 2: Add a header-comment note to `bluexport_api.sh`**

Find the line `# Show version:                 bluexport_api.sh -v | --version` near the top of the header comment block and insert immediately after it:

```bash
# Detailed help for one command:  bluexport_api.sh -h -FLAG  (e.g. -h -imgimport)
```

- [ ] **Step 3: Bump `bluexport_api.sh`'s `Version=`**

Change `Version=1.15.0` to `Version=1.16.0`.

- [ ] **Step 4: Add a note to `bluexscrt_config_api.sh`'s `usage()` heredoc**

Find the `-h | --help` entry in the `usage()` heredoc (around line 99: `  -h | --help\n      Show this help.`) and replace it with:

```
  -h | --help [-FLAG]
      Show this help, or detailed parameter help for one flag
      (e.g. -h -addlpar).
```

- [ ] **Step 5: Bump `bluexscrt_config_api.sh`'s `VERSION=`**

Change `VERSION="2.0"` to `VERSION="2.1"`.

- [ ] **Step 6: Update `README.md`**

Add a short paragraph near the top of each script's usage documentation section (wherever the existing README already introduces `-h`/`--help` for that script) noting the new `-h -FLAG` detailed-help mode and that argument-count errors now also print the parameter breakdown automatically.

- [ ] **Step 7: Update `CHANGELOG.md`**

Read `CHANGELOG.md`'s most recent entries for formatting, then add new entries:

```markdown
## [1.16.0] - 2026-08-10 (`bluexport_api.sh`)

### Added
- Every flag that takes at least one argument now prints a per-parameter breakdown (name + description) when the argument count is wrong, and via a new `-h -FLAG` detailed-help mode (e.g. `bluexport_api.sh -h -imgimport`). The general `-h` summary is unchanged.

## [2.1] - 2026-08-10 (`bluexscrt_config_api.sh`)

### Added
- `-dellpar`/`-addlpar` now print a per-parameter breakdown on a wrong argument count, and via a new `-h -FLAG` detailed-help mode (e.g. `-h -addlpar`).
```

- [ ] **Step 8: Syntax check both scripts**

Run: `bash -n bluexport_api.sh && bash -n bluexscrt_config_api.sh && echo "ALL OK"`
Expected: `ALL OK`

- [ ] **Step 9: Commit**

```bash
cd /home/rqmartins/Git/bluexport_api
git add bluexport_api.sh bluexscrt_config_api.sh README.md CHANGELOG.md
git commit -m "$(cat <<'EOF'
Version bump + docs for per-flag usage_X() detail

bluexport_api.sh -> 1.16.0, bluexscrt_config_api.sh -> 2.1 (both
MINOR: purely additive, no existing behavior changed).

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: Real-world verification (required before calling this done)

Not a code task — acceptance checklist against the real deployed tools. The function-level tests in Tasks 1-7 prove each `usage_X()` function's own content and its screen-only behavior; they do not prove the full end-to-end dispatcher wiring (invoking the real script with a wrong argument count, or the real `-h -FLAG` path) since that requires the full `bluexscrt`/`conf_file`/IAM-token environment this plan's sandbox tests deliberately avoid standing up. Do not report this feature as done without running this.

- [ ] **Step 1: Argument-count error path, one flag per group**

Pick one flag from each of the 8 groups (e.g. `-imgimport`, `-snapcr`, `-vclone`, `-creategrs`, `-vsioper`, `-restorefromarchive`, plus `-dellpar`/`-addlpar` on `bluexscrt_config_api.sh`) and run each with too few arguments. Confirm the parameter breakdown appears on screen, the existing one-line Syntax message still appears after it, and the log file (`bluexport_bcce.log` or equivalent) does NOT contain the parameter breakdown — only the single Syntax line, exactly as before this feature.

- [ ] **Step 2: `-h -FLAG` mode**

Run `bluexport_api.sh -h -imgimport`, `bluexport_api.sh -h -a`, and `bluexport_api.sh -h -ta` (confirm both aliases work identically) and `bluexscrt_config_api.sh -h -addlpar`. Confirm `echo $?` is `0` after each.

- [ ] **Step 3: `-h` error cases**

Run `bluexport_api.sh -h -imgimport somethingextra` and confirm it errors with exit code 1 (not silently accepted). Run `bluexport_api.sh -h -notarealflag` and confirm the "Unknown flag for detailed help" message and exit code 1. Repeat both on `bluexscrt_config_api.sh`.

- [ ] **Step 4: General `-h` unchanged**

Run `bluexport_api.sh -h` (no second argument) and confirm the output is identical in shape to before this feature (still the short one-line-per-command summary, not the new detailed breakdowns).

- [ ] **Step 5: Real verification on IBM i PASE**

Repeat at least Step 1 (one flag) and Step 2 on the real IBM i PASE environment, per standing project guidance.

- [ ] **Step 6: Report results to the user**

Summarize what was confirmed, any deviations, and get explicit sign-off before considering this feature complete.

---

## Self-Review Notes

- **Spec coverage:** Section A (shared `usage_X()` mechanism, screen-only `echoscreen`) → Tasks 1-6. Section A's `bluexscrt_config_api.sh` echo/log adaptation → Task 7 (with rationale documented, resolving the architecture question the content-drafting pass flagged). Section B.1 (call before `abort()`) → every wiring step in Tasks 1-7. Section B.2 (`-h -FLAG`, alias resolution, arg-count limit) → Task 1 establishes the skeleton for `bluexport_api.sh`, Tasks 2-6 extend it; Task 7 establishes the separate skeleton for `bluexscrt_config_api.sh`. Section B.3 (general `-h` untouched) → confirmed, no task modifies `help()`/`usage()`'s own body (only the `-h` case block's wrapper logic). Section C (scope, both scripts, zero-arg flags excluded) → confirmed against the Global Constraints' explicit zero-arg-flag list, drawn from the vetted content-drafting pass. Section D (MINOR bump both scripts) → Task 8. All spec sections have a task.
- **Placeholder scan:** no TBD/TODO; every step has literal code, an exact `grep`, or an exact test script.
- **Type/name consistency:** every `usage_X()` function name matches exactly between its definition (Tasks 1-7), its call-site insertion, and its `-h -FLAG` dispatch arm — cross-checked during plan-writing against a research pass over the actual case-dispatch code (scratch notes, not committed — content is fully embedded in each task above).
- **Line numbers:** every task's Step 1 re-confirms current line numbers/text with `grep`/`Read` before editing, since both scripts shift with each prior task in this plan. Task 3 additionally warns against `replace_all` given `-vchtier`/`-insvchtier`'s textually-similar blocks.
- **Content accuracy:** every parameter description was grounded directly in the actual case-dispatch code, called function signatures, or pre-existing detailed help text already in the repo — verified via a dedicated research pass (not guessed), including surfacing two genuine pre-existing inconsistencies (tier-prefix convention, `-vclone`'s VOLUMES being names not IDs per a prior user correction in project memory) that must be documented, not silently corrected.
