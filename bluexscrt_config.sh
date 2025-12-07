#!/usr/bin/env bash
# Update bluexscrt_bpa.json systems[] entries with live data from IBM PowerVS APIs
# Compatible with GNU bash 5.2.x (Linux e IBM i QOpenSys)

set -euo pipefail

###############################################################################
# Config
###############################################################################

# Config file (default)
config_file="${1:-$HOME/bluexscrt_bpa.json}"

if [[ ! -f "$config_file" ]]; then
  echo "ERROR: Config file '$config_file' not found." >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: 'jq' not found in PATH." >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "ERROR: 'curl' not found in PATH." >&2
  exit 1
fi

###############################################################################
# Get IAM token
###############################################################################

apikey=$(jq -r '.apikey' "$config_file")

if [[ -z "$apikey" || "$apikey" == "null" ]]; then
  echo "ERROR: .apikey not found in $config_file" >&2
  exit 1
fi

echo "[$(date +%Y-%m-%d_%H:%M:%S)] Getting IAM token..."

iam_token=$(
  curl -s -X POST "https://iam.cloud.ibm.com/identity/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -H "Accept: application/json" \
    -d "grant_type=urn:ibm:params:oauth:grant-type:apikey&apikey=${apikey}" \
  | jq -r '.access_token'
)

if [[ -z "$iam_token" || "$iam_token" == "null" ]]; then
  echo "ERROR: Failed to obtain IAM token." >&2
  exit 1
fi

header_auth="Authorization: Bearer $iam_token"
header_json="Content-Type: application/json"

###############################################################################
# Helper: derive base_url from workspace CRN
#   CRN field 6 -> region string (eu-de-1, eu-de-2, mad02, mad04, etc)
#   base_region = region string without trailing digits and '-digit' suffix
#   base_url = https://<base_region>.power-iaas.cloud.ibm.com/pcloud
###############################################################################

get_base_url_from_crn() {
  local crn="$1"
  # 6th field in CRN: ...:power-iaas:<region>:...
  local region_full
  region_full=$(printf "%s\n" "$crn" | awk -F: '{print $6}')

  if [[ -z "$region_full" || "$region_full" == "null" ]]; then
    echo ""
    return
  fi

  # Remove trailing digits and hyphens (eu-de-1 -> eu-de, mad02 -> mad)
  local base_region
  base_region=$(printf "%s\n" "$region_full" | sed 's/[0-9-]*$//')

  # For regions like "us-south" (no digits), base_region remains unchanged
  printf "https://%s.power-iaas.cloud.ibm.com/pcloud\n" "$base_region"
}

###############################################################################
# Main loop over systems[]
###############################################################################

echo "[$(date +%Y-%m-%d_%H:%M:%S)] Updating systems in $config_file..."

# Work in a temp file and replace at the end
tmp_file="$(mktemp)"
cp "$config_file" "$tmp_file"

# Get number of systems
systems_count=$(jq '.systems | length' "$tmp_file")

if [[ "$systems_count" -eq 0 ]]; then
  echo "No systems[] entries found in $config_file. Nothing to update."
  exit 0
fi

for (( idx=0; idx<systems_count; idx++ )); do
  # Extract system object
  sys_json=$(jq -c ".systems[$idx]" "$tmp_file")

  name=$(printf "%s" "$sys_json" | jq -r '.name')
  workspace_key=$(printf "%s" "$sys_json" | jq -r '.workspace')
  pvm_id=$(printf "%s" "$sys_json" | jq -r '.pvmInstanceID')

  if [[ -z "$name" || "$name" == "null" ]]; then
    echo "[$(date +%Y-%m-%d_%H:%M:%S)] Skipping systems[$idx]: missing .name"
    continue
  fi

  echo "[$(date +%Y-%m-%d_%H:%M:%S)] Processing VSI '$name' (workspace: $workspace_key, pvmInstanceID: $pvm_id)..."

  # Get workspace CRN and ID from JSON
  ws_crn=$(jq -r --arg ws "$workspace_key" '.workspaces[$ws].crn' "$tmp_file")
  ws_id=$(jq -r  --arg ws "$workspace_key" '.workspaces[$ws].id'  "$tmp_file")

  if [[ -z "$ws_crn" || "$ws_crn" == "null" || -z "$ws_id" || "$ws_id" == "null" ]]; then
    echo "  -> WARNING: Workspace '$workspace_key' not found or incomplete in .workspaces. Skipping '$name'."
    continue
  fi

  base_url=$(get_base_url_from_crn "$ws_crn")

  if [[ -z "$base_url" ]]; then
    echo "  -> WARNING: Could not derive base_url from CRN for workspace '$workspace_key'. Skipping '$name'."
    continue
  fi

  # Call PowerVS API to get PVM instance details
  echo "  -> GET $base_url/v1/cloud-instances/$ws_id/pvm-instances/$pvm_id"
  pvm_json=$(
    curl -s -X GET "$base_url/v1/cloud-instances/$ws_id/pvm-instances/$pvm_id" \
      -H "$header_auth" \
      -H "CRN: $ws_crn" \
      -H "$header_json"
  )

  # Detect basic API error
  api_error=$(printf "%s" "$pvm_json" | jq -r '.errors // empty')
  if [[ -n "$api_error" ]]; then
    echo "  -> WARNING: API returned error for '$name': $(printf "%s" "$api_error" | jq -c '.')" >&2
    continue
  fi

  # Extract current pvmInstanceID and IP
  new_pvm_id=$(printf "%s" "$pvm_json" | jq -r '.pvmInstanceID // empty')
  new_ip=$(printf "%s" "$pvm_json" | jq -r '.networks[0].ipAddresses[0] // .networks[0].ipAddress // empty')

  if [[ -z "$new_pvm_id" ]]; then
    echo "  -> WARNING: Could not read .pvmInstanceID from API response for '$name'. Skipping update."
    continue
  fi

  if [[ -z "$new_ip" ]]; then
    echo "  -> WARNING: Could not determine IP from .networks[] for '$name'. Keeping current IP in JSON."
  fi

  echo "  -> Live data: pvmInstanceID=$new_pvm_id, ip=${new_ip:-<unchanged>}"

  # Build jq filter to update this system entry by name
  if [[ -n "$new_ip" ]]; then
    tmp_file_new="$(mktemp)"
    jq --arg name "$name" \
       --arg pvmid "$new_pvm_id" \
       --arg ip "$new_ip" '
      .systems = (
        .systems | map(
          if .name == $name then
            .pvmInstanceID = $pvmid
            | .ip = $ip
          else
            .
          end
        )
      )
    ' "$tmp_file" > "$tmp_file_new"
    mv "$tmp_file_new" "$tmp_file"
  else
    # Update only pvmInstanceID
    tmp_file_new="$(mktemp)"
    jq --arg name "$name" \
       --arg pvmid "$new_pvm_id" '
      .systems = (
        .systems | map(
          if .name == $name then
            .pvmInstanceID = $pvmid
          else
            .
          end
        )
      )
    ' "$tmp_file" > "$tmp_file_new"
    mv "$tmp_file_new" "$tmp_file"
  fi

done

# Replace original file
mv "$tmp_file" "$config_file"

echo "[$(date +%Y-%m-%d_%H:%M:%S)] Update completed. File updated: $config_file"
