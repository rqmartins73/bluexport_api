# Multi-OS LPAR support (IBM i / AIX / Linux) — design

Status: approved by user, pending spec review
Date: 2026-08-05
Repo: bluexport_api (`bluexport_api.sh`, `bluexscrt_config_api.sh`)

## Problem

`bluexport_api.sh`/`bluexscrt_config_api.sh` were built exclusively for IBM i PowerVS LPARs. The tool's `.systems[]` discovery only ever kept IBM i instances (everything else was silently discarded by the existing `osType`/`operatingSystem`/`softwareLicenses.ibmiCSS` classification in `run_updlpars_api`). Every VSI-targeting operation assumes the target is IBM i, in particular `flush_asps()` — which issues `CHGASPACT ASPDEV(...) OPTION(*FRCWRT)` (a real IBM i CL command, executed locally or via `system "..."` over SSH) — is called unconditionally before three operations: snapshot create, volume clone execute, and image/cloud-storage capture.

The user wants the tool to also manage AIX and Linux LPARs in the same PowerVS workspaces. For those, `CHGASPACT` (an ASP-flush concept that doesn't exist outside IBM i) must never run; everything else in the tool (GRS, volume tiers, VSI start/oper/task/srcmon, buckets, etc.) is already OS-agnostic and needs no change — confirmed with the user.

## Scope confirmed with user

In scope:
- Discovery (`-updlpars`, and transitively `-updws`/`-createconfig`) returns **all** LPARs in every workspace (ibmi/aix/linux/other), not just IBM i.
- `.systems[]` gains an `os` (normalized category) and `osDetail` (raw API value) field per entry.
- `-addlpar` gains a new **required** 5th argument, `OS` (`ibmi|aix|linux|other`) — breaking change, accepted by the user.
- The 3 CHGASPACT call sites (`do_snap_create`, `do_volume_clone_execute`, the capture/export flow near `bluexport_api.sh:6260-6274`) skip `flush_asps` (and the IBM i-only SSH/`WRKCFGSTS` iASP discovery inside `get_iASP_name`) unless `vsi_os == "ibmi"`.
- `create_vsi_user_from_json` (optional step of `-createconfig`, SSH-provisions a user via `DSPUSRPRF`/`CRTUSRPRF`) is filtered to `os == ibmi` entries only — out of scope to build AIX/Linux user provisioning now.

Explicitly out of scope (confirmed with user):
- GRS operations, `-vchtier`/`-insvchtier`, `-vclonedel`, `-deletegrs`, bucket operations, `-vsistart`/`-vsioper`/`-vsitask`/`-vsisrcmon` — already OS-agnostic (pure PowerVS API calls), no changes needed.
- AIX/Linux SSH user provisioning — not built now; those entries are just skipped (with a log line) in `create_vsi_user_from_json`.

## A. Data model — `.systems[]`

Each entry gains two new fields, alongside the existing `name`, `ip`, `pvmInstanceID`, `workspace`:

```json
{
  "name": "IBMi75M2", "ip": "172.26.2.5", "pvmInstanceID": "...", "workspace": "WSMAD2",
  "os": "ibmi", "osDetail": "V7R5M0 410 8"
}
```

- `os`: normalized category — `ibmi` | `aix` | `linux` | `other`. This is the field all CHGASPACT gating logic reads.
- `osDetail`: raw `osType`/`operatingSystem` value from the PowerVS API, informational only.

### Classification logic

Verified against real data pulled live from the user's PowerVS account (read-only `GET /pvm-instances`, all 6 workspaces, 2026-08-05):

```
WSFRA1: IBMiCC (osType=ibmi), IBMi75F1 (osType=ibmi), AIX (osType=aix)
WSMAD2: IBMi75M2 (osType=ibmi), IBMiCCDR (osType=ibmi), PAO (osType=rhel), nfs (osType=rhel)
```

Key finding: PowerVS never returns the literal string `"linux"` for `osType` — it returns the distro codename (`rhel`, presumably `sles` for SUSE). Classification must therefore be:

1. `ibmi` — reuse the existing detection in `run_updlpars_api` unchanged (`osType=="ibmi"`, or `operatingSystem` matching `ibmi|v7rXmY` case-insensitively, or `softwareLicenses.ibmiCSS==true` at either `.configuration.softwareLicenses` or `.softwareLicenses`).
2. `aix` — `osType=="aix"` (case-insensitive).
3. `linux` — `osType` (case-insensitive) matches a known Linux distro codename allowlist: `rhel`, `sles`, `suse`, `ubuntu`, `debian`, `centos`, `fedora`, `rocky`, `almalinux`, `oraclelinux` (extend the list if a new one is seen in practice).
4. `other` — everything else: no `osType`/`operatingSystem`/`softwareLicenses` signal at all, **or** an `osType` value present but not recognized by the allowlist above. Unknown values must never be assumed to be `linux` by elimination — `other` is the honest, safe default for anything not positively identified (user correction, 2026-08-05: guards against a future/unseen PowerVS `osType` being silently misclassified).

### Backward compatibility for pre-existing entries

Entries already in `.systems[]` from before this change have no `os` field. They are treated as `ibmi` wherever read (this was the only OS the tool ever added historically). This fallback is **read-only, in-memory** in `bluexport_api.sh` (see boundary note below) — the actual persisted fix is running `-updlpars` once after upgrading, which rewrites `os`/`osDetail` explicitly for every rediscovered entry. This is documented as a required upgrade step in the CHANGELOG/README, not silently handled.

### Read/write boundary (explicit architectural decision)

`bluexport_api.sh` never writes to `.systems[]` today — only `bluexscrt_config_api.sh` does (via `-updlpars`/`-addlpar`/`-dellpar`). This boundary is preserved: `bluexport_api.sh`'s fallback (`.os // "ibmi"`) is purely an in-memory read-time default for the current run, never written back. No new write capability is added to `bluexport_api.sh`.

## B. Discovery — `-updlpars`, `-updws`, `-createconfig`

`run_updlpars_api` (in `bluexscrt_config_api.sh`) stops filtering by IBM i:

- The per-instance loop that today computes `os_flag == "yes"/"no"` (used only to include/exclude) is replaced by the 4-way classification above, applied to **every** instance in every workspace — nothing is discarded.
- The existing-vs-new detection (match by `name`, case-insensitive) is unchanged; it now also preserves/refreshes `os`/`osDetail` alongside `ip`/`pvmInstanceID`/`workspace`.
- The per-workspace summary line (`"Workspace 'X': N confirmed, M new"`, added earlier this session) changes wording from "IBM i instance(s)" to "LPAR(s)" (generic), since it now counts all OSes.
- `-updws` needs no code change — it already calls `run_updlpars_api` at the end when new workspaces are found, and inherits the broadened behavior automatically.
- `-createconfig`'s step 6 call to `run_updlpars_api` also inherits the behavior automatically, no code change.
- `-dellpar` needs no change (removes by name, already OS-agnostic).

## C. `-addlpar` — new required `OS` argument

Syntax changes from:
```
-addlpar NAME IP PVM_ID WORKSPACE_SHORT
```
to:
```
-addlpar NAME IP PVM_ID WORKSPACE_SHORT OS
```

`OS` is validated against `ibmi|aix|linux|other` (case-insensitive, normalized to lowercase on write), following the same validation style already used elsewhere in the script (e.g. `-vsitask`'s TASK enum). Wrong argument count or an invalid `OS` value aborts with a clear message listing the accepted values. `osDetail` is left empty for manually-added entries (only auto-discovery populates it from the live API value — asking a human to type the raw API string by hand doesn't make sense).

This is a confirmed breaking change: any existing script/workflow calling `-addlpar` with the old 4-argument form will now get a syntax error instead of a silent `ibmi` assumption. Confirmed acceptable by the user.

## D. `check_locally_VSI_exists` / `get_iASP_name` — split API-status from IBM i-only SSH/CL

- `check_locally_VSI_exists` additionally reads `.os` for the matched system into a new global `vsi_os`. `vsi_os` is explicitly initialized empty (`vsi_os=""`) before the lookup, and only assigned — with the `// "ibmi"` backward-compatibility fallback — after the existing "VSI not found" check has already confirmed a matching entry exists. The fallback is never applied speculatively before that point (user correction, 2026-08-05).
- `get_iASP_name` keeps its existing structure (status fetch, then a local-execution branch and a remote-via-SSH branch, each with its own SHUTOFF check and early `return`) — that flow is OS-agnostic and unchanged. Only the tail of each branch — the ping+SSH+`system 'WRKCFGSTS CFGTYPE(*DEV) CFGD(*ASP)'` call that gathers iASP names — becomes conditional on `vsi_os == "ibmi"`. For `aix`/`linux`/`other`, that tail is skipped in both branches: `iasp_names` stays empty, and no SSH connectivity or key is required for those OSes in this code path.
- Test mode (`-ta`/`-tx`, `$test=1`) is unaffected — it already skips this whole block today.

### Deferred (explicitly out of scope for this iteration)

The user flagged a real, related risk: name-based `.systems[]` lookups (`check_locally_VSI_exists`, and the separate, largely-parallel `vsi_id_bluexscrt()` — both match purely on `.name`, case-insensitive, with no workspace/ID disambiguation) could misbehave if the same name exists in two different workspaces. Confirmed today's real JSON has no such collision, but broadening discovery to all OSes raises the odds (generic AIX/Linux hostnames repeating across workspaces). Fixing this properly — either merging the two lookup functions or adding ambiguity detection to both, plus scoping discovery's existing-vs-new matching to `name AND workspace` — touches roughly 28 call sites across the script and was explicitly deferred by the user to a future iteration ("para já não faças o meu ponto 2, tratamos disso noutra altura"). Not built as part of this feature.

## E. CHGASPACT gate at the 3 operations

At each of the three `flush_asps` call sites (`do_snap_create`, `do_volume_clone_execute`, the capture/export flow), the call becomes conditional:

```bash
if [[ "$vsi_os" == "ibmi" ]]; then
    flush_asps
else
    echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - VSI $vsi is $vsi_os - CHGASPACT not applicable, skipping ASP flush." "1"
fi
```

Where an existing `shutoff`-based guard already wraps the call (volume clone, capture), the `vsi_os` check is an **additional** condition, not a replacement — a SHUTOFF VSI still skips the flush regardless of OS, exactly as today.

## F. `create_vsi_user_from_json` — filter to `os == ibmi`

The `mapfile -t systems < <(jq -c '.systems[]?' "$CONFIG_JSON")` at `bluexscrt_config_api.sh:575` becomes:

```bash
mapfile -t systems < <(jq -c '.systems[]? | select((.os // "ibmi") == "ibmi")' "$CONFIG_JSON")
```

with an added notice for how many non-IBM i entries were skipped:

```bash
skipped_non_ibmi=$(jq '[.systems[]? | select((.os // "ibmi") != "ibmi")] | length' "$CONFIG_JSON")
if (( skipped_non_ibmi > 0 )); then
    echo "### Skipping $skipped_non_ibmi non-IBM i system(s) in .systems[] (SSH user setup is IBM i-only for now)."
fi
```

The rest of the function (user creation, SSH key deployment, `DSPUSRPRF`/`CRTUSRPRF`) is unchanged.

## G. Documentation

- `usage()` in `bluexscrt_config_api.sh`: `-updlpars` and `-addlpar` entries updated to describe all-OS discovery and the new `OS` argument.
- `README.md`: `-updlpars`/`-addlpar` sections updated; a note added to the export/snapshot/clone chapter explaining CHGASPACT only applies to IBM i LPARs.
- `CHANGELOG.md`: entry describing the behavior change, the `-addlpar` breaking change, and the required upgrade step ("run `-updlpars` once after upgrading to backfill the `os` field on pre-existing entries").
- Log messages at the 3 gated operations and in `create_vsi_user_from_json` (sections E, F) serve as the runtime-visible documentation of what happened and why.

## H. Testing plan

**Sandbox-verifiable (proves logic only, not PASE execution):**
- OS classification against synthetic instance JSON covering `ibmi`, `aix`, `rhel`, and a no-signal case (→ `other`).
- `-addlpar` argument/OS validation.
- The `vsi_os == ibmi` gating conditionals with mocked values.
- The `create_vsi_user_from_json` filter.

**Existing test-mode coverage (safe, no real IBM Cloud side effects):**
`-ta`/`-tx` (capture/export) already do a full dry run — they skip the real `ins_cap` call and `job_monitor` entirely. The new `flush_asps` gate sits directly behind that, so a dry run against the user's real AIX (`AIX`, workspace WSFRA1) or Linux (`PAO`/`nfs`, workspace WSMAD2) test instances validates the whole gating path with zero real IBM Cloud actions.

**No test-mode coverage — real actions, user has explicitly authorized testing against `AIX` and `PAO` (both confirmed disposable/test instances):**
`-snapcr` (snapshot create) and `-vclone` (volume clone execute) have no test mode (`test` is hardcoded to `0`); validating the OS gate for these two operations means actually creating a real snapshot/clone against `AIX` or `PAO` in the user's IBM Cloud account, and cleaning up afterward via `-snapdel`/`-vclonedel`.

**PASE**: this feature introduces no new external command, flag, or coreutils behavior — it reuses jq/bash patterns already present and working in the script (the `mapfile` pattern in `create_vsi_user_from_json` is unchanged from what's already in production; the only SSH/CL command touched, `WRKCFGSTS`/`CHGASPACT`, is the exact same call already proven on the user's PASE environment, just now conditional on `os == ibmi`). Per standing project guidance, this is not the same as confirming it on PASE — real verification on the IBM i box (and the AIX/Linux test instances) is required before this is considered done, and any construct that turns out to need adjustment will be flagged individually, not assumed.

## Versioning

`bluexport_api.sh` and `bluexscrt_config_api.sh` version independently (currently `1.12.1` and `1.6` respectively). Per the project's semver policy:

- `bluexscrt_config_api.sh` → **MAJOR** bump (`1.6` → `2.0`): `-addlpar`'s new required `OS` argument is a real breaking change (old 4-argument calls now error out instead of silently assuming `ibmi`).
- `bluexport_api.sh` → **MINOR** bump (`1.12.1` → `1.13.0`): the CHGASPACT gating is purely additive — any pre-existing installation with only IBM i entries in `.systems[]` sees no behavior change at all (missing `os` falls back to `ibmi`), so this isn't breaking for existing users. New capability (AIX/Linux support), not a compatibility break.

## Non-goals

- No AIX/Linux SSH user provisioning (`create_vsi_user_from_json` equivalent) is built now.
- No renaming of `-updlpars` (kept, behavior broadened per user's explicit choice).
- No change to any operation confirmed as already OS-agnostic (GRS, volume tiers, VSI start/oper/task/srcmon, buckets).
- No cross-workspace name-collision disambiguation (merging `check_locally_VSI_exists`/`vsi_id_bluexscrt`, ambiguous-match detection, or workspace-scoped discovery matching) — explicitly deferred by the user to a future iteration (see "Deferred" note under section D).
