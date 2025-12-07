#!/usr/bin/env bash
#
# bluexscrt_config.api
# Non-interactive JSON-based helper for bluexscrt configuration
# Ricardo Martins - Blue Chip Portugal © 2024-2025
#

set -euo pipefail

VERSION="1.0.0"

# Default config JSON (can be overridden with env var BLUEXSCRT_JSON)
CONFIG_JSON="${BLUEXSCRT_JSON:-"$HOME/bluexscrt_config.json"}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [option] [args]

Options:
  -v
      Show version in JSON.

  -dellpar NAME
      Delete an LPAR (system) from the JSON config.

  -addlpar NAME IP PVM_ID WORKSPACE_SHORT LPAR_LABEL
      Add or update an LPAR (system) in the JSON config.

  -updlpars
      Update pvmInstanceID for existing systems using 'ibmcloud resources'.
      (Same logic as old bluexscrt_config.sh, but writing into JSON.)

Examples:
  $(basename "$0") -v
  $(basename "$0") -dellpar ibmi75m2
  $(basename "$0") -addlpar ibmi75m2 172.26.2.5 7ed4ea03-... WSMAD2 LPAR2
  $(basename "$0") -updlpars
EOF
}

ensure_config_exists() {
  # If config exists, good
  if [[ -f "$CONFIG_JSON" ]]; then
    return 0
  fi

  echo "### JSON config not found at: $CONFIG_JSON"
  echo "### Please enter the full path of the JSON file to update:"
  read -r newpath

  # Empty input → abort
  if [[ -z "$newpath" ]]; then
    echo "ERROR: No path provided. Aborting..."
    exit 1
  fi

  # Validate that provided file exists
  if [[ ! -f "$newpath" ]]; then
    echo "ERROR: File '$newpath' does not exist. Aborting..."
    exit 1
  fi

  # Update CONFIG_JSON to the new path
  CONFIG_JSON="$newpath"
  echo "### Using JSON config: $CONFIG_JSON"
}

# Safe jq wrapper that writes back to CONFIG_JSON
jq_inplace() {
  local filter="$1"
  shift
  tmp_file="$(mktemp "${CONFIG_JSON}.XXXX")"
  jq "$filter" "$@" "$CONFIG_JSON" > "$tmp_file"
  mv "$tmp_file" "$CONFIG_JSON"
}

flag="${1:-}"

if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

case "$flag" in
  -v)
    # Version as JSON
    jq -n --arg version "$VERSION" '{tool:"bluexscrt_config.api", version:$version}'
    ;;

  -dellpar)
    if [[ $# -ne 2 ]]; then
      echo "ERROR: Wrong syntax." >&2
      echo "Usage: $(basename "$0") -dellpar NAME" >&2
      exit 1
    fi
    ensure_config_exists
    name="$2"

    # Remove system with matching name (case-insensitive)
    jq_inplace '
      .systems |= map(
        select(
          (.name // "" | ascii_downcase) != ($name | ascii_downcase)
        )
      )
    ' --arg name "$name"

    # Output updated JSON
    cat "$CONFIG_JSON"
    ;;

  -addlpar)
    if [[ $# -ne 6 ]]; then
      echo "ERROR: Wrong syntax." >&2
      echo "Usage: $(basename "$0") -addlpar NAME IP PVM_ID WORKSPACE_SHORT LPAR_LABEL" >&2
      exit 1
    fi
    ensure_config_exists
    lpar_name="$2"
    lpar_ip="$3"
    lpar_pvmid="$4"
    lpar_ws="$5"
    lpar_label="$6"

    # Upsert system entry
    # 1) Remove any existing system with same name (case-insensitive)
    # 2) Append the new one
    jq_inplace '
      .systems |= (
        map(select((.name // "" | ascii_downcase) != ($name | ascii_downcase)))
        + [ { "name": $name,
              "ip": $ip,
              "pvmInstanceID": $pvmid,
              "workspace": $ws,
              "lpar": $lparlabel } ]
      )
    ' \
      --arg name "$lpar_name" \
      --arg ip "$lpar_ip" \
      --arg pvmid "$lpar_pvmid" \
      --arg ws "$lpar_ws" \
      --arg lparlabel "$lpar_label"

    cat "$CONFIG_JSON"
    ;;

  -updlpars)
    # This keeps the old behaviour: use ibmcloud resources textual output
    # to refresh pvmInstanceID for existing systems.
    ensure_config_exists

    # Read apikey / region / resourceGroup from JSON
    apikey=$(jq -r '.apikey' "$CONFIG_JSON")
    region=$(jq -r '.access.region' "$CONFIG_JSON" 2>/dev/null || jq -r '.region // empty' "$CONFIG_JSON")
    resource_grp=$(jq -r '.resourceGroup' "$CONFIG_JSON")

    if [[ -z "$apikey" || -z "$region" || -z "$resource_grp" ]]; then
      echo "ERROR: apikey, region or resourceGroup missing in $CONFIG_JSON" >&2
      exit 1
    fi

    echo "### Logging into IBM Cloud to refresh LPAR IDs..." >&2
    /usr/local/bin/ibmcloud login --apikey "$apikey" -r "$region" -g "$resource_grp"

    echo "### Getting updated PowerVS VSI list from account..." >&2
    # Same parsing logic as original script: pair Name + ID
    vsi_names=$(/usr/local/bin/ibmcloud resources | grep -B3 pvm-instance | grep "Name:" | awk '{print $2}')
    vsi_ids=$(/usr/local/bin/ibmcloud resources | grep -B3 pvm-instance | grep "CRN:"  | awk '{print $2}' | sed -E 's/.*?pvm-instance://')

    # Combine into "name id" lines
    mapfile -t vsi_pairs < <(paste <(echo "$vsi_names") <(echo "$vsi_ids"))

    # For each "name id" pair, update JSON if system exists
    for pair in "${vsi_pairs[@]}"; do
      vm_name=$(echo "$pair" | awk '{print $1}')
      vm_id=$(echo "$pair"   | awk '{print $2}')

      # Update pvmInstanceID where .name matches (case-insensitive)
      tmp_file="$(mktemp "${CONFIG_JSON}.XXXX")"
      jq '
        .systems |=
          map(
            if (.name // "" | ascii_downcase) == ($vmname | ascii_downcase)
            then .pvmInstanceID = $vmid
            else .
            end
          )
      ' \
        --arg vmname "$vm_name" \
        --arg vmid "$vm_id" \
        "$CONFIG_JSON" > "$tmp_file"
      mv "$tmp_file" "$CONFIG_JSON"
    done

    echo "### bluexscrt JSON updated with latest pvmInstanceID values." >&2
    cat "$CONFIG_JSON"
    ;;

  *)
    usage
    exit 1
    ;;
esac
