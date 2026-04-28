# bluexport_api.sh
API‑driven automation framework for IBM Cloud Power Virtual Server (PowerVS)

---

`bluexport_api.sh` is a comprehensive Bash framework that manages IBM Cloud PowerVS resources **using the native REST APIs**, without depending on the IBM Cloud CLI.

It centralizes automation for:
- VSI lifecycle operations (start, boot/operating mode, IBM i tasks, SRC monitoring)
- Capture & Export to IBM Cloud Object Storage and/or Image Catalog
- Snapshot management (create / update / delete / restore / list)
- Captured images (list / delete / import from COS)
- Volume clones (create / delete / list)
- Volume attach / detach operations
- Volume tier changes
- Cloud Object Storage (COS) operations (list buckets, list/delete objects, archive restore)
- Global Replication Services (GRS) orchestration (create, delete, failover, failback, reverse)

The script is designed for enterprise environments running IBM i in Hybrid Cloud, HA/DR, and multi‑region deployments.

---

## 📌 bluexscrt_config_api.sh – Secrets & Configuration Generator

This repository also includes **`bluexscrt_config_api.sh`**, a helper tool that interactively generates the **JSON secrets/configuration file** required by `bluexport_api.sh`.

The configuration file contains:
- IBM Cloud API Key
- PowerVS Workspace list (CRN, workspace ID, human‑friendly name)
- Region‑specific API endpoints
- VSI definitions (workspace, IP, metadata)
- COS (Cloud Object Storage) credentials
- SSH parameters
- Optional defaults (log file path, temp file paths, etc.)

`bluexport_api.sh` relies heavily on this file to:
- Dynamically resolve regions, CRNs, and Cloud Instance IDs
- Execute multi‑workspace searches
- Wire authentication for all API calls
- Map user‑friendly names to system identifiers

If you are installing the tool for the first time, run:
```
./bluexscrt_config_api.sh -createconfig
```
This will build a complete and valid `bluexscrt_*.json` secrets file that the main script can consume.

---

## 🚀 Features Overview

### **Capture & Export**
- Capture VSI image (all volumes or excluding specific volumes by name prefix)
- Export destination: `image-catalog`, `cloud-storage`, or `both`
- Recurrence: `hourly`, `daily`, `weekly`, `monthly`, `single`
  - Note: `hourly` and `daily` only permit captures to `image-catalog`
- Test mode: validate the capture setup without triggering an actual capture
- Job monitoring: track a running capture/export job until completion

### **VSI Operations**
- Start VSI (IPL) with monitoring until `ACTIVE / SRC 00000000`
- Set boot and operating modes (`a/b/c/d`, `manual/normal`)
- Run IBM i tasks (`iopreset`, `retrydump`, `dumprestart`, `consoleservice`, etc.)
- Monitor SRC independently until either:
  - `ACTIVE / 00000000`, or
  - `SHUTOFF`
- Attach volumes by common name (skips already-attached; VSI must be SHUTOFF)
- Detach all volumes from a VSI (VSI must be SHUTOFF)

### **Snapshots**
- Create snapshot for a VSI (specific volumes or all)
- Update snapshot metadata (name and/or description)
- Delete snapshot (multi‑workspace aware)
- Restore snapshot to a VSI (requires VSI in `SHUTOFF`)
- Restore monitoring until 100%
- List snapshots across all workspaces

### **Captured Images**
- List images across all workspaces
- Delete captured images by name (auto‑workspace resolution)
- Import images from IBM Cloud Object Storage into a target PowerVS workspace using the native `/cos-images` API
- Supports current-account COS credentials from the secrets JSON or cross-account HMAC credentials exported from IBM Cloud COS Service Credentials
- Explicit bucket region and storage tier selection for predictable image imports

### **Cloud Object Storage (COS)**
- List all buckets across all COS instances defined in the secrets file
- Interactively list objects from a selected COS bucket
- Interactively delete an object from a selected COS bucket (with confirmation prompt)
- Restore an object from Archive back to a COS bucket (configurable days and archive type)

### **Volume Clones**
- Create volume clones (attached or detached)
- Tiered storage support
- Optional replication awareness
- Delete clones safely (with optional volume deletion)
- List all volume clones across all workspaces

### **Volume Tier Management**
- Apply tier changes based on volume‑name patterns

### **GRS – Global Replication Services**
- Create Volume Groups for replication
- Onboard auxiliary volumes
- Failover: activate the target workspace (with or without volume attach)
- Cancel failover: restart from primary, re-enable master→auxiliary replication
- Failback: sync auxiliary→master and re-enable replication
- Reverse replication direction: sync auxiliary→master
- Delete GRS structures with safety checks to protect primary volumes
- Retry‑aware polling to avoid rate limits

---

## 🧩 Requirements
- Bash 5.x or higher
- `curl`
- `jq` 1.6+
- IBM Cloud PowerVS API access
- A secrets JSON file generated with `bluexscrt_config_api.sh`

---

## 🔧 Usage Summary

### General
```
./bluexport_api.sh -h                  # Help
./bluexport_api.sh -v                  # Version info
./bluexport_api.sh -chscrt FILE        # Change secrets file (also prompts for log file path)
./bluexport_api.sh -viewscrt           # Show secrets file currently in use
```

### Capture & Export
```
# Capture all volumes
./bluexport_api.sh -a VSI_NAME IMAGE_NAME both|image-catalog|cloud-storage hourly|daily|weekly|monthly|single

# Capture excluding specific volumes (space-separated prefixes)
./bluexport_api.sh -x VOLUMES_TO_EXCLUDE VSI_NAME IMAGE_NAME both|image-catalog|cloud-storage hourly|daily|weekly|monthly|single

# Test mode — validate without triggering a capture
./bluexport_api.sh -tx VOLUMES_TO_EXCLUDE VSI_NAME IMAGE_NAME both|image-catalog|cloud-storage single

# Monitor a running capture/export job
./bluexport_api.sh -j VSI_NAME IMAGE_NAME
```

Examples:
```
./bluexport_api.sh -a vsiprd vsiprd_img image-catalog daily
./bluexport_api.sh -x ASP2_ vsiprd vsiprd_img both monthly
./bluexport_api.sh -x "ASP2_ iASPname" vsiprd vsiprd_img both monthly
./bluexport_api.sh -tx ASP2_ vsiprd vsiprd_img both single
```

### VSI Operations
```
./bluexport_api.sh -vsistart VSI_NAME
./bluexport_api.sh -vsioper  VSI_NAME BOOT_MODE OPERATING_MODE
./bluexport_api.sh -vsitask  VSI_NAME TASK
./bluexport_api.sh -vsisrcmon VSI_NAME START|SHUTOFF
./bluexport_api.sh -attachvolumes VOLUMES_COMMON_NAME VSI_NAME
./bluexport_api.sh -detachvolumes VSI_NAME
```

- `BOOT_MODE`: `a | b | c | d`
- `OPERATING_MODE`: `normal | manual`
- `TASK`: `dston | retrydump | consoleservice | iopreset | remotedstoff | remotedston | iopdump | dumprestart`
- `-vsisrcmon START` → monitor until `ACTIVE` and SRC `00000000`
- `-vsisrcmon SHUTOFF` → monitor until `SHUTOFF` (SRC ignored)

### Snapshots
```
./bluexport_api.sh -snapcr   VSI_NAME SNAP_NAME 0|DESCRIPTION 0|VOLUMES
./bluexport_api.sh -snapupd  SNAP_NAME 0|NEW_NAME 0|DESCRIPTION
./bluexport_api.sh -snapdel  SNAP_NAME
./bluexport_api.sh -snapres  VSI_NAME SNAP_NAME
./bluexport_api.sh -snaplsall
```

Use `0` as a placeholder when a parameter is not applicable (e.g. no description, or snapshot all volumes).

### Images
```
./bluexport_api.sh -imglsall
./bluexport_api.sh -imgdel IMAGE_NAME
./bluexport_api.sh -imgimport IMGNAME BUCKET BUCKET_REGION WORKSPACE_TO_IMPORT IMGNAME_WS STORAGE_TYPE CURRACCOUNT|OTHERACCOUNT [HMACKEYS-JSON-FILE-PATH-NAME]
```

`-imgimport` imports an image file stored in IBM Cloud Object Storage into a PowerVS workspace image catalog.

Parameters:
- `IMGNAME`: image object filename in the COS bucket
- `BUCKET`: COS bucket name
- `BUCKET_REGION`: COS bucket region (e.g. `eu-es`, `eu-de`, `us-east`). Do **not** use the PowerVS datacenter name (e.g. `mad02`)
- `WORKSPACE_TO_IMPORT`: target PowerVS workspace short name or configured workspace display name
- `IMGNAME_WS`: image name to create in the target PowerVS workspace
- `STORAGE_TYPE`: one of `tier0`, `tier1`, `tier3`, or `tier5k`
- `CURRACCOUNT|OTHERACCOUNT`: use `CURRACCOUNT` for COS credentials already present in the bluexport secrets file, or `OTHERACCOUNT` for cross-account COS access
- `HMACKEYS-JSON-FILE-PATH-NAME`: required only with `OTHERACCOUNT`

For `OTHERACCOUNT`, create or open the IBM Cloud COS service credential with HMAC keys enabled, copy the JSON exactly as shown in the IBM Cloud GUI, and save it locally. The file must contain:

```json
{
  "cos_hmac_keys": {
    "access_key_id": "...",
    "secret_access_key": "..."
  }
}
```

### Cloud Object Storage (COS)
```
./bluexport_api.sh -bucketslsall
./bluexport_api.sh -bucketlsobjs
./bluexport_api.sh -bucketdelobj
./bluexport_api.sh -restorefromarchive BUCKET OBJECT [DAYS] [ARCHIVE_TYPE]
```

- `-bucketslsall`: lists all buckets across all COS instances defined in the secrets file
- `-bucketlsobjs`: interactively selects a COS instance and bucket, then lists all objects
- `-bucketdelobj`: interactively selects a COS instance, bucket, and object, then deletes it after confirmation
- `-restorefromarchive`: restores an archived object back to the bucket; `DAYS` defaults to `3`, `ARCHIVE_TYPE` defaults to `Accelerated`

### Volume Clones
```
./bluexport_api.sh -vclone REQUEST_CLONE_NAME VOLUME_BASE_NAME LPAR_NAME True|False True|False STORAGE_TIER ALL|VOLUMES
./bluexport_api.sh -vclonedel REQUEST_CLONE_NAME 0|delete_volumes
./bluexport_api.sh -vclonelsall
```

- Parameters 4 and 5 are `replication-enabled` and `rollback-prepare` respectively (`True|False`)
- Use `ALL` for all volumes, or a comma-separated list of volume names
- Pass `delete_volumes` to also delete the cloned volumes on removal, or `0` to skip

### Volume Tier Updates
```
./bluexport_api.sh -vchtier VSI_NAME VOLUMES_NAME TIER_TO_CHANGE_TO
```

### GRS Operations
```
./bluexport_api.sh -creategrs SRC_VSI TGT_VSI VG_NAME SOURCE_VOL_PREFIX
./bluexport_api.sh -deletegrs SRC_VSI TGT_VSI VG_NAME SOURCE_VOL_PREFIX
./bluexport_api.sh -grsfailover SRC_VSI VG_NAME NO_ATTACH|ATTACH [TARGET_VSI]
./bluexport_api.sh -grscancelfailover SRC_VSI VG_NAME NO_DETACH|DETACH TARGET_VSI
./bluexport_api.sh -grsfailback SRC_VSI TGT_VSI VG_NAME
./bluexport_api.sh -grsreversereplica SRC_VSI TGT_VSI VG_NAME
```

- `SRC_VSI` / `TGT_VSI`: logical PowerVS instance names as defined in your secrets JSON
- `VG_NAME`: name for the Volume Group to create on the source workspace
- `SOURCE_VOL_PREFIX`: common name/prefix to identify source VSI volumes (e.g. `IBMiGRS`)
- `-grsfailover ATTACH`: automatically attaches auxiliary volumes to the target VSI after failover
- `-grscancelfailover`: rolls back a failover and re-establishes primary replication direction

---

## 📒 Logging
Every operation writes detailed logs to the location configured in your secrets JSON file:
- Timestamped messages
- API responses
- Polling/monitoring events
- Automatic error handling and abort conditions

This makes the script fully suitable for production operations, DR rehearsals, and customer‑facing support.

---

## 🌍 Supported PowerVS Regions

The following region endpoints are pre-configured in the script:

| Region Code | Endpoint |
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

---

## 📜 License
MIT License — free to use, modify, and distribute.

---

## 👤 Author
**Ricardo Martins**  
IBM Power Technical Leader @ Blue Chip Portugal  
IBM Champion 2025 | 2026
