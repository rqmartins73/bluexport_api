#!/bin/bash
#
# bluexscrt_config.api
#
# Ricardo Martins - Blue Chip Portugal © 2025-2025
#################################################################

set -euo pipefail

VERSION="1.1.0"

conf_file="$HOME/bluexport_api_conf.json"
flag="${1:-}"

# Para -createconfig ainda não podemos assumir que o conf_file existe.
if [[ "$flag" == "-createconfig" ]]
then
	log_file="$HOME/bluexport.log"
	bluexscrt=""
	CONFIG_JSON=""
else
	log_file=$(jq -r '.log_file' "$conf_file")
	bluexscrt=$(jq -r '.bluexscrt' "$conf_file")
	# Default config JSON (can be overridden with env var BLUEXSCRT_JSON)
	CONFIG_JSON="${BLUEXSCRT_JSON:-"$bluexscrt"}"
fi

usage() {
  cat <<EOF

bluexscrt_config.api v$VERSION

Usage:
  $(basename "$0") [option] [args]

Options:
  -v
      Show tool version as JSON.

  -createconfig
      Run an interactive wizard to:
        - create the initial bluexscrt JSON (IBM Cloud API key, COS, SSH user/key)
        - create or update bluexport_conf.json
        - discover PowerVS workspaces via API and populate .workspaces
        - discover IBM i LPARs and populate .systems
        - optionally create the SSH user on the IBM i LPARs and copy the key

  -dellpar NAME
      Delete an LPAR (system) named NAME from .systems[] in the JSON config
      (match is case-insensitive on the "name" field).

  -addlpar NAME IP PVM_ID WORKSPACE_SHORT
      Add or update a single LPAR (system) entry in .systems[]:
        NAME            Logical system name (e.g. ibmi75m2)
        IP              IP address to use (SSH / bluexport)
        PVM_ID          PowerVS pvmInstanceID of the LPAR
        WORKSPACE_SHORT Workspace key as defined under .workspaces (e.g. WSMAD2)

  -updlpars
      Discover IBM i LPARs in all configured workspaces (via PowerVS APIs) and:
        - add new IBM i systems to .systems[]
        - remove systems that no longer exist
        - refresh pvmInstanceID and workspace for existing entries
      At the end, prints a masked snapshot of the current JSON config.

Examples:
  $(basename "$0") -v
  $(basename "$0") -createconfig
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

rc_list_powervs() {
  curl -s \
    -H "$header_auth" \
    -H "$header_accept" \
    "https://resource-controller.cloud.ibm.com/v2/resource_instances?type=service_instance&resource_id=power-iaas"
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

#### START:FUNCTION - get_base_url_for_workspace ####
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
#### START:FUNCTION - get_base_url_for_workspace ####

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

#### START:FUNCTION - print_masked_config ####
print_masked_config() {

  jq '
    .apikey |= ( if . != null then ( .[0:4] + "****" + .[-4:] ) else . end ) |
    .access.accessKey |= ( if . != null then ( .[0:4] + "****" + .[-4:] ) else . end ) |
    .access.secretKey |= ( if . != null then ( .[0:4] + "****" + .[-4:] ) else . end )
  ' "$CONFIG_JSON"
}
#### END:FUNCTION - print_masked_config ####

#### START:FUNCTION - Ping ####
ping_host() {
  ping -c3 -W3 "$1" &>/dev/null
}
#### END:FUNCTION - Ping ####

#### START:FUNCTION - create_vsi_user_from_json ####
create_vsi_user_from_json() {
  local vsi_user ssh_key_path pub_ssh_key usr_folder usr_folder_ssh auth_keys_path

  vsi_user=$(jq -r '.ssh.user' "$CONFIG_JSON")
  ssh_key_path=$(jq -r '.ssh.keyPath' "$CONFIG_JSON")

  if [[ -z "$vsi_user" || "$vsi_user" == "null" ]]; then
    echo "ERROR: .ssh.user not defined in $CONFIG_JSON" | tee -a "$log_file"
    return 1
  fi
  if [[ -z "$ssh_key_path" || "$ssh_key_path" == "null" ]]; then
    echo "ERROR: .ssh.keyPath not defined in $CONFIG_JSON" | tee -a "$log_file"
    return 1
  fi
  if [[ ! -f "$ssh_key_path.pub" ]]; then
    echo "ERROR: public key $ssh_key_path.pub not found." | tee -a "$log_file"
    return 1
  fi

  pub_ssh_key=$(cat "$ssh_key_path.pub")
  usr_folder="/home/${vsi_user^^}"
  usr_folder_ssh="$usr_folder/.ssh"
  auth_keys_path="$usr_folder_ssh/authorized_keys"

  mapfile -t systems < <(jq -c '.systems[]?' "$CONFIG_JSON")
  if (( ${#systems[@]} == 0 )); then
    echo "### No systems[] defined in $CONFIG_JSON; nothing to do." | tee -a "$log_file"
    return 0
  fi

  echo ""
  echo "### Preparing user '$vsi_user' on IBM i LPARs defined in $CONFIG_JSON ..."
  for sys in "${systems[@]}"; do
    local name ip user_exists
    name=$(jq -r '.name' <<<"$sys")
    ip=$(jq -r '.ip'   <<<"$sys")

    if [[ -z "$ip" || "$ip" == "null" ]]; then
      echo " - Skipping $name (no IP stored)." | tee -a "$log_file"
      continue
    fi

    echo ""
    echo "## LPAR $name with IP $ip"

    if ! ping_host "$ip"; then
      echo "   LPAR $name ($ip) not reachable (ping failed). Skipping." | tee -a "$log_file"
      continue
    fi

    read -p "Do you want to create/prepare user '$vsi_user' on $name ($ip)? (Y/N) " ans
    if [[ ! "$ans" =~ ^[Yy]$ ]]; then
      echo "   Skipping $name by user choice."
      continue
    fi

    echo "To create the user in $name you must provide an existing IBM i user with authority to create users and SSH in..."
    read -p "Admin user name on $name: " admin_user
    if [[ -z "$admin_user" ]]; then
      echo "   Empty admin user; skipping $name."
      continue
    fi

    read -p "If you have an SSH key for $admin_user, enter full path (or leave blank for password auth): " admin_key
    local sshkey_opt=""
    if [[ -n "$admin_key" ]]; then
      sshkey_opt="-i $admin_key"
    fi

    echo "Testing SSH connection to $name ($ip) as $admin_user ..."
    if ! ssh $sshkey_opt -o ConnectTimeout=5 -o ConnectionAttempts=1 "$admin_user@$ip" 'exit 0'; then
      echo "   FAILED: SSH test failed for $admin_user@$ip. Check credentials." | tee -a "$log_file"
      continue
    fi

    echo "Checking if user $vsi_user exists on $name ..."
    if ssh $sshkey_opt "$admin_user@$ip" "system 'DSPUSRPRF USRPRF($vsi_user) OUTPUT(*PRINT)'" >/dev/null 2>&1; then
      user_exists=1
      echo "   User $vsi_user already exists."
    else
      user_exists=0
      echo "   User $vsi_user does not exist."
    fi

    if (( user_exists == 0 )); then
      read -p "Create user profile $vsi_user on $name? (Y/N) " crt
      if [[ "$crt" =~ ^[Yy]$ ]]; then
        echo "Creating IBM i user profile $vsi_user on $name ..."
        ssh $sshkey_opt "$admin_user@$ip" "system 'CRTUSRPRF USRPRF($vsi_user) PASSWORD(*NONE) USRCLS(*USER) INLMNU(*SIGNOFF) SPCAUT(*ALLOBJ *JOBCTL)'"
      else
        echo "   Skipping user creation on $name."
      fi
    fi

    read -p "Create/refresh SSH environment for $vsi_user on $name (home/.ssh/authorized_keys)? (Y/N) " env_ans
    if [[ ! "$env_ans" =~ ^[Yy]$ ]]; then
      echo "   Skipping SSH environment for $name."
      continue
    fi

    echo "Preparing SSH environment for $vsi_user on $name ..."
    ssh $sshkey_opt "$admin_user@$ip" "
      mkdir -p '$usr_folder' '$usr_folder_ssh' &&
      chmod 755 '$usr_folder' &&
      chmod 700 '$usr_folder_ssh' &&
      echo '$pub_ssh_key' >> '$auth_keys_path' &&
      chmod 600 '$auth_keys_path' &&
      chown -R $vsi_user '$usr_folder'
    " || {
      echo "   FAILED to prepare SSH environment on $name." | tee -a "$log_file"
      continue
    }

    echo "Testing SSH login as $vsi_user@$ip ..."
    if ssh -i "$ssh_key_path" -o ConnectTimeout=5 -o ConnectionAttempts=1 "$vsi_user@$ip" 'exit 0'; then
      echo "   SUCCESS: SSH login as $vsi_user@$ip worked."
    else
      echo "   WARNING: SSH login as $vsi_user@$ip failed; check SSH configuration." | tee -a "$log_file"
    fi
  done

  echo ""
  echo "### create_vsi_user_from_json finished."
}
#### END:FUNCTION - create_vsi_user_from_json ####

#### START:FUNCTION - discover_workspaces_via_powervs ####
discover_workspaces_via_powervs() {
  echo "### Discovering PowerVS workspaces via PowerVS API (all known regions)..."

  local workspaces_json="{}"
  local found=0

  # Associative array para evitar processar o mesmo workspace ID mais do que uma vez
  declare -A seen_ids=()

  # Lista de variáveis base_* já definidas no script
  local ALL_BASE_VARS=(
    base_syd04 base_syd05
    base_sao1 base_sao4 base_sao5
    base_mon01 base_tor01
    base_eu_de_1 base_eu_de_2
    base_lon04 base_lon06
    base_che
    base_tok04 base_osa21
    base_mad02 base_mad04
    base_us_east base_wdc06 base_wdc07
    base_us_south base_dal10 base_dal12 base_dal14
  )

  for var in "${ALL_BASE_VARS[@]}"; do
    local url="${!var:-}"
    [[ -z "$url" ]] && continue

    # Faz o GET /v1/workspaces neste endpoint
    local resp
    resp=$(curl -sX GET "$url/v1/workspaces" -H "$header_auth" -H "$header_json")

    # Se não houver array .workspaces, ignora este endpoint
    if ! printf '%s\n' "$resp" | jq -e '.workspaces[]?' >/dev/null 2>&1; then
      continue
    fi

    # Percorre os workspaces devolvidos
    while IFS= read -r ws; do
      local name region crn wsid short

      # Campos reais com base no JSON que enviaste
      name=$(jq -r '.name // "UNKNOWN"' <<<"$ws")
      region=$(jq -r '.location.region // ""' <<<"$ws")
      crn=$(jq -r '.details.crn // ""' <<<"$ws")
      wsid=$(jq -r '.id // ""' <<<"$ws")

      # Se não tiver ID, ignora
      [[ -z "$wsid" ]] && continue

      # Se já vimos este ID antes, não voltamos a mostrar
      if [[ -n "${seen_ids[$wsid]:-}" ]]; then
        continue
      fi
      seen_ids["$wsid"]=1

      echo ""
      echo "Workspace found:"
      echo "  Name  : $name"
      echo "  Region: $region"
      echo "  CRN   : $crn"
      echo "  ID    : $wsid"

      # Pede shortname tipo WSMAD2 / WSFRA1 / WSFRA2 / WSMAD4
      while :; do
        # Escreve o prompt explicitamente para o terminal
        printf "Enter short name for this workspace (e.g. WSMAD2): " > /dev/tty

        # Lê SEMPRE do teclado (/dev/tty), nunca do stdin do while < <(...)
        if ! read -r short < /dev/tty; then
          echo "" > /dev/tty
          echo "### No input received for workspace '$name'; aborting discovery." > /dev/tty
          return 1
        fi

        if [[ -n "$short" ]]; then
          break
        fi

        echo "Short name cannot be empty." > /dev/tty
      done

      # Atualiza o JSON de workspaces em memória
      workspaces_json=$(printf '%s\n' "$workspaces_json" | jq \
        --arg key "$short" --arg crn "$crn" --arg id "$wsid" --arg nm "$name" \
        '. + {($key): {crn:$crn, id:$id, name:$nm}}')

      found=1
    done < <(printf '%s\n' "$resp" | jq -c '.workspaces[]?')
  done

  if (( found == 0 )); then
    echo "### No PowerVS workspaces found using PowerVS API endpoints." | tee -a "$log_file"
    return 1
  fi

  # Escreve a secção .workspaces no CONFIG_JSON
  local tmp_cfg="${CONFIG_JSON}.tmp"
  jq --argjson ws "$workspaces_json" '.workspaces = $ws' "$CONFIG_JSON" > "$tmp_cfg" && mv "$tmp_cfg" "$CONFIG_JSON"
  echo "### Workspaces section populated in $CONFIG_JSON" | tee -a "$log_file"

  return 0
}
#### END:FUNCTION - discover_workspaces_via_powervs ####

#### START:FUNCTION - run_createconfig ####
run_createconfig() {
  echo ""
  echo "### bluexscrt_config.api - Initial JSON configuration (-createconfig)"
  echo ""

  local default_json_path="$HOME/bluexscrt_bcce.json"
  local json_path apikey_input resource_group cos_region acckey seckey bucket vsi_user ssh_key_path default_ssh

  read -p "Full path for bluexscrt JSON config [$default_json_path]: " json_path
  if [[ -z "$json_path" ]]; then
    json_path="$default_json_path"
  fi

  # --- Credenciais IBM Cloud / COS / SSH ---
  while [[ -z "${apikey_input:-}" ]]; do
    read -s -p "IBM Cloud API key: " apikey_input
    echo ""
  done

  read -p "IBM Cloud Resource Group name (e.g. powervs): " resource_group

  while [[ -z "${acckey:-}" ]]; do
    read -s -p "COS Access Key: " acckey
    echo ""
  done

  while [[ -z "${seckey:-}" ]]; do
    read -s -p "COS Secret Key: " seckey
    echo ""
  done

  read -p "COS Bucket Name: " bucket
  read -p "COS Region (e.g. eu-es): " cos_region

  while [[ -z "${vsi_user:-}" ]]; do
    read -p "VSI SSH user (IBM i user profile) [bluexport]: " vsi_user
    if [[ -z "$vsi_user" ]]; then
      vsi_user="bluexport"
    fi
  done

  default_ssh="$HOME/.ssh/${vsi_user}_rsa"
  read -p "SSH private key full path [$default_ssh]: " ssh_key_path
  if [[ -z "$ssh_key_path" ]]; then
    ssh_key_path="$default_ssh"
  fi

  if [[ ! -f "$ssh_key_path" ]]; then
    echo "SSH key $ssh_key_path does not exist."
    read -p "Do you want to create it now with ssh-keygen (Y/N)? " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
      mkdir -p "$(dirname "$ssh_key_path")"
      ssh-keygen -N "" -t rsa -f "$ssh_key_path"
    else
      echo "WARNING: SSH key does not exist yet. You must create it before using SSH features."
    fi
  fi

  echo ""
  echo "### Summary:"
  echo "  JSON config: $json_path"
  echo "  Resource Group: $resource_group"
  echo "  COS Bucket: $bucket"
  echo "  COS Region: $cos_region"
  echo "  VSI SSH user: $vsi_user"
  echo "  SSH key: $ssh_key_path"
  echo ""
  read -p "Is this information correct (Y/N)? " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Aborting -createconfig by user choice."
    exit 1
  fi

  # 1) Criar o JSON base (sem workspaces / systems)
  cat > "$json_path" <<EOF
{
  "apikey": "$apikey_input",
  "access": {
    "accessKey": "$acckey",
    "secretKey": "$seckey",
    "bucketName": "$bucket",
    "region": "$cos_region"
  },
  "ssh": {
    "user": "$vsi_user",
    "keyPath": "$ssh_key_path"
  },
  "resourceGroup": "$resource_group",
  "workspaces": {},
  "systems": []
}
EOF
  chmod 600 "$json_path"
  echo "### Created bluexscrt JSON at $json_path"

  # 2) Criar/atualizar bluexport_conf.json
  if [[ ! -f "$conf_file" ]]; then
    cat > "$conf_file" <<EOF
{
  "bluexscrt": "$json_path",
  "log_file": "$HOME/bluexport.log",
  "job_log": "$HOME/bluex_job.log",
  "job_test_log": "$HOME/bluex_job_test.log",
  "job_id": "$HOME/bluex_job_id.log",
  "job_log_short": "$HOME/bluex_job",
  "job_monitor": "$HOME/bluex_job_monitor.tmp",
  "operid_file": "$HOME/operid_file.log",
  "vsi_list_id_tmp": "$HOME/bluex_vsi_list_id.tmp",
  "vsi_list_tmp": "$HOME/bluex_vsi_list.tmp",
  "volumes_file": "$HOME/bluex_volumes_file.tmp",
  "vol_ch_tier": "$HOME/bluex_vol_ch_tier.tmp",
  "vol_failed_tst": "$HOME/bluex_vol_failed_tst.tmp",
  "iasp_names_file": "$HOME/iasp_names.tmp",
  "env_file": "$HOME/.env_bluexport",
  "snap_retention": 2
}
EOF
    echo "### Created $conf_file"
  else
    read -p "bluexport_conf.json already exists. Update its bluexscrt path to $json_path? (Y/N) " upd
    if [[ "$upd" =~ ^[Yy]$ ]]; then
      tmp="${conf_file}.tmp"
      jq --arg path "$json_path" '.bluexscrt = $path' "$conf_file" > "$tmp" && mv "$tmp" "$conf_file"
      echo "### Updated bluexscrt path in $conf_file"
    fi
  fi

  # 3) Atualizar variáveis globais para o resto da run
  log_file=$(jq -r '.log_file' "$conf_file")
  bluexscrt="$json_path"
  CONFIG_JSON="$json_path"

  # 4) Obter IAM token (para discovery via API)
  iam_token=$(curl -s -X POST "https://iam.cloud.ibm.com/identity/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -H "Accept: application/json" \
    -d "grant_type=urn:ibm:params:oauth:grant-type:apikey&apikey=${apikey_input}" | jq -r '.access_token')

  if [[ -z "$iam_token" || "$iam_token" == "null" ]]; then
    echo "ERROR: Failed to obtain IAM token during -createconfig" | tee -a "$log_file"
    exit 1
  fi

  header_auth="Authorization: Bearer $iam_token"
  header_json="Content-Type: application/json"
  header_accept="Accept: application/json"

  # 5) Descobrir e preencher workspaces via PowerVS API
  if discover_workspaces_via_powervs; then
    echo "### Workspace discovery completed and saved into $CONFIG_JSON."

    # 6) Preencher systems[] usando a mesma lógica de -updlpars
    run_updlpars_api

  else
    echo "### WARNING: Workspace discovery failed or returned no workspaces. systems[] will not be updated automatically." | tee -a "$log_file"
  fi

  # 7) Criar utilizador nas LPARs (opcional, mas AGORA já há systems[])
  read -p "Do you want to create the VSI user '$vsi_user' on the IBM i LPARs and copy the SSH key now? (Y/N) " crt
  if [[ "$crt" =~ ^[Yy]$ ]]; then
    create_vsi_user_from_json
  fi

  echo "### -createconfig finished."
}
#### END:FUNCTION - run_createconfig ####

#### START:FUNCTION - run_updlpars_api ####
run_updlpars_api() {
  get_iam_token
  echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - === Starting -updlpars using IBM Cloud APIs (IBM i only) ===" "1"

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

    # Se resposta vazia, ignora logo
    if [[ -z "$resp" || "$resp" == "null" ]]; then
      echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - -> Empty response from ins_ls in '$ws' (skipping)" "1"
      continue
    fi

    local ws_ibmi_found=0

    # Iterar sobre TODAS as pvmInstances; filtramos IBM i em bash/jq
    while IFS= read -r inst; do
      # Decide se é IBM i com base em vários sinais (suporta esquemas antigos e novos)
      os_flag=$(jq -r '
        if ((.osType? // "" | ascii_downcase) == "ibmi") then
          "yes"
        elif ((.operatingSystem? | type == "string")
              and ((.operatingSystem | ascii_downcase) | test("ibmi|v7r[0-9]m[0-9]"; "i"))) then
          "yes"
        elif ((.operatingSystem.type? // "" | ascii_downcase) == "ibmi") then
          "yes"
        elif .configuration.softwareLicenses.ibmiCSS? == true then
          "yes"
        elif .softwareLicenses.ibmiCSS? == true then
          "yes"
        else
          "no"
        end
      ' <<<"$inst")

      if [[ "$os_flag" != "yes" ]]; then
        # não é IBM i, ignoramos
        continue
      fi

      ws_ibmi_found=1

      # Nome e ID: suportar tanto serverName/pvmInstanceID como name/id
      name=$(jq -r '.serverName // .name // "UNKNOWN"' <<<"$inst")
      pvmid=$(jq -r '.pvmInstanceID // .id // ""'      <<<"$inst")

      if [[ -z "$pvmid" || "$pvmid" == "null" ]]; then
        echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - -> Skipping IBM i instance '$name' in '$ws' (no pvmInstanceID/id)." "1"
        continue
      fi

      # Verificar se este nome já existe em .systems (case-insensitive)
      existing=$(printf '%s\n' "$existing_systems_json" | jq -c --arg name "$name" '
        .[] | select((.name // "" | ascii_downcase) == ($name | ascii_downcase))
      ' | head -n 1)

      if [[ -n "$existing" ]]; then
        # LPAR já existia no JSON: manter ip antigo, só actualizar pvmInstanceID/workspace
        old_ip=$(jq -r '.ip // ""' <<<"$existing")

        echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Existing IBM i LPAR '$name' in workspace '$ws' -> keeping IP '$old_ip', updating pvmInstanceID." "1"

        system_obj=$(jq -n \
          --arg name "$name" \
          --arg ip "$old_ip" \
          --arg pvmid "$pvmid" \
          --arg ws "$ws" \
          '{name:$name, ip:$ip, pvmInstanceID:$pvmid, workspace:$ws}')

      else
        # LPAR novo: decidir IP (com escolha se houver mais do que um)
        # Suportar:
        #  - addresses[].ipAddress/ip
        #  - networks[].ipAddress/ip/ipAddresses[]
        #  - networkPorts[].privateIP/ipAddress
        mapfile -t ip_array < <(jq -r '
          [
            (.addresses[]?      | .ipAddress?),
            (.addresses[]?      | .ip?),
            (.networks[]?       | .ipAddress?),
            (.networks[]?       | .ip?),
            (.networks[]?       | .ipAddresses[]?),
            (.networkPorts[]?   | .privateIP?),
            (.networkPorts[]?   | .ipAddress?)
          ]
          | map(select(. != null))
          | unique[]
        ' <<<"$inst")

        chosen_ip=""
        ip_count=${#ip_array[@]}

        if (( ip_count == 0 )); then
          echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - New IBM i LPAR '$name' in workspace '$ws' has no IP addresses reported by API (storing empty IP)." "1"

        elif (( ip_count == 1 )); then
          chosen_ip="${ip_array[0]}"
          echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - New IBM i LPAR '$name' in workspace '$ws' -> single IP detected: $chosen_ip" "1"

        else
          echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - New IBM i LPAR '$name' in workspace '$ws' has multiple IPs:" "1"
          idx=1
          for ip in "${ip_array[@]}"; do
            echo "  $idx) $ip"
            ((idx++))
          done

          # Loop until we get a valid choice
          while :; do
            printf "### Choose the IP to store in JSON [1-%d] (default 1): " "$ip_count" > /dev/tty

            if ! read -r choice < /dev/tty; then
              choice=1
              echo > /dev/tty
              echo "### No input received, defaulting to option 1." > /dev/tty
            fi

            if [[ -z "$choice" ]]; then
              choice=1
            fi

            if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ip_count )); then
              break
            fi

            echo "Invalid choice. Please enter a number between 1 and ${ip_count}." > /dev/tty
          done

          chosen_ip="${ip_array[$((choice-1))]}"
          echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Selected IP '$chosen_ip' for IBM i LPAR '$name'." "1"
        fi

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

    if (( ws_ibmi_found == 0 )); then
      echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - -> No IBM i instances matched in '$ws' (based on osType/operatingSystem/softwareLicenses)." "1"
    fi
  done

  # Se não conseguimos nada do API, não mexemos no JSON
  if [[ -z "$all_systems" ]]; then
    echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - WARNING: No IBM i systems retrieved from any workspace; keeping existing systems[] as-is." "1"
  else
    # Converte as linhas em array JSON e sobrescreve systems[]
    systems_json=$(printf '%s\n' "$all_systems" | jq -s '.')
    tmp_file="${CONFIG_JSON}.tmp"
    jq --argjson systems "$systems_json" '.systems = $systems' "$CONFIG_JSON" > "$tmp_file" && \
      mv "$tmp_file" "$CONFIG_JSON"

    echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Systems updated from IBM Cloud (IBM i only: new LPARs added, obsolete removed)." "1"
  fi

  echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Final (masked) config snapshot:" "1"
  print_masked_config
  echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - -updlpars finished." "1"
}
#### END:FUNCTION - run_updlpars_api ####

#### START:FUNCTION - vsi_exists_in_cloud ####
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
#### END:FUNCTION - vsi_exists_in_cloud ####

#### START:FUNCTION - jq_inplace ####
# Safe jq wrapper that writes back to CONFIG_JSON
jq_inplace() {
  local filter="$1"
  shift
  tmp_file="$(mktemp "${CONFIG_JSON}.XXXX")"
  jq "$filter" "$@" "$CONFIG_JSON" > "$tmp_file"
  mv "$tmp_file" "$CONFIG_JSON"
}
#### END:FUNCTION - jq_inplace ####


if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

#### START:FUNCTION - set_ws_context ####
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
#### END:FUNCTION - set_ws_context ####

case "$flag" in
  -v)
    # Version as JSON
    jq -n --arg version "$VERSION" '{tool:"bluexscrt_config.api", version:$version}'
    ;;

  -createconfig)
    run_createconfig
    ;;

  -dellpar)
    if [[ $# -ne 2 ]]; then
      echo "ERROR: Wrong syntax." >&2
      echo "Usage: $(basename "$0") -dellpar NAME" >&2
      exit 1
    fi
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
