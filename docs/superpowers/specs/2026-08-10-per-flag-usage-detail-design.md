# Design: Per-Flag Parameter Detail (usage_X() functions)

## Motivation

Every flag's "too many or too few arguments" error currently prints only the one-line `Syntax: ...` string with bare parameter names (e.g. `IMGNAME BUCKET BUCKET_REGION ...`). A user who mistypes a command has to already know what each positional parameter means. The user wants a per-parameter breakdown (name + description) shown when this happens, for every flag in both scripts (~44 total: 38 in `bluexport_api.sh`, 6 in `bluexscrt_config_api.sh`).

## A. Shared mechanism: `usage_<flag>()`

Every flag that takes at least one argument gets a dedicated function, e.g. `usage_imgimport()`, `usage_vclone()`, `usage_creategrs()`, `usage_addlpar()`. Each function `echoscreen`s a nested parameter breakdown, one parameter per pair of lines, in the format already established by the existing `-imgexport` help block:

```bash
usage_imgimport() {
	echoscreen "  IMGNAME:"
	echoscreen "    COS object filename to import (e.g. myimage.ova.gz)."
	echoscreen "  BUCKET:"
	echoscreen "    COS bucket name."
	echoscreen "  BUCKET_REGION:"
	echoscreen "    IBM COS S3 endpoint region (e.g. eu-es, us-east)."
	echoscreen "  WORKSPACE_TO_IMPORT:"
	echoscreen "    Target PowerVS workspace, short or full name."
	echoscreen "  IMGNAME_WS:"
	echoscreen "    Name to give the imported image in the catalog."
	echoscreen "  STORAGE_TYPE:"
	echoscreen "    tier0|tier1|tier3|tier5k."
	echoscreen "  CURRACCOUNT|OTHERACCOUNT:"
	echoscreen "    COS account type."
	echoscreen "  HMAC_JSON_FILE:"
	echoscreen "    Optional; required only for OTHERACCOUNT."
}
```

**Presentation convention:** optional parameters must say so explicitly in their description (e.g. `HMAC_JSON_FILE: Optional; required only for OTHERACCOUNT.`), and enum-style parameters list their valid values (e.g. `STORAGE_TYPE: tier0|tier1|tier3|tier5k.`) — never leave either implicit.

**Every `echoscreen` call inside a `usage_X()` function is made WITHOUT the second `"1"` argument** — screen-only, never written to the log file. This is a deliberate, explicit requirement from the user: the detail is only useful interactively; the log stays exactly as concise as it is today (the final `abort()` call still writes its normal single-line syntax message to both screen and log, unchanged).

Flags that take **zero** arguments (`-h`, `-v`/`--version`, `-viewscrt`, `-imglsall`, `-bucketslsall`, and similar list/no-arg commands) get **no** `usage_X()` function — there is nothing to describe. Their existing "too many arguments" check (only "too many" is possible when 0 are expected) is left untouched.

## B. Call sites

1. **Argument-count error path** (existing `if [ $# -lt N ]`/`if [ $# -gt N ]`/`if [[ $# -ne N ]]` checks in every case block): call `usage_<flag>` immediately before the existing `abort "... Syntax: ..." [1]` call. The `abort()` call itself is unchanged — same message, same log-writing behavior as today. Only a new call to `usage_<flag>` is inserted before it.
2. **New `-h -FLAG` mode**: a new branch in the `-h | --help | -help)` case handling a second argument. Syntax: `bluexport_api.sh -h -FLAGNAME` (the flag name as normally typed, with its leading hyphen — e.g. `bluexport_api.sh -h -imgimport`). If `-FLAGNAME` matches a known flag with a `usage_X()` function, call it (screen-only, same as the error path) and exit 0 (this is a successful help request, not an error — use `abort "..." ` with no exit code argument, i.e. the existing default-0 behavior, matching how the current bare `-h` already exits via `abort` after printing help). If the flag is unrecognized (or is a zero-argument flag with no `usage_X()`), abort with `"Unknown flag for detailed help: X. Run bluexport_api.sh -h for the full command list."` and exit 1.

   **Aliases:** for shared case aliases (e.g. `-a | -ta`, `-x | -tx`), every accepted alias must be recognized by the `-h -FLAG` lookup and dispatch to the same `usage_X()` function — e.g. both `bluexport_api.sh -h -a` and `bluexport_api.sh -h -ta` call `usage_a()`. The lookup's own case/if-chain must list every alias explicitly (mirroring the exact alias set already accepted by that flag's own case-dispatch branch), not just the first/primary one.

   **Argument count:** `-h | --help | -help` accepts at most one additional argument. `-h` alone → full help, exit 0. `-h -FLAG` → detailed flag help, exit 0. `-h -FLAG EXTRA` (or more) → error, exit 1 (e.g. `"Too many arguments!! Syntax: bluexport_api.sh -h [-FLAG]"`). This prevents a mistyped trailing argument (`-h -imgimport qualquer-coisa`) from being silently accepted. Applies identically in `bluexscrt_config_api.sh`.
3. **General `-h`** (no second argument): unchanged — still the existing single-screen, one-line-per-command dump.

## C. Scope

Both `bluexport_api.sh` (38 flags) and `bluexscrt_config_api.sh` (6 flags) get this treatment. Every flag that takes at least one argument gets a `usage_X()` function; the exact per-parameter descriptions require understanding what each parameter actually does (not purely mechanical) — this content work is grouped into implementation-plan tasks by functional area (images, snapshots, volume clone, GRS, VSI operations, buckets, `bluexscrt_config_api.sh`'s own flags, etc.), each independently reviewed, rather than enumerated in full here.

Flags that share a case branch (e.g. `-a | -ta`, `-x | -tx`) get one `usage_X()` function covering both aliases (named after the primary/first alias).

## D. Versioning

Purely additive (new functions, new optional `-h -FLAG` mode, no existing behavior changed for any flag's happy path or its current error message) → MINOR bump for each script touched.

## Non-goals

- General `-h` (no argument) is not restructured or lengthened — stays the current one-line-per-command summary.
- No change to any flag's actual argument-count validation logic (`-lt`/`-gt`/`-ne` checks) — only a new `usage_X()` call inserted before the existing `abort()`.
- No change to `abort()` itself.
- Zero-argument flags are explicitly out of scope for `usage_X()` functions (nothing to describe).
