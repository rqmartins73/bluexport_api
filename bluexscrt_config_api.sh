#!/bin/bash
#
# bluexscrt_config_api.sh
#
# Ricardo Martins - Blue Chip Portugal © 2025-2026
#################################################################

set -euo pipefail

VERSION="2.0"

conf_file="$HOME/bluexport_api_conf.json"

# First argument (safe even when script is called with no args)
flag="${1:-}"

# Version flag
if [[ "$flag" == "-v" || "$flag" == "--version" ]]; then
	if [ $# -gt 1 ]; then
		echo "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments!! Syntax: $(basename "$0") -v | --version"
		exit 1
	fi
	echo
	jq -n --arg version "$VERSION" '{tool:"bluexscrt_config_api.sh", version:$version, author:"Ricardo Martins", company:"Blue Chip Portugal", license:"MIT", maintained:"2025-2026"}'
	echo "$(date +%Y-%m-%d_%H:%M:%S)"
	echo
	exit 0
fi

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

bluexscrt_config_api.sh v$VERSION

Usage:
  $(basename "$0") [option] [args]

Options:
  -v | --version
      Show tool version as JSON (tool name, version, author, license).

  -createconfig
      Run an interactive wizard to:
        - create the initial bluexscrt JSON (IBM Cloud API key, COS credentials, SSH user/key)
        - create or update bluexport_api_conf.json (the main config file used by bluexport_api.sh)
        - discover Cloud Object Storage instances and populate .cos_instances
        - discover PowerVS workspaces via API and populate .workspaces
        - discover all LPARs (any OS) in all workspaces and populate .systems,
          classifying each as os=ibmi|aix|linux|other
        - optionally create the SSH user on the LPARs classified os=ibmi and deploy
          the public key (non-IBM i entries are skipped and reported by count)

  -dellpar NAME
      Delete an LPAR (system) named NAME from .systems[] in the JSON config.
      The match on "name" is case-insensitive.

  -addlpar NAME IP PVM_ID WORKSPACE_SHORT OS
      Add or update a single LPAR (system) entry in .systems[]:
        NAME            Logical system name (e.g. ibmi75m2)
        IP              IP address used for SSH and bluexport operations
        PVM_ID          PowerVS pvmInstanceID of the LPAR
        WORKSPACE_SHORT Workspace key as defined under .workspaces in the JSON (e.g. WSMAD2)
        OS              ibmi | aix | linux | other - determines whether operations that
                         flush ASPs (CHGASPACT) run for this LPAR (ibmi only)

  -updlpars
      Refresh LPARs (all OS: ibmi/aix/linux/other) and COS instances from IBM Cloud APIs:
        - discover all LPARs in all configured workspaces, classifying each as
          os=ibmi|aix|linux|other (osDetail keeps the raw API value)
        - add new systems to .systems[], remove obsolete ones, refresh pvmInstanceID/os/osDetail
        - refresh .cos_instances from IBM Cloud
      At the end, prints a masked snapshot of the current JSON config.
      Upgrade note: run this once after upgrading to backfill os/osDetail on any
      pre-existing .systems[] entry that predates this field (treated as ibmi until then).

  -updws
      Refresh PowerVS workspaces from IBM Cloud APIs:
        - discover PowerVS workspaces across all known regions
        - add new workspaces to .workspaces (prompts for a short name, e.g. WSMAD2)
        - refresh crn/name for already-known workspaces (matched by workspace ID)
        - remove workspaces from .workspaces that no longer exist in IBM Cloud
        - also remove any LPAR in .systems[] left orphaned by a removed workspace
      If any new workspace was found, automatically runs -updlpars at the end
      to populate the LPARs of the new workspace(s).

  -h | --help
      Show this help.

Examples:
  $(basename "$0") -v
  $(basename "$0") -createconfig
  $(basename "$0") -dellpar ibmi75m2
  $(basename "$0") -addlpar ibmi75m2 172.26.2.5 7ed4ea03-... WSMAD2 ibmi
  $(basename "$0") -updlpars
  $(basename "$0") -updws
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
  echo "### File '$newpath' does not exist."
  read -p "Do you want to create it now using -createconfig? (Y/N) " create_ans

  if [[ "$create_ans" =~ ^[Yy]$ ]]; then
    echo ""
    echo "### Launching -createconfig wizard..."
    echo ""

    # Force createconfig to use this path
    export BLUEXSCRT_JSON="$newpath"

    run_createconfig
    exit 0
  else
    echo "Aborting by user choice."
    exit 1
  fi
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
# Derive base_url from workspace CRN
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
#### END:FUNCTION - get_base_url_for_workspace ####

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

## COS
list_object() {
	curl -sX GET https://s3.$REGION.cloud-object-storage.appdomain.cloud/$BUCKET?list-type=2 -H "$header_auth"
}

object_delete() {
	curl -X DELETE https://s3.$REGION.cloud-object-storage.appdomain.cloud/$BUCKET/$KEY -H "$header_auth"
}

cos_ins_ls() {
	# The Resource Controller "list resource instances" API paginates (default
	# page size is small - 10). Scanning ALL service instances in the account
	# (no resource_id filter, unlike rc_list_powervs) can easily span several
	# pages once PowerVS workspaces/VPC/etc are added, silently dropping COS
	# instances that land past page 1 if we only ever read the first page.
	# Follow next_url until exhausted and merge everything into one .resources[].
	#
	# Each page's resources are staged into a temp file rather than an
	# --argjson/command-line argument: a real account's full resource_instances
	# response (even one page, at limit=100) can be large enough to hit the
	# OS's ARG_MAX ("Argument list too long"), which killed the whole script
	# under set -e the first time this was tried.
	local url="https://resource-controller.cloud.ibm.com/v2/resource_instances?type=service_instance&limit=100"
	local page next tmpdir
	local -a page_files=()

	tmpdir=$(mktemp -d)

	while [[ -n "$url" ]]; do
		page=$(curl -sS --connect-timeout 30 --max-time 60 -X GET "$url" -H "$header_auth" -H "$header_accept")

		# A network/auth hiccup can make curl return an empty body or an HTML/plain-text
		# error instead of JSON. Validate before touching it with jq, and just stop
		# paginating with whatever was already collected instead of aborting the script.
		if ! jq -e . >/dev/null 2>&1 <<<"$page"; then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - WARNING: cos_ins_ls got a non-JSON response from Resource Controller (network/auth issue?). Raw response (first 200 chars): ${page:0:200}" "1"
			break
		fi

		local page_file="$tmpdir/page_${#page_files[@]}.json"
		jq '.resources // []' <<<"$page" > "$page_file"
		page_files+=("$page_file")

		next=$(jq -r '.next_url // empty' <<<"$page")
		if [[ -n "$next" ]]; then
			url="https://resource-controller.cloud.ibm.com${next}"
		else
			url=""
		fi
	done

	if (( ${#page_files[@]} == 0 )); then
		echo '{"resources": []}'
	else
		jq -s 'add | {resources: .}' "${page_files[@]}"
	fi

	rm -rf "$tmpdir"
}

cos_ls_buckets() {
	curl -sX GET https://s3.$REGION.cloud-object-storage.appdomain.cloud/ -H "$header_auth" -H "ibm-service-instance-id: $SERVICE_INSTANCE_ID"
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

  local skipped_non_ibmi
  skipped_non_ibmi=$(jq '[.systems[]? | select((.os // "ibmi") != "ibmi")] | length' "$CONFIG_JSON")
  if (( skipped_non_ibmi > 0 )); then
    echo "### Skipping $skipped_non_ibmi non-IBM i system(s) in .systems[] (SSH user setup is IBM i-only for now)." | tee -a "$log_file"
  fi

  mapfile -t systems < <(jq -c '.systems[]? | select((.os // "ibmi") == "ibmi")' "$CONFIG_JSON")
  if (( ${#systems[@]} == 0 )); then
    echo "### No IBM i systems[] defined in $CONFIG_JSON; nothing to do." | tee -a "$log_file"
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

    read -p "If you have an SSH key for $admin_user, enter full path (or leave blank for password auth, it will be asked for password several times): " admin_key
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
        ssh $sshkey_opt "$admin_user@$ip" "system 'CRTUSRPRF USRPRF($vsi_user) PASSWORD(*NONE) USRCLS(*USER) INLMNU(*SIGNOFF) SPCAUT(*ALLOBJ *JOBCTL *IOSYSCFG)'"
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
	echo "### bluexscrt_config_api.sh - Initial JSON configuration (-createconfig)"
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
	# 1) Criar o JSON base
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

	# 2) Criar/atualizar bluexport_api_conf.json
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
		read -p "bluexport_api_conf.json already exists. Update its bluexscrt path to $json_path? (Y/N) " upd
		if [[ "$upd" =~ ^[Yy]$ ]]; then
			tmp="${conf_file}.tmp"
			jq --arg path "$json_path" '.bluexscrt = $path' "$conf_file" > "$tmp" && mv "$tmp" "$conf_file"
			echo "### Updated bluexscrt path in $conf_file"
		fi
	fi
	# 3) Atualizar variáveis globais
	log_file=$(jq -r '.log_file' "$conf_file")
	bluexscrt="$json_path"
	CONFIG_JSON="$json_path"
	# 4) IAM Token
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
	# 5a) Descobrir instâncias Cloud Object Storage
	cos_raw=$(cos_ins_ls)
	cos_total=$(jq '[.resources[]?] | length' <<<"$cos_raw" 2>/dev/null)
	cos_instances_json=$(jq '
		[.resources[]?
			| select(.crn | contains(":cloud-object-storage:"))
			| {name, guid, crn}]
		| reduce .[] as $i ({}; .[$i.name] = {guid: $i.guid, crn: $i.crn})
	' <<<"$cos_raw")
	if [[ -n "$cos_instances_json" && "$cos_instances_json" != "{}" ]]; then
		tmp_cos="${json_path}.tmp"
		jq --argjson cos "$cos_instances_json" '.cos_instances = $cos' "$json_path" > "$tmp_cos" && mv "$tmp_cos" "$json_path"
		echo "### Added cos_instances section to $json_path ($(jq 'length' <<<"$cos_instances_json") instance(s))"
	else
		echo "### WARNING: No Cloud Object Storage instances found among ${cos_total:-0} resource instance(s) scanned (cos_instances not added)." | tee -a "$log_file"
	fi
	# 5) Descobrir workspaces PowerVS
	if discover_workspaces_via_powervs; then
		echo "### Workspace discovery completed."

		# 6) Atualizar systems[]
		run_updlpars_api
	else
		echo "### WARNING: No workspaces found — systems[] will not be updated." | tee -a "$log_file"
	fi
	# 7) Criar utilizador SSH nas LPARs
	read -p "Do you want to create the VSI user '$vsi_user' on the IBM i LPARs now? (Y/N) " crt
	if [[ "$crt" =~ ^[Yy]$ ]]; then
		create_vsi_user_from_json
	fi
	echo "### -createconfig finished."
}
#### END:FUNCTION - run_createconfig ####

#### START:FUNCTION - run_updlpars_api ####
run_updlpars_api() {
	get_iam_token
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - === Starting -updlpars using IBM Cloud APIs ===" "1"

	# 0) Refresh cos_instances from IBM Cloud (Cloud Object Storage instances)
	cos_raw=$(cos_ins_ls 2>>"$log_file")
	cos_total=$(jq '[.resources[]?] | length' <<<"$cos_raw" 2>/dev/null)
	cos_instances_json=$(jq '
		[.resources[]?
			| select(.crn | contains(":cloud-object-storage:"))
			| {name, guid, crn}]
		| reduce .[] as $i ({}; .[$i.name] = {guid: $i.guid, crn: $i.crn})
	' <<<"$cos_raw")

	if [[ -n "$cos_instances_json" && "$cos_instances_json" != "{}" ]]; then
		tmp_cos="${CONFIG_JSON}.tmp"
		jq --argjson cos "$cos_instances_json" '.cos_instances = $cos' "$CONFIG_JSON" > "$tmp_cos" && mv "$tmp_cos" "$CONFIG_JSON"
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - cos_instances section refreshed from IBM Cloud ($(jq 'length' <<<"$cos_instances_json") instance(s))." "1"
	else
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - WARNING: No Cloud Object Storage instances found among ${cos_total:-0} resource instance(s) scanned; cos_instances not updated." "1"
	fi

	# Load current systems[] from JSON (to detect existing vs new)
	# Aqui guardamos APENAS o array .systems
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

		local ws_found=0
		local ws_new_count=0
		local ws_existing_count=0

		# Iterar sobre TODAS as pvmInstances de todos os OS (ibmi/aix/linux/other)
		while IFS= read -r inst; do
			ws_found=1

			# Classificar o OS: ibmi (deteção multi-sinal já existente) / aix / linux (distros
			# conhecidas) / other (qualquer osType não reconhecido - nunca assumir linux por
			# eliminação, ver spec 2026-08-05 secção A).
			os_class=$(jq -r '
				def is_ibmi:
					((.osType? // "" | ascii_downcase) == "ibmi")
					or ((.operatingSystem? | type == "string") and ((.operatingSystem | ascii_downcase) | test("ibmi|v7r[0-9]m[0-9]"; "i")))
					or ((.operatingSystem.type? // "" | ascii_downcase) == "ibmi")
					or (.configuration.softwareLicenses.ibmiCSS? == true)
					or (.softwareLicenses.ibmiCSS? == true);
				def linux_distros: ["rhel","sles","suse","ubuntu","debian","centos","fedora","rocky","almalinux","oraclelinux"];
				if is_ibmi then "ibmi"
				elif ((.osType? // "" | ascii_downcase) == "aix") then "aix"
				elif ((.osType? // "" | ascii_downcase) as $t | linux_distros | index($t) != null) then "linux"
				else "other"
				end
			' <<<"$inst")

			os_detail=$(jq -r '
				if ((.operatingSystem? | type) == "string") then
					(if ((.operatingSystem | ascii_downcase) == "unknown" or .operatingSystem == "") then
						(.osType? // "unknown")
					else
						.operatingSystem
					end)
				else
					(.osType? // "unknown")
				end
			' <<<"$inst")

			# Nome e ID: suportar tanto serverName/pvmInstanceID como name/id
			name=$(jq -r '.serverName // .name // "UNKNOWN"' <<<"$inst")
			pvmid=$(jq -r '.pvmInstanceID // .id // ""'      <<<"$inst")

			if [[ -z "$pvmid" || "$pvmid" == "null" ]]; then
				echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - -> Skipping LPAR '$name' in '$ws' (no pvmInstanceID/id)." "1"
				continue
			fi

			# Verificar se este nome já existe em .systems (case-insensitive)
			existing_obj=$(jq -r --arg name_lc "$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')" '
				.[]? | select((.name // "" | ascii_downcase) == $name_lc)
			' <<<"$existing_systems_json")

			if [[ -n "$existing_obj" && "$existing_obj" != "null" ]]; then
				# Já existe: mantemos o IP anterior, actualizamos ws/pvmid/os/osDetail
				old_ip=$(jq -r '.ip // ""' <<<"$existing_obj")
				ws_existing_count=$((ws_existing_count + 1))

				system_obj=$(jq -n \
					--arg name "$name" \
					--arg ip "$old_ip" \
					--arg pvmid "$pvmid" \
					--arg ws "$ws" \
					--arg os "$os_class" \
					--arg osdetail "$os_detail" \
					'{name:$name, ip:$ip, pvmInstanceID:$pvmid, workspace:$ws, os:$os, osDetail:$osdetail}')

			else
				ws_new_count=$((ws_new_count + 1))
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
					echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - New LPAR '$name' in workspace '$ws' has no IP addresses reported by API (storing empty IP)." "1"

				elif (( ip_count == 1 )); then
					chosen_ip="${ip_array[0]}"
					echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - New LPAR '$name' in workspace '$ws' -> single IP detected: $chosen_ip" "1"

				else
					echoscreen "" "1"
					echoscreen "============================================================" "1"
					echoscreen "LPAR '$name' in workspace '$ws' has multiple IP addresses:" "1"
					for (( idx=0; idx<ip_count; idx++ )); do
						echoscreen "  [$((idx+1))] ${ip_array[$idx]}" "1"
					done
					echoscreen "------------------------------------------------------------" "1"

					# Tentar sugerir IP com base em prefNetwork/prefIP
					default_choice=""
					if [[ -n "${prefNetwork:-}" ]]; then
						for (( idx=0; idx<ip_count; idx++ )); do
							if [[ "${ip_array[$idx]}" == "$prefNetwork"* ]]; then
								default_choice=$((idx+1))
								break
							fi
						done
					fi

					if [[ -z "$default_choice" && -n "${prefIP:-}" ]]; then
						for (( idx=0; idx<ip_count; idx++ )); do
							if [[ "${ip_array[$idx]}" == "$prefIP" ]]; then
								default_choice=$((idx+1))
								break
							fi
						done
					fi

					if [[ -n "$default_choice" ]]; then
						echoscreen "Suggested default based on preferences (prefNetwork/prefIP): [$default_choice]" "1"
					fi

					while true; do
						# Prompt vai sempre para o terminal real
						printf "Select IP index [1-%d] (ENTER for default %s): " \
							"$ip_count" "${default_choice:-1}" > /dev/tty

						# Ler SEMPRE do /dev/tty, nunca do stdin do while < <(...)
						if ! read -r choice < /dev/tty; then
							# Se por algum motivo não houver input (EOF, etc.) assumimos default
							choice="${default_choice:-1}"
						fi

						# Se o utilizador só carregar ENTER:
						if [[ -z "$choice" ]]; then
							if [[ -n "$default_choice" ]]; then
								choice="$default_choice"
							else
								# Sem default configurado → assume índice 1
								choice=1
							fi
						fi

						# Validar se é numérico
						if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
							echo "Invalid input. Please enter a number between 1 and $ip_count, or press ENTER for default." > /dev/tty
							continue
						fi

						# Validar range
						if (( choice < 1 || choice > ip_count )); then
							echo "Choice out of range. Please select between 1 and $ip_count." > /dev/tty
							continue
						fi

						break
					done

					chosen_ip="${ip_array[$((choice-1))]}"
					echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Selected IP '$chosen_ip' for LPAR '$name'." "1"
				fi

				system_obj=$(jq -n \
					--arg name "$name" \
					--arg ip "$chosen_ip" \
					--arg pvmid "$pvmid" \
					--arg ws "$ws" \
					--arg os "$os_class" \
					--arg osdetail "$os_detail" \
					'{name:$name, ip:$ip, pvmInstanceID:$pvmid, workspace:$ws, os:$os, osDetail:$osdetail}')
			fi

			# Acrescenta este objecto JSON (numa linha) ao acumulador
			all_systems+="$system_obj"$'\n'

		done < <(printf '%s\n' "$resp" | jq -c '.pvmInstances[]?')

		if (( ws_found == 0 )); then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - -> No LPARs found in '$ws'." "1"
		elif (( ws_new_count > 0 )); then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - -> Workspace '$ws': $ws_new_count new LPAR(s) added, $ws_existing_count confirmed unchanged." "1"
		else
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - -> Workspace '$ws': $ws_existing_count LPAR(s) confirmed, no changes." "1"
		fi
	done

	# Se não conseguimos nada do API, não mexemos no JSON
	if [[ -z "$all_systems" ]]; then
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - WARNING: No LPARs retrieved from any workspace; keeping existing systems[] as-is." "1"
	else
		# Converte as linhas em array JSON e sobrescreve systems[]
		systems_json=$(printf '%s\n' "$all_systems" | jq -s '.')
		tmp_file="${CONFIG_JSON}.tmp"
		jq --argjson systems "$systems_json" '.systems = $systems' "$CONFIG_JSON" > "$tmp_file" && \
			mv "$tmp_file" "$CONFIG_JSON"

		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Systems updated from IBM Cloud (all OS: new LPARs added, obsolete removed)." "1"
	fi

	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Final (masked) config snapshot:" "1"
	print_masked_config
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - -updlpars finished." "1"
}
#### END:FUNCTION - run_updlpars_api ####

#### START:FUNCTION - run_updws_api ####
run_updws_api() {
	get_iam_token
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - === Starting -updws using IBM Cloud APIs ===" "1"

	existing_workspaces_json=$(jq '.workspaces // {}' "$CONFIG_JSON")
	workspaces_json="$existing_workspaces_json"

	declare -A seen_ids=()
	new_found=0

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

		local resp
		resp=$(curl -sX GET "$url/v1/workspaces" -H "$header_auth" -H "$header_json")

		if ! printf '%s\n' "$resp" | jq -e '.workspaces[]?' >/dev/null 2>&1; then
			continue
		fi

		while IFS= read -r ws; do
			local name region crn wsid short existing_key

			name=$(jq -r '.name // "UNKNOWN"' <<<"$ws")
			region=$(jq -r '.location.region // ""' <<<"$ws")
			crn=$(jq -r '.details.crn // ""' <<<"$ws")
			wsid=$(jq -r '.id // ""' <<<"$ws")

			[[ -z "$wsid" ]] && continue

			if [[ -n "${seen_ids[$wsid]:-}" ]]; then
				continue
			fi
			seen_ids["$wsid"]=1

			existing_key=$(jq -r --arg id "$wsid" '
				to_entries[]? | select(.value.id == $id) | .key
			' <<<"$existing_workspaces_json" | head -1)

			if [[ -n "$existing_key" ]]; then
				# Already known: refresh crn/name under the same short key
				workspaces_json=$(jq --arg key "$existing_key" --arg crn "$crn" --arg id "$wsid" --arg nm "$name" \
					'.[$key] = {crn:$crn, id:$id, name:$nm}' <<<"$workspaces_json")
				echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - -> Workspace '$name' ($existing_key) refreshed." "1"
			else
				echo ""
				echo "New workspace found:"
				echo "  Name  : $name"
				echo "  Region: $region"
				echo "  CRN   : $crn"
				echo "  ID    : $wsid"

				short=""
				while :; do
					printf "Enter short name for this workspace (e.g. WSMAD2): " > /dev/tty

					if ! read -r short < /dev/tty; then
						echo "" > /dev/tty
						echo "### No input received for workspace '$name'; skipping." > /dev/tty
						short=""
						break
					fi

					if [[ -n "$short" ]]; then
						break
					fi

					echo "Short name cannot be empty." > /dev/tty
				done

				if [[ -z "$short" ]]; then
					continue
				fi

				workspaces_json=$(jq --arg key "$short" --arg crn "$crn" --arg id "$wsid" --arg nm "$name" \
					'. + {($key): {crn:$crn, id:$id, name:$nm}}' <<<"$workspaces_json")

				new_found=1
				echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - -> New workspace '$name' added as '$short'." "1"
			fi
		done < <(printf '%s\n' "$resp" | jq -c '.workspaces[]?')
	done

	# Remove workspaces that no longer exist in IBM Cloud. Only when at least one
	# workspace was actually returned by an endpoint - otherwise a transient API/network
	# failure across every region would wipe out .workspaces entirely.
	if (( ${#seen_ids[@]} == 0 )); then
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - WARNING: No workspaces returned by any IBM Cloud PowerVS endpoint; keeping existing workspaces as-is (no additions/removals)." "1"
	else
		local seen_json removed_keys
		seen_json=$(printf '%s\n' "${!seen_ids[@]}" | jq -R . | jq -s .)
		removed_keys=$(jq -r --argjson seen "$seen_json" '
			to_entries[] | select([.value.id] | inside($seen) | not) | .key
		' <<<"$workspaces_json")

		if [[ -n "$removed_keys" ]]; then
			while IFS= read -r key; do
				[[ -z "$key" ]] && continue
				echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - -> Workspace '$key' no longer exists in IBM Cloud; removing." "1"
				workspaces_json=$(jq --arg key "$key" 'del(.[$key])' <<<"$workspaces_json")

				# The workspace itself is gone from IBM Cloud, so any LPAR still
				# pointing at it in .systems[] is orphaned - clean those up too.
				local orphan_names
				orphan_names=$(jq -r --arg ws "$key" '.systems[]? | select(.workspace == $ws) | .name' "$CONFIG_JSON")
				if [[ -n "$orphan_names" ]]; then
					while IFS= read -r sysname; do
						[[ -z "$sysname" ]] && continue
						echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - -> Removing orphaned LPAR '$sysname' (workspace '$key' no longer exists)." "1"
					done <<<"$orphan_names"
					jq_inplace '.systems |= map(select(.workspace != $ws))' --arg ws "$key"
				fi
			done <<<"$removed_keys"
		fi
	fi

	tmp_cfg="${CONFIG_JSON}.tmp"
	jq --argjson ws "$workspaces_json" '.workspaces = $ws' "$CONFIG_JSON" > "$tmp_cfg" && mv "$tmp_cfg" "$CONFIG_JSON"
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Workspaces section updated in $CONFIG_JSON." "1"

	if (( new_found == 1 )); then
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - New workspace(s) detected - running -updlpars to populate their LPARs..." "1"
		run_updlpars_api
	else
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Final (masked) config snapshot:" "1"
		print_masked_config
	fi

	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - -updws finished." "1"
}
#### END:FUNCTION - run_updws_api ####

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

#### START: usage_X() - per-flag parameter detail (shown on argument-count error and via -h -FLAG) ####
usage_dellpar() {
	echo "  NAME:" >&2
	echo "    Logical system name to remove from .systems[] (case-insensitive)." >&2
}

usage_addlpar() {
	echo "  NAME:" >&2
	echo "    Logical system name (e.g. ibmi75m2)." >&2
	echo "  IP:" >&2
	echo "    IP address used for SSH and bluexport operations." >&2
	echo "  PVM_ID:" >&2
	echo "    PowerVS pvmInstanceID of the LPAR." >&2
	echo "  WORKSPACE_SHORT:" >&2
	echo "    Workspace key as defined under .workspaces in the JSON (e.g. WSMAD2)." >&2
	echo "  OS:" >&2
	echo "    ibmi|aix|linux|other - determines whether operations that flush ASPs" >&2
	echo "    (CHGASPACT) run for this LPAR (ibmi only)." >&2
}
#### END: usage_X() functions ####

case "$flag" in
  -h | --help)
    if [ $# -gt 2 ]; then
      echo "ERROR: Too many arguments!! Syntax: $(basename "$0") -h [-FLAG]" >&2
      exit 1
    fi
    if [ $# -eq 2 ]; then
      case "$2" in
        -dellpar) usage_dellpar ;;
        -addlpar) usage_addlpar ;;
        *)
          echo "ERROR: Unknown flag for detailed help: $2. Run $(basename "$0") -h for the full command list." >&2
          exit 1
          ;;
      esac
      exit 0
    fi
    usage
    exit 0
    ;;

  -createconfig)
    run_createconfig
    ;;

  -dellpar)
    if [[ $# -ne 2 ]]; then
      echo "ERROR: Wrong syntax." >&2
      echo "Usage: $(basename "$0") -dellpar NAME" >&2
      usage_dellpar
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
    # Now: NAME IP PVM_ID WORKSPACE_SHORT OS
    if [[ $# -ne 6 ]]; then
      echo "ERROR: Wrong syntax." >&2
      echo "Usage: $(basename "$0") -addlpar NAME IP PVM_ID WORKSPACE_SHORT OS" >&2
      echo "  OS must be one of: ibmi | aix | linux | other" >&2
      usage_addlpar
      exit 1
    fi

    # ensure_config_exists  # se quiseres obrigar a escolher o JSON aqui também

    lpar_name="$2"
    lpar_ip="$3"
    lpar_pvmid="$4"
    lpar_ws="$5"
    lpar_os=$(printf '%s' "$6" | tr '[:upper:]' '[:lower:]')

    case "$lpar_os" in
      ibmi|aix|linux|other)
        ;;
      *)
        echo "ERROR: Invalid OS '$6'. Must be one of: ibmi | aix | linux | other" >&2
        exit 1
        ;;
    esac

    # Upsert system entry (case-insensitive on .name), sem campo "lpar"
    jq_inplace '
      .systems |= (
        ( . // [] )
        | map(select((.name // "" | ascii_downcase) != ($name | ascii_downcase)))
        + [ {
              "name": $name,
              "ip": $ip,
              "pvmInstanceID": $pvmid,
              "workspace": $ws,
              "os": $os,
              "osDetail": ""
            } ]
      )
    ' \
      --arg name  "$lpar_name" \
      --arg ip    "$lpar_ip" \
      --arg pvmid "$lpar_pvmid" \
      --arg ws    "$lpar_ws" \
      --arg os    "$lpar_os"

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

  -updws)
        ensure_config_exists
        run_updws_api
        ;;

  *)
    usage
    exit 1
    ;;
esac
