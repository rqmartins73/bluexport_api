#!/usr/bin/env bash
#
# bluexscrt_config.api
# Non-interactive JSON-based helper for bluexscrt configuration
# Ricardo Martins - Blue Chip Portugal © 2024-2025
#

set -euo pipefail

VERSION="1.0.0"

conf_file="$HOME/bluexport_conf.json"
log_file=$(jq -r '.log_file' "$conf_file")
bluexscrt=$(jq -r '.bluexscrt' "$conf_file")

# Default config JSON (can be overridden with env var BLUEXSCRT_JSON)
CONFIG_JSON="${BLUEXSCRT_JSON:-"$bluexscrt"}"

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

#### START:FUNCTION - Echo to log file and screen  ####
echoscreen() {
        if [ -t 1 ]
        then
                echo $1
        fi
        if [[ $2 == "1" ]]
        then
                echo $1 >> $log_file
        fi
}
#### END:FUNCTION - Echo to log file and screen  ####

#### START:FUNCTION - Finish vsi_status=$(log file when aborting  ####
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
#### END:FUNCTION - Finish log file when aborting  ####



ensure_config_exists() {

  # Show current default JSON path (resolved earlier)
  echo "### Default JSON in use: $CONFIG_JSON"
  echo "### Do you want to use this JSON file? (Y/n)"
  read -r answer

  # Normalize answer to lowercase
  answer="${answer,,}"

  if [[ "$answer" == "y" || "$answer" == "" ]]; then
      # User accepts the default JSON path
      if [[ -f "$CONFIG_JSON" ]]; then
          echo "### Using default JSON config: $CONFIG_JSON"
          return
      else
          echo "ERROR: Default JSON '$CONFIG_JSON' not found."
          echo "### Please enter a valid JSON file path:"
      fi
  else
      echo "### Please enter the full path of the JSON file to update:"
  fi

  # Ask user for a path (only happens if default rejected or missing)
  read -r newpath

  # Validate input
  if [[ -z "$newpath" ]]; then
      echo "ERROR: No path provided. Aborting..."
      exit 1
  fi

  if [[ ! -f "$newpath" ]]; then
      echo "ERROR: File '$newpath' does not exist. Aborting..."
      exit 1
  fi

  # Set new config JSON path
  CONFIG_JSON="$newpath"
  echo "### Using JSON config: $CONFIG_JSON"
}

ensure_config_exists

#### START: API Environment ###
#  authentication
apikey=$(jq -r '.apikey' "$CONFIG_JSON")
header_json="Content-Type: application/json"
header_accept="Accept: application/json"
iam_token=$(curl -s -X POST "https://iam.cloud.ibm.com/identity/token" -H "Content-Type: application/x-www-form-urlencoded" -H "$header_accept" -d "grant_type=urn:ibm:params:oauth:grant-type:apikey&apikey=${apikey}" | jq -r '.access_token')
header_auth="Authorization: Bearer $iam_token"

# Current date (YYYY-MM-DD). Required for Transit Gateway API versioning.
version=$(date +%F)

#  base endpoints per region
base_syd04="https://syd.power-iaas.cloud.ibm.com"
base_syd05="https://syd.power-iaas.cloud.ibm.com"
base_sao1="https://sao.power-iaas.cloud.ibm.com"
base_sao4="https://sao.power-iaas.cloud.ibm.com"
base_sao5="https://sao.power-iaas.cloud.ibm.com"
base_mon01="https://mon.power-iaas.cloud.ibm.com"
base_tor01="https://tor.power-iaas.cloud.ibm.com"
base_eu_de_1="https://eu-de.power-iaas.cloud.ibm.com"
base_eu_de_2="https://eu-de.power-iaas.cloud.ibm.com"
base_lon04="https://lon.power-iaas.cloud.ibm.com"
base_lon06="https://lon.power-iaas.cloud.ibm.com"
base_che="https://che.power-iaas.cloud.ibm.com"
base_tok04="https://tok.power-iaas.cloud.ibm.com"
base_osa21="https://osa.power-iaas.cloud.ibm.com"
base_mad04="https://mad.power-iaas.cloud.ibm.com"
base_mad02="https://mad.power-iaas.cloud.ibm.com"
base_us_east="https://us-east.power-iaas.cloud.ibm.com"
base_wdc06="https://us-east.power-iaas.cloud.ibm.com"
base_wdc07="https://us-east.power-iaas.cloud.ibm.com"
base_us_south="https://us-south.power-iaas.cloud.ibm.com"
base_dal10="https://us-south.power-iaas.cloud.ibm.com"
base_dal12="https://us-south.power-iaas.cloud.ibm.com"
base_dal14="https://us-south.power-iaas.cloud.ibm.com"

default_base_url=$base_mad02 # change to your prefered
#### END: API Environment ###

# Derive base_url from a PowerVS workspace CRN
get_base_url_from_crn() {
  local crn="$1"
  local region_raw region_label base_var base_url

  # CRN format: crn:v1:bluemix:public:power-iaas:<region>:a/...
  # Field 6 = region (eu-de-1, mad02, etc.)
  region_raw=$(printf '%s\n' "$crn" | awk -F: '{print $6}')

  if [[ -z "$region_raw" || "$region_raw" == "null" ]]; then
    echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - WARN: Could not extract region from CRN '$crn'" "1"
    return 1
  fi

  # Strip trailing digits (zone) and replace '-' with '_' to match base_<region>
  #   eu-de-1 -> eu-de -> eu_de  -> base_eu_de
  #   mad02   -> mad   -> mad    -> base_mad
  region_label=$(printf '%s\n' "$region_raw" | sed 's/[0-9]\+$//' | tr '-' '_')
  base_var="base_${region_label}"

  # Com set -u: usar a forma ${!var-} para não rebentar se não existir
  if [[ -z "${!base_var-}" ]]; then
    echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - WARN: No base URL defined for region token '${region_label}' (var ${base_var})" "1"
    return 1
  fi

  base_url="${!base_var}"
  printf '%s\n' "$base_url"
  return 0
}


#### START:FUNCTION - API Commands ####
##  Workspace management aliases
ws_ls() {
        curl -sX GET "$base_url/v1/workspaces" -H "$header_auth" -H "$header_json"
}

## Instance (VSI) management functions
ins_get() {
        curl -sX GET "$base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/pvm-instances/$PVM_ID" -H "$header_auth" -H "CRN: $CRN" -H "$header_json"
}

ins_vol_ls() {
        curl -sX GET "$base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/pvm-instances/$PVM_ID/volumes" -H "$header_auth" -H "CRN: $CRN" -H "$header_json"
}

ins_vol_bdet() {
        curl -X DELETE "$base_url/pcloud/v2/cloud-instances/$CLOUD_INSTANCE_ID/pvm-instances/$PVM_ID/volumes" -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -d "{$ACTIONS}"
}

ins_ls() {
        curl -sX GET "$base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/pvm-instances" -H "$header_auth" -H "CRN: $CRN" -H "$header_json"
}

ins_act() {
        curl -sX POST "$base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/pvm-instances/$PVM_ID/action" -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -d "{$ACTIONS}"
}

ins_cap() {
        curl -sX POST "$base_url/pcloud/v2/cloud-instances/$CLOUD_INSTANCE_ID/pvm-instances/$PVM_ID/capture" -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -d "{$ACTIONS}"
}

## Volume management
vol_ls() {
        curl -sX GET "$base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/volumes" -H "$header_auth" -H "CRN: $CRN" -H "$header_json"
}

vol_get() {
        curl -sX GET "$base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/pvm-instances/$PVM_ID/volumes/$VOL_ID" -H "$header_auth" -H "CRN: $CRN" -H "$header_json"
}

vol_act() {
        curl -sX POST "$base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/volumes/$VOL_ID/action" -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -d "{$ACTIONS}"
}

vol_att() {
        curl -sX POST "$base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/pvm-instances/$PVM_ID/volumes/$VOL_ID" -H "$header_auth" -H "CRN: $CRN" -H "$header_json"
}

vol_att_multi() {
        curl -sX POST "$base_url/pcloud/v2/cloud-instances/$CLOUD_INSTANCE_ID/pvm-instances/$PVM_ID/volumes" -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -d "{$ACTIONS}"
}

vol_del() {
        curl -X DELETE "$base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/volumes/$VOL_ID" -H "$header_auth" -H "CRN: $CRN" -H "$header_json"
}

vol_bdel() {
        curl -X DELETE "$base_url/pcloud/v2/cloud-instances/$CLOUD_INSTANCE_ID/volumes" -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -d "{$ACTIONS}"
}


## Volume cloning (attached / detached)
vol_cl_cr() {
        curl -sX POST "$base_url/pcloud/v2/cloud-instances/$CLOUD_INSTANCE_ID/volumes-clone" -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -d "{$ACTIONS}"
}

vol_cl_get() {
        curl -sX GET "$base_url/pcloud/v2/cloud-instances/$CLOUD_INSTANCE_ID/volumes-clone/$VOL_CLONE_ID" -H "$header_auth" -H "CRN: $CRN" -H "$header_json"
}

vol_cl_ls() {
        curl -sX GET "$base_url/pcloud/v2/cloud-instances/$CLOUD_INSTANCE_ID/volumes-clone" -H "$header_auth" -H "CRN: $CRN" -H "$header_json"
}

vol_cl_del() {
        curl -X DELETE "$base_url/pcloud/v2/cloud-instances/$CLOUD_INSTANCE_ID/volumes-clone/$VOL_CLONE_ID" -H "$header_auth" -H "CRN: $CRN" -H "$header_json"
}

vol_cl_st() {
        curl -L -sX POST "$base_url/pcloud/v2/cloud-instances/$CLOUD_INSTANCE_ID/volumes-clone/$VOL_CLONE_ID/start" -H "$header_auth" -H "CRN: $CRN" -H "$header_json"
}

vol_cl_ex() {
        curl -L -sX POST "$base_url/pcloud/v2/cloud-instances/$CLOUD_INSTANCE_ID/volumes-clone/$VOL_CLONE_ID/execute" -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -d "{$ACTIONS}"
}

vol_cl_ca() {
        curl -L -sX POST "$base_url/pcloud/v2/cloud-instances/$CLOUD_INSTANCE_ID/volumes-clone/$VOL_CLONE_ID/cancel" -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -d "{\"force\": $FORCE}"
}

vol_det_cl_cr() {
        curl -sX POST "$base_url/pcloud/v2/cloud-instances/$CLOUD_INSTANCE_ID/volumes/clone" -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -d "{$ACTIONS}"
}

vol_det_cl_ls() {
        curl -sX GET "$base_url/pcloud/v2/cloud-instances/$CLOUD_INSTANCE_ID/volumes/clone-tasks/$CLONE_TASK_ID" -H "$header_auth" -H "CRN: $CRN" -H "$header_json"
}


## Volume Group management
vg_cr() {
        curl -sX POST "$base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/volume-groups" -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -d "{$ACTIONS}"
}

vg_ls() {
        curl -sX GET "$base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/volume-groups" -H "$header_auth" -H "CRN: $CRN" -H "$header_json"
}

vg_rcr() {
        curl -sX GET "$base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/volume-groups/$VOLUME_GROUP_ID/remote-copy-relationships" -H "$header_auth" -H "CRN: $CRN" -H "$header_json"
}

vg_sd() {
        curl -sX GET "$base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/volume-groups/$VOLUME_GROUP_ID/storage-details" -H "$header_auth" -H "CRN: $CRN" -H "$header_json"
}

vg_get() {
        curl -sX GET "$base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/volume-groups/$VOLUME_GROUP_ID/details" -H "$header_auth" -H "CRN: $CRN" -H "$header_json"
}

vg_act() {
        curl -sX POST "$base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/volume-groups/$VOLUME_GROUP_ID/action" -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -d "{$ACTIONS}"
}

vg_del() {
        curl -X DELETE "$base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/volume-groups/$VOLUME_GROUP_ID" -H "$header_auth" -H "CRN: $CRN" -H "$header_json"
}

vg_upd() {
        curl -X PUT "$base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/volume-groups/$VOLUME_GROUP_ID" -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -d "{$ACTIONS}"
}

## Auxiliary volume onboarding
on_ls() {
        curl -sX GET "$base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/volumes/onboarding" -H "$header_auth" -H "CRN: $CRN" -H "$header_json"
}

on_cr() {
        curl -sX POST "$base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/volumes/onboarding" -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -d "{$ACTIONS}"
}

on_get() {
        curl -sX GET "$base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/volumes/onboarding/$VOLUME_ONBOARDING_ID" -H "$header_auth" -H "CRN: $CRN" -H "$header_json"
}


## Transit Gateway
tg_gws() {
        curl -sX GET -L -H "$header_auth" -H "$header_accept" "$base_url/transit_gateways?version=$version"
}

tg_cs() {
        curl -sX GET -L -H "$header_auth" -H "$header_accept" "$base_url/connections?version=$version"
}

tg_pfs() {
        curl -sX GET -L -H "$header_auth" -H "$header_accept" "$base_url/transit_gateways/$TGW_ID/connections/$CONNID/prefix_filters?version=$version"
}

tg_pfu() {
        curl -sX PATCH -L -H "$header_auth" -H "$header_accept" -H "$header_json" --data "{\"action\": \"$pfaction\"}" "$base_url/transit_gateways/$TGW_ID/connections/$CONNID/prefix_filters/$PFID?version=$version"
}

tg_pfc() {
        curl -sX POST -L -H "$header_auth" -H "$header_accept" -H "$header_json" --data "{\"action\": \"$pfaction\", \"prefix\": \"$pfip\"}" "$base_url/transit_gateways/$TGW_ID/connections/$CONNID/prefix_filters?version=$version"
}

tg_pfd() {
        curl -sX DELETE -L -H "$header_auth" "$base_url/transit_gateways/$TGW_ID/connections/$CONNID/prefix_filters/$PFID?version=$version"
}


## Jobs
job_ls() {
        curl -sX GET $base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/jobs -H "$header_auth" -H "CRN: $CRN" -H "$header_json"
}

job_get() {
        curl -sX GET $base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/jobs/$JOB_ID -H "$header_auth" -H "CRN: $CRN" -H "$header_json"
}

## Images
img_ls() {
        curl -sX GET $base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/images -H "$header_auth" -H "CRN: $CRN" -H "$header_json"
}

## Snapshots
snap_ls() {
        curl -sX GET $base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/snapshots -H "$header_auth" -H "CRN: $CRN" -H "$header_json"
}
#### END:FUNCTION - API Commands ####

# Devolve 0 se o pvmInstanceID ainda existe no workspace, 1 caso contrário
vsi_exists_in_cloud() {
    local ws="$1"           # exemplo: WSMAD2
    local pvm_id="$2"

    # Vai buscar o CLOUD_INSTANCE_ID desse workspace ao JSON
    local cloud_instance_id
    cloud_instance_id=$(jq -r --arg ws "$ws" '.workspaces[$ws].id' "$CONFIG_JSON")

    if [[ -z "$cloud_instance_id" || "$cloud_instance_id" == "null" ]]; then
        return 1
    fi

    # Aqui assumes que já tens base_url/CRN/etc. preparados para esse workspace
    # Se tens um set_node ou algo equivalente, chama-o aqui:
    #   set_node "$ws"
    CLOUD_INSTANCE_ID="$cloud_instance_id"

    # Verifica se o pvmInstanceID aparece na lista de instâncias
    if ins_ls 2>/dev/null | jq -e --arg id "$pvm_id" '.pvmInstances[]? | select(.pvmInstanceID == $id)' >/dev/null; then
        return 0    # existe
    else
        return 1    # não existe
    fi
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

# Set base_url, CLOUD_INSTANCE_ID e CRN para um workspace curto (ex: WSMAD2)
set_ws_context() {
    local ws="$1"

    # Vai buscar crn e id do workspace ao JSON
    local crn id region_token region_api base_var

    crn=$(jq -r --arg ws "$ws" '.workspaces[$ws].crn' "$CONFIG_JSON")
    id=$(jq -r --arg ws "$ws" '.workspaces[$ws].id'  "$CONFIG_JSON")

    if [[ -z "$crn" || "$crn" == "null" || -z "$id" || "$id" == "null" ]]; then
        echo "WARN: Workspace '$ws' not found or missing crn/id in $CONFIG_JSON" >&2
        return 1
    fi

    # CRN: crn:v1:bluemix:public:power-iaas:mad02:...
    region_token=$(echo "$crn" | awk -F: '{print $5}')
    region_api=${region_token//-/_}              # eu-de-1 -> eu_de_1, mad02 -> mad02

    base_var="base_${region_api}"
    base_url="${!base_var:-}"

    if [[ -z "$base_url" ]]; then
        echo "WARN: No base URL defined for region token '$region_token' (var $base_var)" >&2
        return 1
    fi

    CLOUD_INSTANCE_ID="$id"
    CRN="$crn"
    return 0
}

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
#    ensure_config_exists
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
#    ensure_config_exists
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
        test=0
        echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - === Starting -updlpars using IBM Cloud APIs ===" "1"

        tmp_keep="$(mktemp)"
        tmp_struct="$(mktemp)"
        tmp_vsi_list="$(mktemp)"

        # 1) Construir lista dos sistemas que EXISTEM na Cloud, por workspace
        for ws in $(jq -r '.workspaces | keys[]' "$CONFIG_JSON"); do
            ws_crn=$(jq -r --arg ws "$ws" '.workspaces[$ws].crn' "$CONFIG_JSON")
            ws_id=$(jq -r --arg ws "$ws" '.workspaces[$ws].id' "$CONFIG_JSON")

            if [[ -z "$ws_crn" || "$ws_crn" == "null" || -z "$ws_id" || "$ws_id" == "null" ]]; then
                echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - WARN: Workspace '$ws' missing CRN or ID in JSON. Skipping..." "1"
                continue
            fi

            base_url="$(get_base_url_from_crn "$ws_crn")"
            if [[ $? -ne 0 || -z "$base_url" ]]; then
                echoscreen "  -> Skipping workspace '$ws' (no valid base_url)" "1"
                continue
            fi

            CRN="$ws_crn"
            CLOUD_INSTANCE_ID="$ws_id"

            echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Processing workspace '$ws' (CRN=$CRN, CLOUD_INSTANCE_ID=$CLOUD_INSTANCE_ID)..." "1"

            # ins_ls deve estar definido no teu .env para usar $base_url / $CLOUD_INSTANCE_ID / $CRN
            ins_ls 2>>"$log_file" \
              | jq -r '.pvmInstances[]? | .serverName' > "$tmp_vsi_list"

            if [[ ! -s "$tmp_vsi_list" ]]; then
                echoscreen "$(date +%Y-%m-%d_%H:%M:%S) -   No instances returned by API for workspace '$ws'." "1"
                continue
            fi

            # Guardar pares {name, workspace} que existem na Cloud
            while read -r name; do
                [[ -z "$name" ]] && continue
                printf '{"name":"%s","workspace":"%s"}\n' "$name" "$ws" >> "$tmp_keep"
            done < "$tmp_vsi_list"
        done

        if [[ ! -s "$tmp_keep" ]]; then
            echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - ERROR: No VSIs found via API in any workspace. JSON will not be modified." "1"
            rm -f "$tmp_keep" "$tmp_struct" "$tmp_vsi_list"
            abort "$(date +%Y-%m-%d_%H:%M:%S) - -updlpars finished with errors (no VSIs)."
        fi

        keep_pairs=$(jq -s '.' "$tmp_keep")

        # 2) Construir estrutura intermédia com kept / removed para evitar o erro "Cannot index array with string \"systems\""
        jq --argjson keep "$keep_pairs" '
          . as $root
          | $root.systems as $sys
          | {
              root: $root,
              kept:    [ $sys[] | select(any($keep[]; .name == .name and .workspace == .workspace)) ],
              removed: [ $sys[] | select(any($keep[]; .name == .name and .workspace == .workspace) | not) ]
            }
        ' "$CONFIG_JSON" > "$tmp_struct"

        # 3) Logar quais sistemas foram removidos (deixaram de existir na Cloud)
        if jq -e '.removed | length > 0' "$tmp_struct" > /dev/null; then
            echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Systems removed from JSON (no longer in IBM Cloud):" "1"
            jq -r '.removed[] | "   - \(.name) (\(.workspace))"' "$tmp_struct" \
                | while read -r line; do
                      echoscreen "$line" "1"
                  done
        else
            echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - No systems removed; all JSON entries still exist in IBM Cloud." "1"
        fi

        # 4) Atualizar JSON: root.systems = kept
        jq '.root.systems = .kept | .root' "$tmp_struct" > "${CONFIG_JSON}.tmp" &&
            mv "${CONFIG_JSON}.tmp" "$CONFIG_JSON"

        rm -f "$tmp_keep" "$tmp_struct" "$tmp_vsi_list"

        echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - -updlpars finished." "1"
        abort "$(date +%Y-%m-%d_%H:%M:%S) - -updlpars finished."
        ;;

  *)
    usage
    exit 1
    ;;
esac
