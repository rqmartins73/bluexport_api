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

### Usage: $(basename "$0") [option] [args]

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
  $(basename "$0") -addlpar ibmi75m2 172.26.2.5 7ed4ea03-... WSMAD2
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
  header_accept="Accept: application/json"
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

print_masked_config() {

  jq '
    .apikey |= ( if . != null then ( .[0:4] + "****" + .[-4:] ) else . end ) |
    .access.accessKey |= ( if . != null then ( .[0:4] + "****" + .[-4:] ) else . end ) |
    .access.secretKey |= ( if . != null then ( .[0:4] + "****" + .[-4:] ) else . end )
  ' "$CONFIG_JSON"
}

############################
run_updlpars_api() {
  get_iam_token
  echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - === Starting -updlpars using IBM Cloud APIs ===" "1"

  # Load current systems[] from JSON (to detect existing vs new)
  existing_systems_json=$(jq '.systems // []' "$CONFIG_JSON")

  all_systems=""

  # Lista de workspaces definidos no JSON
  mapfile -t ws_keys < <(jq -r '.workspaces | keys[]' "$CONFIG_JSON")

  for ws in "${ws_keys[@]}"; do
    # Preparar contexto para este workspace (base_url, CLOUD_INSTANCE_ID, CRN)
    if ! set_ws_context "$ws"; then
      echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - -> Skipping workspace '$ws' (no valid context)" "1"
      continue
    fi

    echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Processing workspace '$ws'..." "1"

    # Chama o API de lista de instâncias
    resp=$(ins_ls 2>>"$log_file")

    # Se resposta vazia ou sem pvmInstances, ignora
    if [[ -z "$resp" || "$resp" == "null" ]] || \
       ! printf '%s\n' "$resp" | jq -e '.pvmInstances? // empty' >/dev/null 2>&1; then
      echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - -> No pvmInstances found in '$ws' (skipping)" "1"
      continue
    fi

    # IMPORTANTE: usar process substitution, NÃO pipe, para o while correr no shell principal
    while IFS= read -r inst; do
      name=$(jq -r '.serverName' <<<"$inst")
      pvmid=$(jq -r '.pvmInstanceID' <<<"$inst")

      # Verificar se este nome já existe em .systems (case-insensitive)
      existing=$(printf '%s\n' "$existing_systems_json" | jq -c --arg name "$name" '
        .[] | select((.name // "" | ascii_downcase) == ($name | ascii_downcase))
      ' | head -n 1)

      if [[ -n "$existing" ]]; then
        # LPAR já existia no JSON: manter ip e lpar antigos, só actualizar pvmInstanceID
        old_ip=$(jq -r '.ip // ""'    <<<"$existing")
        old_lpar=$(jq -r '.lpar // ""' <<<"$existing")

        echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Existing LPAR '$name' in workspace '$ws' -> keeping IP '$old_ip', updating pvmInstanceID." "1"

        system_obj=$(jq -n \
          --arg name "$name" \
          --arg ip "$old_ip" \
          --arg pvmid "$pvmid" \
          --arg ws "$ws" \
          '{name:$name, ip:$ip, pvmInstanceID:$pvmid, workspace:$ws}')

      else
        # LPAR novo: decidir IP (com escolha se houver mais do que um)
        mapfile -t ip_array < <(jq -r '
          [
            (.networks[]? | .ipAddress?),
            (.networks[]? | .ipAddresses[]?)
          ]
          | map(select(. != null))
          | unique[]
        ' <<<"$inst")

        chosen_ip=""
        ip_count=${#ip_array[@]}

        if (( ip_count == 0 )); then
          echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - New LPAR '$name' in workspace '$ws' has no IP addresses reported by API (storing empty IP)." "1"

        elif (( ip_count == 1 )); then
          chosen_ip="${ip_array[0]}"
          echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - New LPAR '$name' in workspace '$ws' -> single IP detected: $chosen_ip" "1"

        else
          echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - New LPAR '$name' in workspace '$ws' has multiple IPs:" "1"
          idx=1
          for ip in "${ip_array[@]}"; do
            echo "  $idx) $ip"
            ((idx++))
          done

	# Loop until we get a valid choice
          while :; do
            # Always read from the terminal, not from redirected stdin
            printf "### Choose the IP to store in JSON [1-%d] (default 1): " "$ip_count" > /dev/tty

            if ! read -r choice < /dev/tty; then
              # If we get EOF (Ctrl+D or no TTY), default to 1
              choice=1
              echo > /dev/tty
              echo "### No input received, defaulting to option 1." > /dev/tty
            fi

            # Default = 1 if user just presses Enter
            if [[ -z "$choice" ]]; then
              choice=1
            fi

            if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ip_count )); then
              break
            fi

            echo "Invalid choice. Please enter a number between 1 and ${ip_count}." > /dev/tty
          done
          chosen_ip="${ip_array[$((choice-1))]}"
          echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Selected IP '$chosen_ip' for LPAR '$name'." "1"
        fi

        # LPAR novo -> lpar label vazio por agora
        system_obj=$(jq -n \
          --arg name "$name" \
          --arg ip "$chosen_ip" \
          --arg pvmid "$pvmid" \
          --arg ws "$ws" \
          '{name:$name, ip:$ip, pvmInstanceID:$pvmid, workspace:$ws}')
      fi

      # Acrescenta este objecto JSON (numa linha) ao acumulador
      all_systems+="$system_obj"$'\n'

    done < <(printf '%s\n' "$resp" | jq -c '.pvmInstances[]?')
  done

  # Se não conseguimos nada do API, não mexemos no JSON
  if [[ -z "$all_systems" ]]; then
    echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - WARNING: No systems retrieved from any workspace; keeping existing systems[] as-is." "1"
  else
    # Converte as linhas em array JSON e sobrescreve systems[]
    systems_json=$(printf '%s\n' "$all_systems" | jq -s '.')
    tmp_file="${CONFIG_JSON}.tmp"
    jq --argjson systems "$systems_json" '.systems = $systems' "$CONFIG_JSON" > "$tmp_file" && \
      mv "$tmp_file" "$CONFIG_JSON"

    echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Systems updated from IBM Cloud (new LPARs added, obsolete removed)." "1"
  fi

  echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Final (masked) config snapshot:" "1"
  print_masked_config
  echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - -updlpars finished." "1"
}


###### Devolve 0 se o pvmInstanceID ainda existe no workspace, 1 caso contrário
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
# Set base_url, CLOUD_INSTANCE_ID e CRN para um workspace curto (ex: WSMAD2)
set_ws_context() {
    local ws="$1"

    # Vai buscar crn e id do workspace ao JSON
    local crn id region_raw region_api base_var

    crn=$(jq -r --arg ws "$ws" '.workspaces[$ws].crn' "$CONFIG_JSON")
    id=$(jq -r --arg ws "$ws" '.workspaces[$ws].id'  "$CONFIG_JSON")

    if [[ -z "$crn" || "$crn" == "null" || -z "$id" || "$id" == "null" ]]; then
        echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - WARN: Workspace '$ws' not found or missing crn/id in $CONFIG_JSON" "1"
        return 1
    fi

    # CRN: crn:v1:bluemix:public:power-iaas:eu-de-1:...
    region_raw=$(echo "$crn" | awk -F: '{print $6}')
    region_api=$(echo "$region_raw" | tr '-' '_')   # eu-de-1 -> eu_de_1

    base_var="base_${region_api}"
    base_url="${!base_var:-}"

    if [[ -z "$base_url" ]]; then
        echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - WARN: No base URL defined for region '$region_raw' (expected var $base_var)" "1"
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
	print_masked_config
    ;;

  -addlpar)
    # Now: NAME IP PVM_ID WORKSPACE_SHORT  (no LPAR label)
    if [[ $# -ne 5 ]]; then
      echo "ERROR: Wrong syntax." >&2
      echo "Usage: $(basename "$0") -addlpar NAME IP PVM_ID WORKSPACE_SHORT" >&2
      exit 1
    fi

    # ensure_config_exists  # se quiseres obrigar a escolher o JSON aqui também

    lpar_name="$2"
    lpar_ip="$3"
    lpar_pvmid="$4"
    lpar_ws="$5"

    # Upsert system entry (case-insensitive on .name), sem campo "lpar"
    jq_inplace '
      .systems |= (
        ( . // [] )
        | map(select((.name // "" | ascii_downcase) != ($name | ascii_downcase)))
        + [ {
              "name": $name,
              "ip": $ip,
              "pvmInstanceID": $pvmid,
              "workspace": $ws
            } ]
      )
    ' \
      --arg name  "$lpar_name" \
      --arg ip    "$lpar_ip" \
      --arg pvmid "$lpar_pvmid" \
      --arg ws    "$lpar_ws"

    echo ""
    echo "LPAR '$lpar_name' added/updated in $CONFIG_JSON:"
    jq -r '
      .systems[]
      | select((.name // "" | ascii_downcase) == ($n | ascii_downcase))
    ' --arg n "$lpar_name" "$CONFIG_JSON"
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
