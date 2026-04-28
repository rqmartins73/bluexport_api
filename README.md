# bluexport_api.sh
API‑driven automation framework for IBM Cloud Power Virtual Server (PowerVS)

---

`bluexport_api.sh` is a comprehensive Bash framework that manages IBM Cloud PowerVS resources **using the native REST APIs**, without depending on the IBM Cloud CLI.

It centralizes automation for:
- VSI lifecycle operations
- Snapshot management (create / update / delete / restore)
- Captured images (list / delete / import from COS)
- Volume clones (create / delete / list)
- Volume tier changes
- Global Replication Services (GRS) orchestration
- IBM i operational tasks, boot modes, and SRC monitoring

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
- Optional defaults

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

### **VSI Operations**
- Start VSI with monitoring until `ACTIVE / SRC 00000000`
- Set boot and operating modes (`a/b/c/d`, `manual/normal`)
- Run IBM i tasks (`iopreset`, `retrydump`, etc.)
- Monitor SRC independently until either:
  - `ACTIVE / 00000000`, or
  - `SHUTOFF`

### **Snapshots**
- Create snapshot for a VSI
- Update snapshot metadata
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

### **Volume Clones**
- Create volume clones (attached/detached)
- Tiered storage support
- Optional replication awareness
- Delete clones safely

### **Volume Tier Management**
- Apply tier changes based on volume‑name patterns

### **GRS – Global Replication Services**
- Create Volume Groups for replication
- Onboard auxiliary volumes
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
./bluexport_api.sh -h           # Help
./bluexport_api.sh -v           # Version info
./bluexport_api.sh -chscrt FILE # Change secrets file
```

### VSI Operations
```
./bluexport_api.sh -vsistart VSI_NAME
./bluexport_api.sh -vsioper  VSI_NAME BOOT_MODE OPERATING_MODE
./bluexport_api.sh -vsitask  VSI_NAME TASK
./bluexport_api.sh -vsisrcmon VSI_NAME
```

### Snapshots
```
./bluexport_api.sh -snapcr   VSI_NAME SNAP_NAME DESC VOLS
./bluexport_api.sh -snapupd  SNAP_NAME NEW_NAME DESC
./bluexport_api.sh -snapdel  SNAP_NAME
./bluexport_api.sh -snapres  VSI_NAME SNAP_NAME
./bluexport_api.sh -snaplsall
```

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
- `BUCKET_REGION`: COS bucket region, for example `eu-es`, `eu-de`, `us-east`
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

### Volume Clones
```
./bluexport_api.sh -vclone NAME BASE VSI REPLICATION ROLLBACK TIER VOLS
./bluexport_api.sh -vclonedel NAME
./bluexport_api.sh -vclonelsall
```

### Volume Tier Updates
```
./bluexport_api.sh -vchtier VSI FILTER TIER
```

### GRS Operations
```
./bluexport_api.sh -creategrs SRC_VSI TGT_VSI VG_NAME SOURCE_VOL_PREFIX
./bluexport_api.sh -deletegrs SRC_VSI TGT_VSI VG_NAME SOURCE_VOL_PREFIX
```

---

## 📒 Logging
Every operation writes detailed logs to the location configured in your secrets JSON file:
- Timestamped messages
- API responses
- Polling/monitoring events
- Automatic error handling and abort conditions

This makes the script fully suitable for production operations, DR rehearsals, and customer‑facing support.

---

## 📜 License
MIT License — free to use, modify, and distribute.

---

## 👤 Author
**Ricardo Martins**  
IBM Power Technical Leader @ Blue Chip Portugal  
IBM Champion 2025 • IBM Influencer 2025
```}

