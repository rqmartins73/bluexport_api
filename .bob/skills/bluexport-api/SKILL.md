---
name: bluexport-api
description: Use when working on or asking about the bluexport_api project — IBM Cloud PowerVS automation framework. Provides full context about the project structure, purpose, scripts, configuration, and conventions.
---

# bluexport_api — Project Memory

## What is this project?

`bluexport_api` is a **Bash automation framework** for **IBM Cloud Power Virtual Server (PowerVS)**, authored by **Ricardo Martins** (IBM Champion 2025|2026) at **Blue Chip Portugal**.

It manages PowerVS resources using the **native IBM Cloud REST APIs** — no IBM Cloud CLI dependency.

- **Repository**: https://github.com/rqmartins73/bluexport_api
- **Local path**: `/home/rqmartins/Git/bluexport_api`
- **License**: MIT
- **Language**: Bash (requires Bash 5.x+, `curl`, `jq` 1.6+)

---

## Files in the project

| File | Version | Purpose |
|---|---|---|
| `bluexport_api.sh` | 1.10.2 | Main automation script — all PowerVS operations |
| `bluexscrt_config_api.sh` | 1.2 | Interactive wizard to create/manage the JSON secrets/config file |
| `README.md` | — | Full documentation |
| `CHANGELOG.md` | — | Version history (semver) |
| `CONTRIBUTING.md` | — | Contribution guidelines |
| `SECURITY.md` | — | Security policy |
| `CODE_OF_CONDUCT.md` | — | Community code of conduct |
| `.editorconfig` | — | Code style consistency |
| `.github/ISSUE_TEMPLATE/bug_report.md` | — | GitHub issue template |

---

## Runtime configuration files (created at first run, NOT in repo)

| File | Location | Purpose |
|---|---|---|
| `bluexport_api_conf.json` | `$HOME/` | Main config — paths to secrets file, log files, temp files, snap_retention |
| `bluexscrt_*.json` | `$HOME/` (configurable) | Secrets file — IBM Cloud API key, COS credentials, SSH config, workspaces, systems |

### `bluexport_api_conf.json` structure (key fields)
```json
{
  "bluexscrt": "/home/user/bluexscrt_bcce.json",
  "log_file": "/home/user/bluexport.log",
  "job_log": "/home/user/bluex_job.log",
  "snap_retention": 2
}
```

### `bluexscrt_*.json` structure (key fields)
```json
{
  "apikey": "...",
  "access": { "accessKey": "...", "secretKey": "...", "bucketName": "...", "region": "eu-es" },
  "ssh": { "user": "bluexport", "keyPath": "/home/user/.ssh/bluexport_rsa" },
  "resourceGroup": "powervs",
  "workspaces": {
    "WSMAD2": { "crn": "crn:v1:...", "id": "...", "name": "My WS Madrid" }
  },
  "systems": [
    { "name": "ibmi75m2", "ip": "172.26.2.5", "pvmInstanceID": "...", "workspace": "WSMAD2" }
  ],
  "cos_instances": { "MyCOS": { "guid": "...", "crn": "..." } }
}
```

---

## Main script: `bluexport_api.sh`

### How it initialises
1. Reads `$HOME/bluexport_api_conf.json` → loads all path variables
2. Checks `bluexscrt` file exists
3. Gets IBM IAM token via `https://iam.cloud.ibm.com/identity/token` using the API key
4. Dynamically creates env vars for each workspace: `WSMAD2` (CRN), `WSMAD2ID`, `WSMAD2NAME`

### Key internal functions
| Function | Purpose |
|---|---|
| `echoscreen()` | Prints to stdout (TTY check) and optionally to log file (flag="1") |
| `abort()` | Logs error, closes log section, exits |
| `dc_vsi_list()` | Resolves workspace region and lists all VSIs; maps VSI name → ID |
| `delete_previous_img()` | Cleans up old images from image catalog and COS bucket |
| `chk_vol_rep()` | Enables replication on volumes if needed, waits until all are enabled |
| `chk_vol_mirror()` | Polls until all volumes with a given name prefix reach `consistent_copying` |
| `chk_on_status()` | Polls auxiliary volume onboarding until completion |
| `vg_is_sync_aux_to_master()` | Checks if VG is in aux→master syncing steady state |
| `vg_wait_sync_aux_to_master()` | Waits until VG reaches aux→master syncing state |

### REST API wrapper functions (curl calls)
These functions use env vars `$base_url`, `$CLOUD_INSTANCE_ID`, `$CRN`, `$PVM_ID`, `$VOL_ID`, etc.

| Category | Functions |
|---|---|
| Workspace | `ws_ls` |
| VSI/Instance | `ins_get`, `ins_ls`, `ins_act`, `ins_cap`, `ins_oper`, `ins_vol_ls`, `ins_vol_bdet` |
| Volume | `vol_ls`, `vol_get`, `vol_act`, `vol_att`, `vol_att_multi`, `vol_del`, `vol_bdel`, `vol_rcr` |
| Volume Clone | `vol_cl_cr`, `vol_cl_get`, `vol_cl_ls`, `vol_cl_del`, `vol_cl_st`, `vol_cl_ex`, `vol_cl_ca`, `vol_det_cl_cr`, `vol_det_cl_ls` |
| Volume Group (GRS) | `vg_cr`, `vg_ls`, `vg_get`, `vg_sd`, `vg_rcr`, `vg_act`, `vg_del`, `vg_upd` |
| Onboarding | `on_ls`, `on_cr`, `on_get` |
| Jobs | `job_ls`, `job_get` |
| Images | `img_ls`, `img_del`, `img_import_api` |
| Snapshots | `snap_ls`, `snap_cr`, `snap_del`, `snap_upd`, `snap_res` |
| COS | `list_object`, `object_delete`, `cos_ins_ls`, `cos_ls_buckets`, `cos_rest_arch` |
| Transit Gateway | `tg_gws`, `tg_cs`, `tg_pfs`, `tg_pfu`, `tg_pfc`, `tg_pfd` |

---

## CLI flags — `bluexport_api.sh`

### General
| Flag | Syntax | Description |
|---|---|---|
| `-v` / `--version` | `-v` | Show version as JSON |
| `-h` / `--help` | `-h` | Show full help |
| `-chscrt` | `-chscrt FILE` | Change secrets file in use (also prompts for log file path) |
| `-viewscrt` | `-viewscrt` | Show secrets file currently in use |

### Capture & Export
| Flag | Syntax |
|---|---|
| `-a` | `-a VSI_NAME IMAGE_NAME both\|image-catalog\|cloud-storage hourly\|daily\|weekly\|monthly\|single` |
| `-x` | `-x EXCLUDE_NAME VSI_NAME IMAGE_NAME both\|image-catalog\|cloud-storage ...` |
| `-ta` / `-tx` | Same as `-a`/`-x` but test mode (no actual capture) |
| `-j` | `-j VSI_NAME IMAGE_NAME` — monitor running capture job |

> Note: `hourly` and `daily` recurrence only valid with `image-catalog` destination.

### Snapshots
| Flag | Syntax |
|---|---|
| `-snapcr` | `-snapcr VSI_NAME SNAPSHOT_NAME 0\|"DESCRIPTION" 0\|"VOLUMES"` |
| `-snapupd` | `-snapupd SNAPSHOT_NAME 0\|NEW_NAME 0\|"DESCRIPTION"` |
| `-snapdel` | `-snapdel SNAPSHOT_NAME` |
| `-snapres` | `-snapres VSI_NAME SNAPSHOT_NAME` |
| `-snaplsall` | List all snapshots across all workspaces |

### Images
| Flag | Syntax |
|---|---|
| `-imglsall` | List all captured images across all workspaces |
| `-imgdel` | `-imgdel IMG_NAME` |
| `-imgimport` | `-imgimport IMGNAME BUCKET BUCKET_REGION WORKSPACE IMGNAME_WS STORAGE_TYPE CURRACCOUNT\|OTHERACCOUNT [HMAC_JSON_FILE]` |

### COS (Cloud Object Storage)
| Flag | Description |
|---|---|
| `-bucketslsall` | List all buckets for all COS instances |
| `-bucketlsobjs` | Interactive: list objects from a selected bucket |
| `-bucketdelobj` | Interactive: delete an object from a selected bucket |
| `-restorefromarchive BUCKET OBJECT [DAYS] [ARCHIVE_TYPE]` | Restore archived object (default: 3 days, Accelerated) |

### Volume Clones
| Flag | Syntax |
|---|---|
| `-vclone` | `-vclone REQUEST_CLONE_NAME VOLUME_BASE_NAME LPAR_NAME True\|False True\|False tier0\|tier1\|tier3\|tier5k ALL\|VOLUMES` |
| `-vclonedel` | `-vclonedel REQUEST_CLONE_NAME 0\|delete_volumes` |
| `-vclonelsall` | List all volume clones across all workspaces |

### Volume Tier
| Flag | Syntax |
|---|---|
| `-vchtier` | `-vchtier VSI_NAME VOLUMES_NAME 0\|1\|3\|5k` |
| `-insvchtier` | `-insvchtier VSI_NAME 0\|1\|3\|5k` — all volumes attached to VSI |

### GRS (Global Replication Services)
| Flag | Syntax |
|---|---|
| `-creategrs` | `-creategrs SOURCE_VSI TARGET_VSI VG_NAME SOURCE_VOLUMES_NAME` |
| `-deletegrs` | `-deletegrs SOURCE_VSI TARGET_VSI VG_NAME SOURCE_VOLUMES_NAME` |
| `-grsfailover` | `-grsfailover SOURCE_VSI VG_NAME NO_ATTACH\|ATTACH [TARGET_VSI]` |
| `-grscancelfailover` | `-grscancelfailover SOURCE_VSI VG_NAME NO_DETACH\|DETACH TARGET_VSI` |
| `-grsfailback` | `-grsfailback SOURCE_VSI TARGET_VSI VG_NAME` |
| `-grsreversereplica` | `-grsreversereplica SOURCE_VSI TARGET_VSI VG_NAME` |

### VSI Operations
| Flag | Syntax |
|---|---|
| `-vsistart` | `-vsistart VSI_NAME` — Start/IPL VSI (must be SHUTOFF) |
| `-vsioper` | `-vsioper VSI_NAME a\|b\|c\|d normal\|manual` |
| `-vsitask` | `-vsitask VSI_NAME dston\|retrydump\|consoleservice\|iopreset\|remotedstoff\|remotedston\|iopdump\|dumprestart` |
| `-vsisrcmon` | `-vsisrcmon VSI_NAME START\|SHUTOFF` |
| `-attachvolumes` | `-attachvolumes VOLUMES_COMMON_NAME VSI_NAME` — VSI must be SHUTOFF |
| `-detachvolumes` | `-detachvolumes VSI_NAME` — Detach all; VSI must be SHUTOFF |

---

## CLI flags — `bluexscrt_config_api.sh`

| Flag | Description |
|---|---|
| `-createconfig` | Interactive wizard: creates secrets JSON + `bluexport_api_conf.json`, discovers workspaces + LPARs, optionally creates SSH user on IBM i |
| `-addlpar NAME IP PVM_ID WORKSPACE_SHORT` | Add or update a single LPAR in `.systems[]` |
| `-dellpar NAME` | Remove LPAR from `.systems[]` (case-insensitive) |
| `-updlpars` | Refresh LPARs and COS instances from IBM Cloud APIs |
| `-v` / `--version` | Show version |
| `-h` / `--help` | Show help |

---

## Supported PowerVS Regions (base URL mapping)

| Region codes | Base URL |
|---|---|
| `eu-de-1`, `eu-de-2` | `eu-de.power-iaas.cloud.ibm.com` |
| `mad02`, `mad04` | `mad.power-iaas.cloud.ibm.com` |
| `us-east`, `wdc06`, `wdc07` | `us-east.power-iaas.cloud.ibm.com` |
| `us-south`, `dal10`, `dal12`, `dal14` | `us-south.power-iaas.cloud.ibm.com` |
| `lon04`, `lon06` | `lon.power-iaas.cloud.ibm.com` |
| `syd04`, `syd05` | `syd.power-iaas.cloud.ibm.com` |
| `sao1`, `sao4`, `sao5` | `sao.power-iaas.cloud.ibm.com` |
| `tok04` | `tok.power-iaas.cloud.ibm.com` |
| `osa21` | `osa.power-iaas.cloud.ibm.com` |
| `che` | `che.power-iaas.cloud.ibm.com` |
| `mon01` | `mon.power-iaas.cloud.ibm.com` |
| `tor01` | `tor.power-iaas.cloud.ibm.com` |

> Default base URL in script: `$base_mad02` — change `default_base_url` to your preferred region.

---

## Coding conventions & patterns

- `echoscreen "message" "1"` → print to screen AND log file. Omit `"1"` for screen only.
- `abort "message"` → logs error, writes END marker to log, exits 0.
- All API calls are thin `curl` wrappers — logic lives in the flag handlers above.
- Workspace env vars are created dynamically via `declare`: `${WS}`, `${WS}ID`, `${WS}NAME`.
- Multi-workspace operations loop over `$allws` (space-separated list from secrets JSON).
- The `PATH` is extended at startup for IBM i compatibility: `/QOpenSys/pkgs/bin:/QOpenSys/usr/bin`.
- `set -euo pipefail` used in `bluexscrt_config_api.sh` but NOT in `bluexport_api.sh`.
- Secrets file is chmod 600.
- All temp files defined in `bluexport_api_conf.json` (not hardcoded paths in main script).

---

## Version history summary

| Version | Date | Highlights |
|---|---|---|
| 1.10.2 | 2026-05-11 | `-vsisrcmon` UNKNOWN status detection |
| 1.10.1 | 2026-05-05 | Bug fixes in error messages; `bluexscrt_config_api.sh` naming fixes |
| 1.10.0 | 2026-04-28 | `-imgimport` from COS; cross-account HMAC support; repo structure improvements |
| 1.9.0 | 2025-03-30 | VSI operations, SRC monitoring, volume attach/detach, rate limiting improvements |
| 1.2.0 | 2025-01-15 | `bluexscrt_config_api.sh` wizard, multi-workspace, LPAR management |
| 1.0.0 | 2024-12-01 | Initial release |

---

## Author & contacts

- **Author**: Ricardo Martins — IBM Power Technical Leader @ Blue Chip Portugal
- **IBM Champion**: 2025 | 2026
- **Email**: ricardo.martins@bluechip.pt
- **Issues**: https://github.com/rqmartins73/bluexport_api/issues
