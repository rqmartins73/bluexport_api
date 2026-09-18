# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- (future changes go here)

## [1.23.0] - 2026-09-18 (`bluexport_api.sh`)

### Added

- **`-invreport [FORMAT] [PATH] [OLD_DAYS]`: a read-only inventory report
  across every configured workspace and COS instance.** One pass covers
  workspaces, LPARs (compute, licences, IP addresses), volumes, volume
  groups and their replication state, snapshots, images, volume clones,
  and COS buckets with object counts/sizes - plus a Totals section
  (memory/cores, storage by tier, unattached volumes, snapshots/images
  older than `OLD_DAYS`, default 90).
  - `FORMAT`: `md` (default, the source of truth), `csv` (one file per
    section under `PATH-csv/`), `html` (one self-contained file), or
    `all` (writes all three). Case-insensitive.
  - `PATH` defaults to `./bluexport-inventory-<timestamp>`, no extension.
  - Every helper this flag calls is a `GET` - it never writes to the
    account, only to the report file(s).
  - A workspace, volume group or bucket that cannot be read is named in
    the report's own "Could not be read" section and skipped; one bad
    workspace never stops the report and is never rendered as an empty
    or zero result (a workspace-loop failure here does not `abort` the
    whole run the way most other `*lsall` flags do - deliberately, since
    that pattern would turn "this account only has 2 workspaces" and "a
    workspace failed to read" into the same, indistinguishable output).
  - The COS object-count pagination this needed did not exist yet
    (`list_object()` only ever read one page) - added `list_object_page()`
    and a bounded pagination loop (`INVREPORT_MAX_COS_PAGES`, default
    100000) that follows `<NextContinuationToken>` while
    `<IsTruncated>true</IsTruncated>`, using the same bash+sed-free XML
    parsing `-bucketslsall` already uses for `<Bucket>` elements, applied
    to `<Contents>` elements. Hitting the cap, or a truncated page with no
    continuation token, discards the count/size entirely rather than
    reporting a partial listing as complete.
  - Internal TSV field separator is `\037` (ASCII unit separator), not a
    literal tab: bash's `read`/`awk` treat a run of tab characters as one
    delimiter (the same whitespace-collapsing rule as word-splitting),
    which silently misaligns a row the moment any field is legitimately
    empty (no licences, no tier, no attached LPAR, ...). `\037` is not
    IFS whitespace, so an empty field never gets swallowed.

## [1.22.0] - 2026-09-17 (`bluexport_api.sh`)

### Fixed

- **`-vclonedel` could refuse to delete a volume clone request with no way forward.** Live
  against a real account, deleting a clone request still in status `available` (i.e. cloned
  but not yet cancelled) answered `400 Bad Request`, and the operator only ever saw
  `Delete of volume clone request NAME was refused: Bad Request` - the API's own explanation
  (which names the current status and the three terminal ones it needs) lives in `.description`,
  and the shared `delete_check` picked `.error` (just the HTTP reason phrase) ahead of it.
  `-vclonedel` now reads the request's status before ever calling delete:
  - `completed`/`failed`/`cancelled` (terminal): deletes immediately, as before.
  - `available`/`running`/`preparing` (cancellable - the same status `do_volume_clone_start`
    already waits for): asks explicitly, separately from the existing delete confirmation,
    whether to cancel first; only cancels on a typed "yes", never silently.
  - anything else (`creating`/`executing`/`cancelling`/unrecognized): aborts, naming the
    status, since there is nothing safe to cancel out of yet.
  If the delete call still comes back with that same status-conflict shape anyway (e.g. a race
  between the check and the delete), the real `.description` is surfaced directly instead of
  `delete_check`'s generic `.error` message - `delete_check` itself is unchanged, since it is
  shared with `-imgdel` and `-jobcancel` and changing its field precedence would have changed
  their messages too.

### Added

- **The missing cancel step.** `vol_cl_ca` (the wrapper for
  `POST .../volumes-clone/{id}/cancel`) existed since 1.18.8 but had no caller anywhere in the
  script - there was no way to cancel a clone request from the CLI at all. `-vclonedel` now
  calls it (with `force: true`) when the operator confirms cancelling, then polls the request's
  status every 5 seconds until it reaches a terminal one before deleting.
  - **Bounded.** The poll uses the same `BLUEXPORT_JOB_MAX_SECS` cap (default 24h)
    `vclone_time_left` already reads elsewhere; exhausting it aborts with "cancelled but not
    yet confirmed terminal - check status and delete manually" instead of polling forever.

## [1.21.0] - 2026-09-17 (`bluexport_api.sh`)

### Added

- **Four Jobs flags: `-jobslsall`, `-jobsls WORKSPACE`, `-jobget JOB_ID`, `-jobcancel JOB_ID`.**
  Account-wide job listing/detail/cancel, on top of the same unified PowerVS jobs queue
  `-j`/`-ji`/`-je` already poll:
  - `-jobslsall` lists every job in every configured workspace as one merged table with a
    `WORKSPACE` column - unlike `-imglsall`/`-snaplsall`/`-vclonelsall`, which print a
    separate section per workspace, this one is a single table, per the brief for this flag.
  - `-jobsls WORKSPACE` prints the same table for one workspace, resolved by short or full
    name (the same lookup `-ji` already uses).
  - `-jobget JOB_ID` prints one job's full detail, resolved by searching every configured
    workspace for the ID (the same "search every workspace" idiom `-imgdel`/`-je` already
    use for a bare name, via the new `job_find_ws()`).
  - `-jobcancel JOB_ID` cancels/deletes a job, found the same way, but refuses locally when
    the job's own status is already `completed` or `failed` - nothing left to cancel - and
    asks for typed confirmation (`confirm_or_abort`, 1.19.0) before sending the DELETE.
  - New API-layer functions: `job_ls_status()` (same request as the existing, until-now-unused
    `job_ls()`, with the HTTP status appended - `job_get()`'s idiom) and `job_del()` (DELETE,
    same idiom, checked by the existing `delete_check()`). No new HTTP plumbing otherwise:
    `job_get()`, `confirm_or_abort()` and `delete_check()` are reused unchanged.
  - Every call reads its HTTP status; a non-2xx aborts (exit 1) naming the workspace or job
    and the step that failed. Status strings are the API's own, never re-worded.

### IBM i / PASE

- The four new flags use only constructs already elsewhere in this script (arrays, `[[ ]]`,
  `local`, `${var,,}`, `read -r -a ... <<<`) - no `readarray`/`mapfile`, no `/proc`, no
  `PIPESTATUS`, no `grep -P`.

## [1.20.1] - 2026-09-15 (`bluexport_api.sh`)

### Fixed

- **`-grsfailover` and `-grscancelfailover` still took the first workspace that had the
  consistencyGroupName.** 1.20.0 refuses several matches inside one workspace, but the scan
  across the other configured workspaces stopped at the first hit. It now scans them all and
  aborts (exit 1, before any change) when more than one workspace has a match.

### IBM i / PASE

- `echo | wc -w` and `[ ]` only.

## [1.20.0] - 2026-09-15 (`bluexport_api.sh`)

### Fixed

- **Four GRS waits had no bound.** `chk_vol_mirror`, `chk_on_status`, `chk_vol_rep`'s final
  recheck, and the `-grscancelfailover` DETACH wait (no attached volumes left on
  TARGET_VSI) looped `while true` forever. They now abort (exit 1), naming what did not
  finish, after: `chk_vol_rep` 30 minutes, `chk_on_status` 60 minutes, the DETACH wait 30
  minutes, and `chk_vol_mirror` 24 hours (it copies whole disks) - overridable in minutes
  with `BLUEXPORT_GRS_MIRROR_MAX_MIN`.
- **GRS write calls did not check the HTTP status.** `vg_cr`, `vg_act`, `vg_del`, `vg_upd`,
  `on_cr`, the replication-enable `vol_act`, `ins_vol_bdet`, `vol_att_multi` and `vol_bdel`
  were piped straight to the log, or checked only by grepping the body for `.code`/`.error`
  - a field a rejected (non-2xx) response does not have to carry, so a refused request
  could look identical to a success and the flow kept going onto volumes or groups the API
  never touched. New `*_status` wrappers (same `-w '\n%{http_code}'` shape as
  `vol_act_status`) are used at the GRS create/delete/failover/cancel-failover/
  failback/reverse-replica call sites; a new `grs_check_write` helper aborts (exit 1) on
  any non-2xx status with the API's `.description`/`.message`/`.error`/`.errors[0].message`,
  naming the step and what earlier steps in that call already reached the API. Other
  callers of these functions (attach/detach volumes, volume clone) are unchanged.
- **`head -n1` on an ambiguous match.** The target Volume Group lookup by
  `consistencyGroupName` (`-grsfailover`, `-grscancelfailover`, `-grsfailback`,
  `-grsreversereplica`) and the boot/auxiliary volume name-to-volumeID resolution in
  `-grsfailover`'s ATTACH step silently took the first of several matches. They now count
  matches and abort (exit 1) listing them when there is more than one - before any write
  in the function when the lookup happens before writes, otherwise before the next write.
- **`-grscancelfailover` could start the master onto volumes TARGET_VSI was running on.**
  Before any write, it now reads TARGET_VSI's status and attached volumes; if TARGET_VSI is
  not SHUTOFF and is attached to a volume that is a member of the target Volume Group, it
  refuses with "stop TARGET_VSI first: the master start overwrites the volumes it is
  running on". The existing end-of-run warning (NO_DETACH, still-attached volumes) is
  unchanged.

### IBM i / PASE

- POSIX constructs only: `local`, `$(( ))`, `case`, `[ ]`/`[[ ]]`, `grep -c`/`-x`/`-w`,
  `printf`, `jq -r`/`-e`. No `readarray`, `/proc`, `PIPESTATUS`, `grep -P` or other
  GNU-only flags introduced.

## [1.19.3] - 2026-09-15 (`bluexport_api.sh`)

### Fixed

- **`-grsfailback` stopped halfway on every run.** Its three polls (source replication
  disabled, source replication re-enabled, target replication visible) compared against
  `max_wait`, which was never set in `do_grs_failback`. An empty value counts as 0, so the
  first two polls aborted (exit 1) on their first check - typically after the aux-to-master
  sync and the source stop had already been sent - and the third only warned. They now wait
  up to 60 minutes, like the other GRS flags.

### IBM i / PASE

- One `local` declaration; no new commands or constructs.

## [1.19.2] - 2026-09-15 (`bluexport_api.sh`)

### Fixed

- **`-deletegrs` could delete volumes that were not part of the replication group.** The
  auxiliary volumes to delete were every volume in the target workspace whose name
  contained SOURCE_VOLUME_NAMES, so another LPAR's disk or a clone with that text in its
  name was removed from the volume group, and bulk-deleted. The source side likewise
  disabled replication on every source-workspace volume whose name started with the
  value. Both sides now act only on the volume groups' own members (`volumeIDs` from the
  volume group details).
- **The last safety check before the delete could never refuse.** It read each auxiliary
  volume through the target VSI right after all volumes had been detached from it, the
  read failed, and `// "false"` let the volume pass. It now reads the volume at workspace
  level and deletes only when every volume reads `replicationEnabled=false` and is
  attached to no LPAR; an unreadable volume stops the delete (exit 1).
- **The target volume group was picked by name prefix.** It is now matched by
  `consistencyGroupName`, like the other GRS flags, and more than one match stops the run
  before anything is changed.
- The three waits in `-deletegrs` (source VG empty, source replication disabled, target
  detach) are bounded at 30 minutes and exit 1 on timeout.

### IBM i / PASE

- `jq -e`, `case`, `[ ]` and arithmetic expansion only; no new external commands.

## [1.19.1] - 2026-09-15 (`bluexport_api.sh`)

### Fixed

- **59 more failures still exited 0.** 1.19.0 matched failure aborts by a fixed word list,
  so messages worded differently ("Too many or too few arguments", "is not SHUTOFF",
  "does not exist", "did not reach", "Cannot ping", "Job Failed", "Empty response",
  "has no GUID", the GRS safety refusals) kept exit 0. Each now passes `1`. "Nothing to
  do", "Nothing to list" and user-cancelled aborts still exit 0.

### IBM i / PASE

- Exit codes only; no new commands or shell constructs.

## [1.19.0] - 2026-09-15 (`bluexport_api.sh`)

### Fixed

- **A failed run could still exit 0.** `abort()` itself is unchanged (it still exits
  `${2:-0}`), but 198 of its call sites that report a failure (FAILED/ERROR/Invalid/
  not found/missing/"Too many arguments"/"Arguments Missing"/not valid/must be/Could
  not/Unable/denied/refused/No input - "cancelled by user" is not a failure and was
  left alone) passed no exit code at all, so a scheduler or IBM i job that only checks
  the return code saw success. Each of those 198 lines now passes `1`. **This is the
  one behaviour change callers can notice: a scheduler now stops on a failure it used
  to silently pass through.**
- **A job poll that lost its status retried at a flat 30s, up to 10 times, with no
  regard for a 429.** `job_get` now takes an optional header-file path (`curl -D`) and
  a new `job_poll_delay()` backs `job_monitor` and `wait_for_job`'s retry off
  exponentially (30s/60s/120s/240s, capped at 300s); on HTTP 429 the server's own
  `Retry-After` (seconds form, read case-insensitively) is honoured when present.
- **`dc_vsi_list` could blank `base_url`.** When the workspace's region had no matching
  `base_<region>` variable, the indirect expansion silently produced an empty
  `base_url` and every subsequent API call in that run would hit a bare host. It now
  aborts (exit 1), naming the CRN and the unresolved region.
- **`get_iam_token` ignored the token's own `expires_in`.** All three refresh timers
  (`job_monitor`, `wait_for_job`, `vsi_source_monitor`'s poll) used a hardcoded 2700s
  guess. `get_iam_token` now sets a global `iam_refresh_secs` to 75% of `expires_in`
  (falling back to 2700 when it is absent, non-numeric, or under 120s), and all three
  timers read `${iam_refresh_secs:-2700}`.
- **`-imgexport` and `-je` (`img_export`, `img_export_monitor`) narrowed an ambiguous
  image name to the first match** (`head -n1` then `break` on the first workspace with
  a hit), same class of bug fixed for `-imgdel` in 1.18.6. Both now search every
  workspace, count every match, and abort (exit 1) listing them when more than one
  image carries the name.
- **The image import pre-check used an IAM bearer token for CURRACCOUNT.** The export
  pre-check has said since 1.18.6 that this check must always use `--aws-sigv4` with
  the same `cos_accesskey:cos_secretkey` that go into the payload, so it validates the
  credentials actually used; the import pre-check (`img_import`) now does the same
  unconditionally, for both CURRACCOUNT and OTHERACCOUNT.
- **`-vclone`'s explicit volume list was sent as volumeIDs even though the syntax asks
  for volume NAMES.** Each comma-separated token is now resolved against `ins_vol_ls`:
  an exact `name` match uses that volume's `volumeID`, an exact `volumeID` match is
  used as-is, and a token matching neither (or a name shared by more than one volume)
  aborts (exit 1) naming it. `ALL` is unchanged. The handler's `# Args:` comment, which
  said `id1,id2,...`, now says `name1,name2,...` and points at `usage_vclone`.
- **`vchtier` decided failure by grepping `Failed`/`Performing` out of accumulated JSON
  - a pattern that never matched real API output - and never read `vol_act`'s HTTP
  status.** A new `vol_act_status` wrapper (added alongside `vol_act`, which keeps its
  other callers untouched) appends the HTTP status; `vchtier` now reads it per volume:
  2xx is a change, a body containing "current storage tier" is "already at that tier"
  (not an error), anything else is a failure reported with the API's
  `.description // .message // .error`. The dead `grep -B2 Failed | grep Performing`
  is removed, and the final "there were errors" abort now exits 1 (both `-vchtier` and
  `-insvchtier` call this function).
- **`-vclone`, `-vclonedel`, `-vchtier` and `-insvchtier` had no confirmation before
  acting on live volumes/VSIs.** A new `confirm_or_abort "<what>" "<name>"` requires an
  interactive operator (stdin and stdout both a TTY) to type the name back: the clone
  request name for `-vclone`/`-vclonedel` (saying explicitly when `delete_volumes`
  will also delete the produced volumes), the VSI name for the two tier flags. When
  not interactive (IBM i batch, cron, pipes) or when `BLUEXPORT_ASSUME_YES=1`,
  confirmation is skipped - one log line says so - so existing automation keeps
  working unchanged.
- **`do_volume_clone_start` checked the clone's status once, immediately after the
  start POST**, which could catch it still mid-transition and fail a start that was
  actually fine. It now polls every 5s with the same `vclone_time_left` (time bound)
  and `vclone_failure` (added in 1.18.8) helpers `do_volume_clone_execute` already
  uses, until `action == start` and `status == available`.

### Changed

- `BLUEXPORT_ASSUME_YES=1` is a new environment variable: set it to skip the new
  interactive confirmations above without changing any other behaviour.

IBM i / PASE: no new external dependencies - `curl -D`/`-w`, `jq`, `awk`, `date +%s`,
`[ ]`, `case`, `read -r ... < /dev/tty` are all already used elsewhere in this script.
`confirm_or_abort`'s TTY check (`[ -t 0 ] && [ -t 1 ]`) is false under IBM i batch/cron,
so scheduled jobs skip the prompt exactly as before, unless they already read from a
terminal.

## [1.18.8] - 2026-09-15 (`bluexport_api.sh`)

### Fixed

- **A failed volume clone was watched forever.** Both `-vclone` polls waited only for
  `percentComplete` to reach 100, so a clone request or execution that failed never ended the
  script. A clone is now treated as failed when its `status` is `failed` or it carries a
  `failureMessage` (the API's field for why a clone failed); the script stops with exit 1 and
  prints that reason.
- **The clone polls had no time bound.** They now stop after `BLUEXPORT_JOB_MAX_SECS` (24 hours
  by default), the same bound `wait_for_job` has; the clone itself continues in IBM Cloud.
- **`-vclone`'s duplicate-name check never fired.** It read `.volumeClones[]`, but the API returns
  `.volumesClone[]` (as every other read in the script already uses), so an existing name was never
  found.
- **`-vclonedel` reported a refused delete of the clone request as success.** The status checked
  was `tee`'s, not `curl`'s. The call now appends its HTTP status and `delete_check` reads it.
- The execute poll's two failure aborts now exit 1.

IBM i / PASE: `jq`, `date +%s`, `[ ]` and `case` only.

## [1.18.7] - 2026-09-15 (`bluexport_api.sh`)

### Fixed

- **`-restorefromarchive` sent no `Content-MD5`.** IBM Cloud Object Storage requires an integrity
  header on a restore request; without it the request can be refused. The header is now the base64
  MD5 of the exact XML body, computed with `openssl`. On a system without `openssl` the request is
  sent as before and a warning is logged.

IBM i / PASE: `command -v openssl` decides; `openssl dgst -md5 -binary | openssl base64` is the only
new dependency, and it is optional.

## [1.18.6] - 2026-09-13 (`bluexport_api.sh`)

### Fixed

- **`-imgdel` could report a delete that had not happened.** `img_del` never read the HTTP status,
  and success was inferred from the body not being JSON with a `code` field — so a `403` or `404`
  with an empty body printed "deleted successfully". `img_del` now appends the status, and a
  shared `delete_check` reads it (and any JSON or XML error body) before anything is called done.
  The same check now covers the object delete in `-bucketdelobj` and both deletes inside the
  previous-capture cleanup, which piped their output to `tee` and never looked at it.
- **`-imgdel` deleted the first image that matched, with no confirmation, even when the name was
  not unique.** The search stopped at the first workspace with a hit and took the first match in
  it. Every workspace is now searched and every match counted; more than one match aborts with the
  list, and nothing is deleted.
- **`-restorefromarchive` ended a successful request with exit status 1.** Its success lines
  passed `"1"` as `abort`'s second argument, which is the exit code, not a log flag; a restore
  already in progress did the same. Both now exit 0, and the two validation failures (DAYS not a
  number, ARCHIVE_TYPE not Bulk/Accelerated) now exit 1 instead of 0.
- The restore request sent its XML body under `Content-Type: application/json`; it is
  `application/xml` now.
- The XML error parsing in the restore path used `grep -P`, which not every PASE `grep` has;
  it is `sed` now.

### Changed

- **`wait_for_job` has a wall-clock bound.** A job answering a readable, non-terminal state was
  polled forever. The default is 24 hours (`BLUEXPORT_JOB_MAX_SECS` overrides it); on reaching it
  the monitor stops with exit 1 and says so — the job itself continues in IBM Cloud, and `-j`,
  `-ji` or `-je` re-attach to it.
- `echoscreen`'s comment said it wraps at 132 columns; the code wraps at 377 and now the comment
  says so too.

IBM i / PASE: `$'\n'` splitting is what the script already used for `img_import_api`; the new
helper uses `[ ]`, `case`, `sed -n` and `jq`, nothing else.

## [1.18.5] - 2026-09-13 (`bluexport_api.sh`)

### Changed

- Comments only. The fix comments added in 1.18.1–1.18.4 carried a finding number from another
  project's tracker that means nothing to a reader of this repository; they now name the version
  that made the change and nothing else. No code changed.

## [1.18.4] - 2026-09-13 (`bluexport_api.sh`)

### Fixed

- **`-x` and `-tx` accepted `hourly` and `daily` with `both` or `cloud-storage`, which `-a` has
  always refused.** The recurrence check read `$destination` before the handler assigned it —
  `destination=$5` came 46 lines later — so it compared an empty string and never fired. The
  assignment now comes first. Reproduced before the fix (`-x LOGVOL VSI IMG cloud-storage hourly`
  accepted) and after it (refused with the same message as `-a`); `image-catalog hourly` and
  `cloud-storage weekly` are still accepted.

- **In the repeated hour of an autumn clock change, hourly cleanup could delete the capture it
  had just taken.** On the last Sunday of October in Europe/Lisbon, 01:00–01:59 happens twice. In
  the second one, `date --date '1 hour ago' "+_%H"` is `_01` — the same suffix the capture just
  taken is named with — so `delete_previous_img` looked for this run's own image. The cleanup is
  now skipped when the hourly token equals the current capture's suffix, with a line saying so.
  Skipping deletes nothing; the older image of the same name is left for a later cleanup. Checked
  across the 2026 change: 01:30 WEST and 02:30 WET clean up as before, 01:30 WET skips.

Both changes are plain `[ ]` tests and an earlier assignment — nothing new for PASE.

## [1.18.3] - 2026-09-13 (`bluexport_api.sh`)

### Fixed

- **The cleanup match was an unanchored substring, so in the 21:00 hour it hit the year — and this
  one affected `-a` as well as `-x`.** 1.18.2 gave the hourly token a leading underscore so it
  could only match a capture name's time segment. It could not: **a capture name's date begins
  right after an underscore too**, so `_20` matches `NAME_2026-09-13_1400`.

  Where an LPAR has both an hourly rotation and a nightly keep, running hourly cleanup in the
  21:00 hour selected the *nightly* image — `head -n1` takes whichever the API lists first — and
  deleted it, leaving the hourly one it was meant to remove. One hour a day, every day, for as
  long as the year begins `20`.

  **The anchor is "not followed by another digit"**, not a suffix comparison. Reading the Cloud
  Object Storage path before changing it is what settled that: an object key carries a suffix
  (`NAME_20.ova`), so `endswith` would have failed on the path that most needed fixing. "Not
  followed by a digit" is exactly the property separating `NAME_20` and `NAME_20.ova` from
  `NAME_2026-…`, and it holds whatever suffix a key has.

  Applied **only when the token is a bare hour**, via a new `old_is_hour` flag. The
  `daily`/`weekly`/`monthly` tokens are full `%Y-%m-%d` dates matched against
  `NAME_YYYY-MM-DD_HHMM` — the date is not at the end and the token is long enough not to collide
  by accident — so those paths keep `contains` and their behaviour is unchanged.

Found while verifying 1.18.2's fix rather than by looking for it, which is why it is a separate
release: the one-character change was correct and necessary and did not close the class.

## [1.18.2] - 2026-09-13 (`bluexport_api.sh`)

### Fixed

- **`-x` with `hourly` could delete the capture it had just taken.** `-a` and `-x` computed the
  token used to find the previous capture for cleanup one character apart — `"+_%H"` and `"+%H"` —
  and `delete_previous_img` matches that token as a plain, unanchored substring before taking the
  first hit.

  Every capture name carries a full ISO date, so a bare two-digit hour matches the *date* as
  readily as the time. At 14:00 on the 13th, `13` matched `NAME_2026-09-13_1400` — the capture the
  run had just finished making — in preference to `NAME_2026-09-13_1300`, the one meant for
  cleanup. The new image was deleted, the old one left behind, and the run reported success.

  Nor was it only the day of the month: the token is the previous hour, `00`–`23`, matched against
  a string containing the year, month and day. In 2026 the year alone supplies `20`, `02` and `26`,
  so the 21:00, 03:00 and 10:00 hours collided with every image, every day.

  It needed `-x` rather than `-a`, with `hourly` rather than the other four recurrences — the
  narrowest corner of the flag matrix — and the damage was a deleted image rather than an error,
  which is why it had not been seen.

### Known, not fixed here

- **The cleanup match is still an unanchored substring, and in the 21:00 hour it hits the year.**
  A capture name's date begins right after an underscore too, so `_20` matches
  `NAME_2026-09-13_1400`. Where an LPAR has both an hourly rotation and a nightly keep, the
  nightly image is the one deleted. **This affects `-a` as well as `-x`**, and it is one hour a
  day for as long as the year begins `20`.

  Not fixed in this release deliberately: unlike the above it changes `-a`'s currently-working
  path and the Cloud Object Storage matcher, and it should be decided on its own rather than
  carried along with a one-character fix. Anchoring the hourly comparison — `endswith` rather than
  `contains` — is the shape of it.

Both were found while porting these paths to a companion project, by reading each line closely
enough to reproduce it, and both were reproduced against this script's own `jq` before being
written down.

## [1.18.1] - 2026-09-11 (`bluexport_api.sh`)

### Fixed

- **The ASP flush's error check could never fire, and a flush that did not happen looked exactly
  like one that did.** `flush_asps` ran `CHGASPACT ... OPTION(*FRCWRT)` piped to `tee` and then
  tested `$?` — which after a pipeline is the *last* command's status, so it read `tee`, and `tee`
  succeeds whenever it can write the log. An SSH failure, a `CHGASPACT` IBM i refused, a partition
  that had stopped answering: all of them left `$?` at `0`, the `abort` never ran, and
  `do_snap_create` went on to take the snapshot.

  That is what the flush is *for*. Without it the snapshot captures disk the partition has not
  finished writing to, the snapshot still completes at 100%, and the damage only surfaces when it
  is restored and the partition IPLs abnormally — by which point nothing points back at the flush.
  Someone who knew the flush could fail would check the log, and the log said it ran.

  The status is now captured before anything is piped (POSIX, not `PIPESTATUS`, which is a
  bashism). **Applied at all four flush sites, not two:** the two remote ones had the dead guard;
  the two local ones had no guard at all. The abort message no longer blames the SSH connection
  either — a refused `CHGASPACT` is the likelier failure and reads nothing like a timeout.

- **`-snapdel` aborted on the first workspace that had snapshots but not the one asked for.** The
  sweep across workspaces is there, but its guard tested whether the workspace had *any* snapshots
  rather than whether it had *this* one. A workspace holding unrelated snapshots therefore fell
  through to `do_snap_delete`, which looks the name up in that workspace's list, does not find it,
  and aborts — ending the run before the workspace actually holding the snapshot is reached.

  It worked every time with one workspace, or with snapshots in only one, which is why it had not
  been noticed. With a second workspace ahead of the target's, the same command reported that a
  snapshot which exists does not.

- **The snapshot-create watch never exited when the snapshot left the list.** `select` yielded
  nothing, the percentage was coerced to `0`, and `while [ "$snap_percent" -lt 100 ]` stayed true
  forever — an unbounded spin at ten-second intervals, after `flush_asps` had already run, leaving
  the partition flushed and the operator waiting on a snapshot that would never report.
  `do_snap_restore` checks for exactly this and aborts; the create watch now does too.

All three were found while porting these paths to a companion project, by reading each line
closely enough to reproduce it rather than transliterating it. Each bullet above is self-contained;
nothing here depends on a document you cannot see. No behaviour changes beyond the three fixes, no
new flags, and nothing that alters the shape of any API call.

## [1.18.0] - 2026-08-28 (`bluexport_api.sh`)

### Added
- `-vsidetails` — the compute and licensing of every LPAR in every configured workspace, from the
  data `pvm-instances` already returns and nothing else was reading: **memory**, **processors** and
  their type, **virtual cores**, **system type**, and the **IBM i software licences**.

  The licences print as a comma-separated list of the ones that are ON — `ibmiCSS, ibmiPHA` — rather
  than as four true/false columns. A consultant reads that faster, and an LPAR with none prints `-`
  instead of four `false`s that look like a fault. `ibmiRDSUsers` is carried separately because it
  is a count, not a flag.

  Follows the same shape as `-snaplsall`: loop the workspaces, resolve the base URL from the CRN's
  region, one TSV line per row read back through `while IFS=$'\t' read -r`. No `mapfile`, no
  `readarray`, nothing outside what the rest of the script already relies on, so it runs under PASE
  on IBM i like everything else here.

## [2.2] - 2026-08-28 (`bluexscrt_config_api.sh`)

### Fixed
- `rc_list_powervs()` asked the Resource Controller for `resource_id=power-iaas`. That parameter
  takes the **service's catalog GUID**, not its name, and the name matches nothing — so the call
  returned `200 OK` with zero rows rather than an error. Anything reading it would have concluded
  the account holds no PowerVS at all. Now sends `abd259f0-9990-11e8-acc8-b9f54a8f1661`, verified
  against a real account: with the name, 0 rows; with the GUID, every workspace.

  The function is not called from anywhere today, which is why this survived — it is reachable
  only if someone wires it up, and it would have failed silently the moment they did. Found while
  reviewing workspace discovery.

  Two traps are now recorded in a comment above it: PowerVS **sub-resources** (`power-iaas.image`,
  `.network`, `.network-interface`, `.network-security-group`, `.pvm-instance`, `.volume`) *do*
  come back from an unfiltered `type=service_instance` listing while the **workspaces do not**, so
  filtering that listing on a CRN containing `:power-iaas:` finds ninety things and misses every
  workspace; and the listing pages at 100 with a `.next_url` that this function does not follow.

## [1.17.0] - 2026-08-25 (`bluexport_api.sh`)

### Fixed
- `-vsisrcmon` — and therefore `-vsistart`, which delegates its entire monitoring phase to it — no longer refreshes nothing and polls forever. It had none of the three mechanisms `job_monitor()` and `wait_for_job()` have had since captures started outliving their IAM token.
  - **The IAM token is now refreshed**, proactively every 45 minutes and on any `401`. Previously, once the ~60-minute token expired, the API returned an error body with no `.status` field, `jq -r '.status // "UNKNOWN"'` rendered that as the literal string `UNKNOWN`, and the monitor aborted reporting *"VSI … entered UNKNOWN status. The LPAR/VSI is not starting."* — a false diagnosis that sent the operator to look at a perfectly healthy LPAR. A large IBM i IPL after an abnormal end running past the hour is routine, not exotic.
  - **Unreadable responses are now counted and bounded** — ten consecutive failures, 30 seconds apart, then a stop that states plainly that this is an API/connectivity failure and *not* a statement about the VSI. Previously they retried forever, 15 seconds apart, with no counter and nothing said about why.
  - **The monitor now has an overall time bound**, four hours by default. Previously an IPL that never reached SRC `00000000` — a hung IPL, the wrong boot mode, a B-side problem — polled until somebody killed the process.

### Added
- `BLUEXPORT_SRCMON_TIMEOUT` environment variable overrides the `-vsisrcmon` time bound, in seconds, without editing the script. A timeout is reported as a timeout, never as a failed IPL, and re-running the same command resumes monitoring.
- `ins_get_code()`, a variant of `ins_get()` that appends the HTTP status code as a trailing line, using the same idiom `job_get()` already uses. Kept as a separate function rather than changing `ins_get()`, whose nine other callers parse a bare JSON body and would all break on a trailing line.

### Changed
- The `UNKNOWN` status branch in `-vsisrcmon` is now reached only when the API answered `2xx` and the status it reported is literally `UNKNOWN`. It is no longer the catch-all for every unreadable response, so that abort now means what it says.

## [1.16.0] - 2026-08-10 (`bluexport_api.sh`)

### Added
- Every flag that takes at least one argument now prints a per-parameter breakdown (name + description) when the argument count is wrong, and via a new `-h -FLAG` detailed-help mode (e.g. `bluexport_api.sh -h -imgimport`). The general `-h` summary is unchanged.

## [2.1] - 2026-08-10 (`bluexscrt_config_api.sh`)

### Added
- `-dellpar`/`-addlpar` now print a per-parameter breakdown on a wrong argument count, and via a new `-h -FLAG` detailed-help mode (e.g. `-h -addlpar`).

## [1.15.0] - 2026-08-06 (`bluexport_api.sh`)

### Added
- `-ji WORKSPACE`: re-attach monitoring to the last image import job PowerVS has on record for a workspace, without resubmitting - useful after a lost SSH session or when the import was submitted from a different machine. No job ID is stored locally; queries PowerVS's "get last cos-image import job" endpoint directly.
- `-je IMAGE_NAME`: same, for the last image export job for a given image (searches every workspace by name, same as `-imgexport`/`-imgdel`).
- Both distinguish `400`/`401`/`403`/`404`/`500`/other HTTP responses from PowerVS with a specific message each, rather than reporting every failure as "no job history found."

## [1.14.0] - 2026-08-06 (`bluexport_api.sh`)

### Added
- `-imgexport IMGNAME BUCKET BUCKET_REGION CURRACCOUNT|OTHERACCOUNT [HMAC_JSON_FILE]`: export a boot image from a workspace's image catalog to a COS bucket, mirroring `-imgimport` in reverse (image resolved by name, searched across every workspace, same as `-imgdel`). Supports cross-account export via HMAC keys, same JSON format as `-imgimport` (see new `hmac_keys_example.json`).
- 409/"already running" detection for both `-imgimport` and `-imgexport`: PowerVS only allows one import/export operation per workspace at a time; a rejection for this reason now gets a specific, clear message instead of a generic API error.

### Changed
- **`-imgimport` now blocks until its PowerVS job completes and can exit non-zero.** Previously it returned immediately after submitting the job (fire-and-forget) and always exited `0`. It now uses the new `wait_for_job()` poller (copies `job_monitor()`'s proven polling/retry logic without any capture-specific behavior) to monitor the job to completion, the same way `-imgexport` does, and exits `1` on failure. **Upgrade note:** any cron job or script that calls `-imgimport` and assumed an immediate, always-zero exit should be reviewed - a run can now take as long as the underlying PowerVS import job (potentially 30-60+ minutes) and may exit non-zero.

### Fixed
- `-imgimport ... OTHERACCOUNT`: `load_hmac_keys()` was called but never defined anywhere in the script, so this path has never worked - it always failed with "Missing COS HMAC accessKey/secretKey". Now implemented.
- `abort()` gained an optional exit-code argument (default `0`, fully backward compatible with every existing call site) so genuine failures in `-imgimport`/`-imgexport` can be distinguished from success via `$?`.

## [2.0] - 2026-08-05 (`bluexscrt_config_api.sh`)

### Added
- LPAR discovery (`-updlpars`, and transitively `-updws`/`-createconfig`) is no longer IBM i-only: every LPAR in every configured workspace is now discovered and classified as `os`: `ibmi` | `aix` | `linux` | `other` (raw API value kept in `osDetail`). Unrecognized `osType` values classify as `other`, never assumed `linux`.
- `create_vsi_user_from_json` (optional step of `-createconfig`) filters to `os == ibmi` only, since SSH user provisioning via `DSPUSRPRF`/`CRTUSRPRF` is IBM i-only CL; skipped non-IBM i entries are reported by count.

### Changed
- **Breaking:** `-addlpar` now requires a 5th argument, `OS` (`ibmi|aix|linux|other`). Old 4-argument invocations now fail with a syntax error instead of silently assuming `ibmi`.

### Upgrade notes
- Run `-updlpars` once after upgrading to backfill `os`/`osDetail` on any `.systems[]` entry that predates this field (until then, such entries are treated as `ibmi` wherever read, since that was the only OS ever stored before).

## [1.13.0] - 2026-08-05 (`bluexport_api.sh`)

### Added
- `CHGASPACT` (the IBM i ASP-flush before snapshot create, volume clone execute, and image/cloud-storage capture) now only runs when the target LPAR's `os` (from `.systems[]`) is `ibmi`. For `aix`/`linux`/`other` targets, the flush is skipped with a log message, and the IBM i-only ping+SSH+`WRKCFGSTS` iASP-discovery step inside `get_iASP_name` is skipped entirely - no SSH connectivity or key is required for non-IBM i targets in these 3 operations.
- Purely additive: any installation with only IBM i entries in `.systems[]` sees no behavior change (missing `os` field falls back to `ibmi`).

## [1.12.2] - 2026-08-05 (`bluexport_api.sh`)

### Changed
- `spin_wait`'s spinner no longer prefixes the rotating character with `###` — cleaner terminal output during job-monitor wait phases.

## [1.6] - 2026-08-05 (`bluexscrt_config_api.sh`)

### Fixed
- `cos_ins_ls` (introduced in 1.5's pagination fix) crashed `-updlpars`/`-createconfig` outright: it passed each full API page (and a growing accumulator) to `jq` via `--argjson`, which puts the JSON on the process's command-line argument list. A real account's `resource_instances` page (even a single one, at `limit=100`) was large enough to hit the OS's `ARG_MAX` ("Argument list too long"), and under `set -e` that killed the whole script with no visible error (the failing jq's stderr was swallowed into `$log_file` by the caller's redirect). Fixed by staging each page's `.resources[]` into a temp file instead and merging all pages with `jq -s 'add'` (which reads from files, not argv) - reproduced the exact failure with a 3MB synthetic page and confirmed the new approach handles it (and merges correctly across pages) before shipping.

## [1.5] - 2026-08-05 (`bluexscrt_config_api.sh`)

### Fixed
- `cos_ins_ls`: the Resource Controller "list resource instances" call only ever read page 1 (API default page size is small), so any Cloud Object Storage instance sitting past the first page was silently invisible to `.cos_instances` refresh - looked identical to "account has zero COS instances". Now paginates through `next_url` (with `limit=100`) until exhausted and merges every page before filtering by CRN.
- `run_updlpars_api` / `-createconfig`: the "No Cloud Object Storage instances found" warning now also reports how many resource instances were actually scanned, to distinguish a real "API/permission problem, nothing came back at all" from "resources came back, but none matched the `:cloud-object-storage:` CRN filter" (e.g. if IBM ever renames the CRN service segment).

### Changed
- `run_updlpars_api`: per-workspace log line no longer stays silent when a workspace's IBM i LPARs are unchanged. Now explicitly reports `"Workspace 'X': N IBM i instance(s) confirmed, no changes."` (or `"N new IBM i instance(s) added, M confirmed unchanged."` when something new was found), instead of leaving it ambiguous whether the run actually did anything for that workspace.

## [1.4] - 2026-08-05 (`bluexscrt_config_api.sh`)

### Added
- `-updws` flag: refreshes PowerVS workspaces from IBM Cloud APIs, mirroring `-updlpars`. Discovers workspaces across all known regions, adds new ones (prompting for a short name), refreshes crn/name for already-known workspaces (matched by workspace ID, so the existing short-name key is preserved), and removes workspaces from `.workspaces` that no longer exist in IBM Cloud. As a safety guard, removal is skipped entirely if no workspace at all was returned by any endpoint (avoids wiping `.workspaces` on a transient API/network failure). If any new workspace was found, automatically runs `-updlpars` at the end to populate the new workspace's LPARs.
- `-updws`: when a workspace is removed for no longer existing in IBM Cloud, any LPAR left in `.systems[]` still pointing at that workspace is now also removed (it's orphaned - the workspace it belongs to is gone) and logged individually.

## [1.12.1] - 2026-08-04

### Fixed (`bluexport_api.sh`)
- `-a`/capture start: when the capture API rejects the request (e.g. another capture already running on the same VSI), the response has no `.id` field. `jq -r '.id'` was rendering that as the literal string `"null"`, which passed the existing `[[ -z "$job_id" ]]` check, so the script proceeded straight into `job_monitor` polling a job that never existed (10 pointless "HTTP 404" retries before giving up). `ins_cap` now surfaces the HTTP status, and both call sites validate the response and abort immediately with the actual API error message instead. `job_monitor`'s job-id checks also now reject the literal string `"null"` as a defensive second layer.

## [1.12.0] - 2026-08-04

### Added (`bluexport_api.sh`)
- `job_monitor`'s poll waits (queued/running/still-running/transient-retry) now show a spinner with a countdown on an interactive terminal, so a long capture/export doesn't look stuck during the 30-60s waits between status checks. Falls back to a plain `sleep` (no control characters) when output isn't a tty, so log files and IBM i batch/spool output are unaffected.

## [1.11.0] - 2026-08-04

### Fixed (`bluexport_api.sh`)
- `-a`/`-j` job monitoring loop (`job_monitor`) could abort a healthy, in-progress capture/export because the IBM Cloud IAM access token (fetched once at startup, ~3600s TTL) expired mid-poll. The resulting 401 response has no `.status.state` field, which the old code treated as "no job running" and aborted on immediately.

### Added (`bluexport_api.sh`)
- IAM token retrieval extracted into `get_iam_token()`, now called proactively every 45 minutes from inside `job_monitor` (and reactively on any HTTP 401 from `job_get`) so long-running jobs never hit an expired token
- `job_monitor` now tolerates transient `job_get` failures (network errors, non-2xx HTTP, unparsable JSON) with up to 10 retries at 30s intervals before aborting, instead of aborting on the first bad response
- `job_get` now sets connection/max-time timeouts and surfaces the HTTP status code to the caller

## [1.10.2] - 2026-05-11

### Fixed
- `-vsisrcmon`: Added detection for UNKNOWN status during monitoring. When VSI enters UNKNOWN status (e.g., during shutdown while monitoring START, or other abnormal states), monitoring now terminates with an appropriate message indicating the LPAR/VSI is not starting (START mode) or not shutting down properly (SHUTOFF mode)

## [1.10.1] - 2026-05-05

### Fixed (`bluexport_api.sh`)
- `-vsistart` error message incorrectly referenced the flag as `-startvsi`
- Config file missing message used `$bluexscrt` (not yet loaded at that point) instead of `$conf_file`, resulting in an empty variable in the output
- "Iniciating Job Monitorization" corrected to "Initiating Job Monitoring"

### Fixed (`bluexscrt_config_api.sh`)
- Tool name throughout the file was `bluexscrt_config.api` (dot notation) instead of `bluexscrt_config_api.sh`
- Copyright year range was `2025-2025`; corrected to `2025-2026`
- `usage()` and `-createconfig` wizard referred to `bluexport_conf.json`; correct name is `bluexport_api_conf.json`
- END marker for `get_base_url_for_workspace` function was mistakenly written as START

### Changed (`bluexport_api.sh`)
- Help and header comment for `-a` / `-x`: clarified that `hourly` and `daily` are only valid with `image-catalog`; documented `-ta` / `-tx` test mode inline
- Help for `-snapcr` and `-snapupd`: explained meaning of `0` placeholder for optional arguments
- Help for `-vclonedel`: clarified behaviour of `0` (keep cloned volumes) vs `delete_volumes` (also delete cloned volumes)
- Help for `-vclone`: `STORAGE_TIER` replaced with explicit `tier0|tier1|tier3|tier5k` (distinct from `-vchtier` which accepts `0|1|3|5k`)
- Help for `-bucketlsobjs` and `-bucketdelobj`: marked as interactive (guided selection)
- Help for `-restorefromarchive`: documented all `ARCHIVE_TYPE` options (Bulk | Standard | Accelerated) and default values
- Help for `-grscancelfailover`: rewritten for clarity ("resync from master to aux, reactivate master→aux replication")
- Help for `-vsistart`: "IPL VSI" expanded to "IPL/Start VSI" with inline note
- `-imgimport` parameter renamed from `HMACKEYS-JSON-FILE-PATH-NAME` to `HMAC_JSON_FILE` in help, header comment, and README
- `README.md`: added `-insvchtier` command and `TIER_TO_CHANGE_TO` values to Volume Tier section
- `README.md`: `-vclone` usage updated to show explicit tier values
- `CHANGELOG.md`: "Acelerated" typo corrected to "Accelerated" (two occurrences in help and header)

### Changed (`bluexscrt_config_api.sh`)
- `usage()`: expanded `-v` description; added `-h | --help` entry; clarified that `-createconfig` also discovers COS instances; clarified `-addlpar` `WORKSPACE_SHORT` parameter; documented that `-updlpars` also refreshes `cos_instances`
- Added `-h | --help` to the `case` dispatcher (previously fell through to `*` with exit 1)

## [1.10.0] - 2026-04-28

### Added
- `-imgimport` flag to import images from IBM Cloud Object Storage into a PowerVS workspace image catalog using the native `/cos-images` API
- Support for explicit COS bucket region (`BUCKET_REGION`) to correctly target COS endpoints during image import
- Support for explicit imported image name using `IMGNAME_WS`
- Support for image import storage tier selection: `tier0`, `tier1`, `tier3`, `tier5k`
- Support for current-account and cross-account COS image import using `CURRACCOUNT|OTHERACCOUNT`
- HMAC JSON parsing for cross-account imports using IBM Cloud COS Service Credentials format: `.cos_hmac_keys.access_key_id` and `.cos_hmac_keys.secret_access_key`
- Validation of HMAC JSON structure with explicit error handling for invalid COS credentials
- Help text explaining how to obtain HMAC keys from IBM Cloud COS Service Credentials

- Professional repository structure with `.gitignore`, `CONTRIBUTING.md`, and `CHANGELOG.md`
- Issue and pull request templates
- `.editorconfig` for consistent code formatting
- Example configuration files in `examples/` directory
- Badges in README for license, version, and maintenance status

## [1.9.0] - 2025-03-30

### Added
- VSI operations: start, boot mode, operating mode, and task execution
- SRC monitoring for IBM i systems
- Volume attach/detach operations by common name
- Enhanced error handling and logging

### Changed
- Improved API rate limiting handling with exponential backoff
- Enhanced GRS operations with better safety checks
- Updated documentation with more examples

### Fixed
- Rate limiting issues in high-frequency operations
- Error handling in snapshot restore operations

## [1.2.0] - 2025-01-15

### Added
- `bluexscrt_config_api.sh` - Interactive configuration generator
- Support for multiple PowerVS workspaces
- Automatic workspace discovery via API
- LPAR management commands (`-addlpar`, `-dellpar`, `-updlpars`)

### Changed
- Configuration file format to JSON for better structure
- Improved secrets management

## [1.0.0] - 2024-12-01

### Added
- Initial release of bluexport_api.sh
- VSI lifecycle operations (start, stop, monitor)
- Snapshot management (create, update, delete, restore)
- Captured images management (list, delete)
- Volume clones (create, delete, list)
- Volume tier changes
- GRS (Global Replication Services) orchestration
- IBM i operational tasks support
- Cloud Object Storage (COS) integration
- Multi-workspace support
- Comprehensive logging system
- API-driven automation without IBM Cloud CLI dependency

### Features
- **Snapshots**: Full lifecycle management with multi-workspace awareness
- **Volume Clones**: Create and manage clones with tiered storage support
- **GRS Operations**: Volume group creation, onboarding, and deletion
- **VSI Operations**: Boot modes, operating modes, and IBM i tasks
- **COS Integration**: Bucket and object management
- **Monitoring**: SRC monitoring and job tracking

---

## Version History Summary

- **1.10.x**: Image import from COS, repository improvements, help and bug fixes
- **1.9.x**: VSI operations and enhanced monitoring
- **1.2.x**: Configuration management improvements
- **1.0.x**: Initial release with core functionality

---

## Migration Notes

### Upgrading to 1.10.0

No breaking changes. New features are additive.

### Upgrading to 1.9.0

No breaking changes. New features are additive.

### Upgrading to 1.2.0

**Configuration File Changes:**
- Old format: Shell variables in `bluexscrt` file
- New format: JSON structure in `bluexscrt_*.json`
- Use `bluexscrt_config_api.sh -createconfig` to generate new format

**Migration Steps:**
1. Backup existing configuration
2. Run `./bluexscrt_config_api.sh -createconfig`
3. Populate with your existing values
4. Test with non-production resources
5. Update automation scripts to use new config path

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on how to contribute to this project.

---

## Support

For issues, questions, or contributions:
- **Issues**: https://github.com/rqmartins73/bluexport_api/issues
- **Email**: ricardo.martins@bluechip.pt
- **Documentation**: See [README.md](README.md)

---

[Unreleased]: https://github.com/rqmartins73/bluexport_api/compare/v1.10.1...HEAD
[1.10.1]: https://github.com/rqmartins73/bluexport_api/compare/v1.10.0...v1.10.1
[1.10.0]: https://github.com/rqmartins73/bluexport_api/compare/v1.9.0...v1.10.0
[1.9.0]: https://github.com/rqmartins73/bluexport_api/compare/v1.2.0...v1.9.0
[1.2.0]: https://github.com/rqmartins73/bluexport_api/compare/v1.0.0...v1.2.0
[1.0.0]: https://github.com/rqmartins73/bluexport_api/releases/tag/v1.0.0