#!/bin/bash
#
# bluexscrt_config.api
# Non-interactive JSON-based helper for bluexscrt configuration
# Ricardo Martins - Blue Chip Portugal © 2024-2025
#################################################################

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
  echo "### Default JSON in use: $CONFIG_JSON"
  echo "### Do you want to use this JSON file? (Y/n)"
  read -r ans

  if [[ -z "$ans" || "$ans" =~ ^[Yy]$ ]]; then
    if [[ ! -f "$CONFIG_JSON" ]]; then
      echo "ERROR: Default JSON '$CONFIG_JSON' does not exist. Aborting..."
      exit 1
    fi
    echo "### Using JSON config: $CONFIG_JSON"
    return
  fi

  echo "### Please enter the full path of the JSON file to update:"
  read -r newpath

  if [[ -z "$newpath" ]]; then
    echo "ERROR: No path provided. Aborting..."
    exit 1
  fi

  if [[ ! -f "$newpath" ]]; then
    echo "ERROR: File '$newpath' does not exist. Aborting..."
    exit 1
  fi

  CONFIG_JSON="$newpath"
  echo "### Using JSON config: $CONFIG_JSON"
}

#ensure_config_exists

# ===== IBM Cloud IAM Token from CONFIG_JSON.apikey =====
get_iam_token() {
  local apikey
  apikey=$(jq -r '.apikey' "$CONFIG_JSON")
  if [[ -z "$apikey" || "$apikey" == "null" ]]; then
    echo "ERROR: .apikey not found in $CONFIG_JSON"
    exit 1
  fi

  iam_token=$(curl -s -X POST "https://iam.cloud.ibm.com/identity/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -H "Accept: application/json" \
    -d "grant_type=urn:ibm:params:oauth:grant-type:apikey&apikey=${apikey}" | jq -r '.access_token')

  if [[ -z "$iam_token" || "$iam_token" == "null" ]]; then
    echo "ERROR: Failed to obtain IAM token"
    exit 1
  fi

  header_auth="Authorization: Bearer $iam_token"
  header_json="Content-Type: application/json"
}


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

# ===== Derive base_url from workspace CRN =====
get_base_url_for_workspace() {
  local ws_key="$1"   # ex: WSFRA1, WSMAD2
  local crn region_raw region_api base_var url

  # Vai buscar o CRN do workspace ao JSON
  crn=$(jq -r --arg ws "$ws_key" '.workspaces[$ws].crn' "$CONFIG_JSON")
  if [[ -z "$crn" || "$crn" == "null" ]]; then
    echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - WARN: No CRN found for workspace '$ws_key' in $CONFIG_JSON" "1"
    return 1
  fi

  # Campo 6 do CRN é a região (ex: eu-de-1, eu-de-2, mad02, mad04)
  region_raw=$(echo "$crn" | awk -F: '{print $6}')

  # Converter para nome de variável: eu-de-1 -> eu_de_1 ; mad02 -> mad02 ; us-east -> us_east
  region_api=$(echo "$region_raw" | tr '-' '_')

  base_var="base_${region_api}"
  url="${!base_var:-}"

  if [[ -z "$url" ]]; then
    echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - WARN: No base URL defined for region '$region_raw' (expected var $base_var)" "1"
    return 1
  fi

  echo "$url"
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

# ===== -updlpars using IBM Cloud APIs (no ibmcloud CLI) =====
run_updlpars_api() {
  echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - === Starting -updlpars using IBM Cloud APIs ===" "1"

  tmp_json=$(mktemp)
  cp "$CONFIG_JSON" "$tmp_json"

  existing_ids_file=$(mktemp)
  : > "$existing_ids_file"

  # Percorre todos os workspaces definidos em .workspaces
  mapfile -t ws_keys < <(jq -r '.workspaces | keys[]' "$tmp_json")

  for ws in "${ws_keys[@]}"; do
    echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Processing workspace '$ws'..." "1"

    # Vai buscar base_url e CRN/ID a partir do JSON
    base_url=$(get_base_url_for_workspace "$ws") || {
      echoscreen "  -> Skipping workspace '$ws' (no valid base_url)" "1"
      continue
    }

    CLOUD_INSTANCE_ID=$(jq -r --arg ws "$ws" '.workspaces[$ws].id' "$tmp_json")
    CRN=$(jq -r --arg ws "$ws" '.workspaces[$ws].crn' "$tmp_json")

    if [[ -z "$CLOUD_INSTANCE_ID" || "$CLOUD_INSTANCE_ID" == "null" || -z "$CRN" || "$CRN" == "null" ]]; then
      echoscreen "  -> Skipping workspace '$ws' (missing CRN or ID in JSON)" "1"
      continue
    fi

     # Chamada à API de listagem de instâncias
    vsi_resp=$(
      curl -sS -X GET \
        "$base_url/v1/cloud-instances/$CLOUD_INSTANCE_ID/pvm-instances" \
        -H "$header_auth" \
        -H "CRN: $CRN" \
        -H "$header_json"
    )

    if [[ $? -ne 0 ]]; then
      echoscreen "  -> ERROR calling PowerVS API for workspace '$ws'" "1"
      continue
    fi

    # Guardar IDs desta workspace
    echo "$vsi_resp" \
      | jq -r '.pvmInstances[]?.pvmInstanceID' 2>/dev/null \
      >> "$existing_ids_file"

    # Atualizar / alinhar os systems desta workspace no JSON (nome + IP se quiseres)
    # Exemplo: só garantir que o pvmInstanceID existe e que o workspace se mantém
    tmp_json_new=$(mktemp)

    jq --arg ws "$ws" --argjson vsis "$vsi_resp" '
      .systems |= (
        map(
          if .workspace == $ws then
            # mantemos o registo, pvmInstanceID é o valor actual no JSON;
            # aqui podias opcionalmente validar se ainda existe em vsis...
            .
          else
            .
          end
        )
      )
    ' "$tmp_json" > "$tmp_json_new" || {
      echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - WARN: Failed to re-map systems for workspace '$ws'. Leaving systems unchanged for this pass." "1"
      cp "$tmp_json" "$tmp_json_new"
    }

    mv "$tmp_json_new" "$tmp_json"
  done

  # Remover sistemas que já não existem na IBM Cloud
  if [[ -s "$existing_ids_file" ]]; then
    ids_json=$(sort -u "$existing_ids_file" | jq -R . | jq -s .)
  else
    ids_json='[]'
  fi

  tmp_json_new=$(mktemp)

  # Só tenta limpar systems se existir .systems e for array
  if jq -e 'has("systems") and (.systems | type == "array")' "$tmp_json" > /dev/null 2>&1; then
    if ! jq --argjson ids "$ids_json" '
        .systems |= map(
          select(.pvmInstanceID as $id | ($ids | index($id)))
        )
      ' "$tmp_json" > "$tmp_json_new"
    then
      echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - WARN: Failed to prune systems based on existing IDs. Leaving systems unchanged." "1"
      cp "$tmp_json" "$tmp_json_new"
    fi
  else
    echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - INFO: No valid .systems array in JSON, skipping systems cleanup." "1"
    cp "$tmp_json" "$tmp_json_new"
  fi

  mv "$tmp_json_new" "$CONFIG_JSON"
  rm -f "$tmp_json" "$existing_ids_file"

  # Mostrar resumo com chaves mascaradas
  masked=$(jq '
    .apikey |= (if . != null then (. | tostring | (.[0:4] + "****" + .[-4:])) else . end)
    | .access.accessKey |= (if . != null then (. | tostring | (.[0:4] + "****" + .[-4:])) else . end)
    | .access.secretKey |= (if . != null then (. | tostring | (.[0:4] + "****" + .[-4:])) else . end)
  ' "$CONFIG_JSON")

  echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Systems updated and cleaned based on IBM Cloud APIs." "1"
  echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Final (masked) config snapshot:" "1"
  echo "$masked"

  echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - -updlpars finished." "1"
}



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
    local crn id region_raw region_api base_var

    crn=$(jq -r --arg ws "$ws" '.workspaces[$ws].crn' "$CONFIG_JSON")
    id=$(jq -r --arg ws "$ws" '.workspaces[$ws].id'  "$CONFIG_JSON")

    if [[ -z "$crn" || "$crn" == "null" || -z "$id" || "$id" == "null" ]]; then
        echo "WARN: Workspace '$ws' not found or missing crn/id in $CONFIG_JSON" >&2
        return 1
    fi

    # CRN: crn:v1:bluemix:public:power-iaas:eu-de-1:...
    region_raw=$(echo "$crn" | awk -F: '{print $6}')
    region_api=$(echo "$region_raw" | tr '-' '_')   # eu-de-1 -> eu_de_1

    base_var="base_${region_api}"
    base_url="${!base_var:-}"

    if [[ -z "$base_url" ]]; then
        echo "WARN: No base URL defined for region '$region_raw' (expected var $base_var)" >&2
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
        ensure_config_exists
        run_updlpars_api
        ;;

  *)
    usage
    exit 1
    ;;
esac
