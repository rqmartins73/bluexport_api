#!/bin/bash
#
# IBM Cloud PowerVS automation framework — API-driven (no IBM Cloud CLI required).
# Manages: VSI lifecycle, Capture & Export, Snapshots, Images, Volume Clones,
#          Volume Tier, Cloud Object Storage (COS), GRS (Global Replication Services),
#          and Jobs (account-wide list/detail/cancel).
#
# === General ===
# Changing secret file:         bluexport_api.sh -chscrt bluexscrt_file_name   (use full path, e.g. /home/user/bluexscrt_new.json)
# View secret file in use:      bluexport_api.sh -viewscrt
#
# Show help:                    bluexport_api.sh -h | --help | -help
# Show version:                 bluexport_api.sh -v | --version
# Detailed help per flag:       bluexport_api.sh -h -FLAG  (e.g. -h -imgimport)
#
# === Capture & Export ===
# Capture all volumes:          bluexport_api.sh -a VSI_NAME IMAGE_NAME both|image-catalog|cloud-storage hourly|daily|weekly|monthly|single
# Capture excluding volumes:    bluexport_api.sh -x EXCLUDE_NAME VSI_NAME IMAGE_NAME both|image-catalog|cloud-storage hourly|daily|weekly|monthly|single
#   Note: hourly and daily are only valid with image-catalog destination.
#   Test mode (no actual capture): use -ta instead of -a, or -tx instead of -x.
# Monitor running capture job:  bluexport_api.sh -j VSI_NAME IMAGE_NAME
#
# === Snapshots ===
# Create snapshot:              bluexport_api.sh -snapcr VSI_NAME SNAPSHOT_NAME 0|"DESCRIPTION" 0|"VOL1,VOL2,..."
#   Use 0 to omit DESCRIPTION or VOLUMES (0 for VOLUMES = all volumes).
# Update snapshot:              bluexport_api.sh -snapupd SNAPSHOT_NAME 0|NEW_SNAPSHOT_NAME 0|"DESCRIPTION"
#   Use 0 to keep the current name or description unchanged.
# Delete snapshot:              bluexport_api.sh -snapdel SNAPSHOT_NAME
# Restore snapshot:             bluexport_api.sh -snapres VSI_NAME SNAPSHOT_NAME
# List all snapshots (all WS):  bluexport_api.sh -snaplsall
# LPAR compute and licences:    bluexport_api.sh -vsidetails
#
# === Captured Images ===
# List all captured images (all workspaces):  bluexport_api.sh -imglsall
# Delete image:                               bluexport_api.sh -imgdel IMG_NAME
# Import image from COS:
#   bluexport_api.sh -imgimport IMGNAME BUCKET BUCKET_REGION WORKSPACE_TO_IMPORT IMGNAME_WS STORAGE_TYPE CURRACCOUNT|OTHERACCOUNT [HMAC_JSON_FILE]
#
#   BUCKET_REGION is the IBM COS S3 endpoint region where the source bucket exists.
#     Example: eu-es, eu-de, us-east, us-south. Do not use the PowerVS datacenter name here (e.g. mad02).
#
#   STORAGE_TYPE must be one of:
#     tier0 | tier1 | tier3 | tier5k
#
#   If OTHERACCOUNT is used:
#     You must provide a JSON file with HMAC keys in the exact format from IBM Cloud COS Service Credentials.
#
#   How to obtain HMAC keys:
#     1. Go to IBM Cloud → Cloud Object Storage
#     2. Open your COS instance
#     3. Go to "Service credentials"
#     4. Open an existing credential or create a new one
#     5. Ensure HMAC keys are enabled
#     6. Copy the JSON exactly as shown and save it locally
#
#   Required JSON structure:
#     {
#         "cos_hmac_keys": {
#             "access_key_id": "...",
#             "secret_access_key": "..."
#         }
#     }
#
# Export image to COS:
#   bluexport_api.sh -imgexport IMGNAME BUCKET BUCKET_REGION CURRACCOUNT|OTHERACCOUNT [HMAC_JSON_FILE]
#
#   BUCKET_REGION is the IBM COS S3 endpoint region where the destination bucket exists.
#   Same HMAC JSON file format as -imgimport for OTHERACCOUNT (see above, or copy
#   hmac_keys_example.json to a file outside this repository, or at minimum a
#   gitignored path, and fill in your keys - never commit real HMAC credentials).
#   Both -imgimport and -imgexport monitor their PowerVS job to completion and exit
#   non-zero on failure (including if another import/export is already running in the
#   target workspace - PowerVS only allows one at a time per workspace).
#
# Monitor an existing import/export job (re-attach without resubmitting):
#   bluexport_api.sh -ji WORKSPACE
#   bluexport_api.sh -je IMAGE_NAME
#
#   Looks up the last import/export job PowerVS has on record (via the API - no
#   local job-ID storage, works even from a different machine than the one that
#   submitted it) and monitors it to completion, exiting non-zero on failure.
#
# === Jobs (account-wide) === (1.21.0)
# List every job in every workspace:  bluexport_api.sh -jobslsall
# List every job in one workspace:    bluexport_api.sh -jobsls WORKSPACE
# Show one job's full detail:         bluexport_api.sh -jobget JOB_ID
# Cancel/delete a job:                bluexport_api.sh -jobcancel JOB_ID
#
#   JOB_ID (for -jobget/-jobcancel) is searched across every configured workspace,
#   the same lookup -imgdel/-je already use for a bare name.
#   -jobcancel refuses a job whose own status is already terminal (completed/failed -
#   nothing left to cancel) and asks for confirmation (type the Job ID back, via
#   confirm_or_abort) before sending the request.
#
# === Cloud Object Storage (COS) ===
# List buckets for all COS instances (from bluexscrt):  bluexport_api.sh -bucketslsall
# List objects from a bucket (interactive):             bluexport_api.sh -bucketlsobjs
# Delete object from a bucket (interactive):            bluexport_api.sh -bucketdelobj
# Restore archived object to COS bucket:                bluexport_api.sh -restorefromarchive BUCKET OBJECT [DAYS] [ARCHIVE_TYPE]
#   DAYS: days to make available (default 3). ARCHIVE_TYPE: Bulk|Accelerated (default Accelerated).
#
# === Volume Clones ===
# Create volume clone:
#   bluexport_api.sh -vclone REQUEST_CLONE_NAME VOLUME_BASE_NAME LPAR_NAME \
#     True|False(replication-enabled) True|False(rollback-prepare) \
#     tier0|tier1|tier3|tier5k ALL|"VOL1,VOL2,..."
# Delete volume clone:          bluexport_api.sh -vclonedel REQUEST_CLONE_NAME 0|delete_volumes
#   0=delete clone request only (keep volumes). delete_volumes=delete clone request AND cloned volumes.
# List volume clones (all WS):  bluexport_api.sh -vclonelsall
#
# === Reports ===
# Inventory report (all workspaces):    bluexport_api.sh -invreport \
#   [FORMAT] [PATH] [OLD_DAYS]
#   FORMAT:   md|csv|html|all (default md, case-insensitive).
#   PATH:     output base path, no extension (default a timestamped
#             name in the current directory).
#   OLD_DAYS: snapshot/image "old" threshold in days (default 90).
#   Read-only; never aborts on one bad workspace/group/bucket - it
#   names it and moves on. See -h -invreport for the full breakdown.
#
# === Volume Tier ===
# Change volume tier (by name):         bluexport_api.sh -vchtier VSI_NAME VOLUMES_NAME TIER_TO_CHANGE_TO
# Change volume tier (all VSI volumes): bluexport_api.sh -insvchtier VSI_NAME TIER_TO_CHANGE_TO
#
#   TIER_TO_CHANGE_TO must be one of:
#     0 | 1 | 3 | 5k
#
# === GRS (Global Replication Services) ===
# Create GRS Volume Group and onboard auxiliary volumes:         bluexport_api.sh -creategrs SOURCE_VSI TARGET_VSI VG_NAME SOURCE_VOLUMES_NAME
# Delete GRS Volume Group and auxiliary volumes:                 bluexport_api.sh -deletegrs SOURCE_VSI TARGET_VSI VG_NAME SOURCE_VOLUMES_NAME
# Failover GRS Volume Group (activate target):                   bluexport_api.sh -grsfailover SOURCE_VSI VG_NAME NO_ATTACH|ATTACH [TARGET_VSI]
# Cancel GRS failover (resync master->aux, reactivate replication):
#   bluexport_api.sh -grscancelfailover SOURCE_VSI VG_NAME NO_DETACH|DETACH TARGET_VSI
# Failback GRS Volume Group (sync aux->master, re-enable replication):
#   bluexport_api.sh -grsfailback SOURCE_VSI TARGET_VSI VG_NAME
# Reverse GRS replication direction (sync aux->master):
#   bluexport_api.sh -grsreversereplica SOURCE_VSI TARGET_VSI VG_NAME
#
#   SOURCE_VSI / TARGET_VSI:    Logical PowerVS instance names as defined in your JSON.
#   VG_NAME:                    Name for the Volume Group to create on the source workspace.
#   SOURCE_VOLUMES_NAME:        Common name/prefix to identify source VSI volumes (e.g. IBMiGRS).
#
# === VSI Operations ===
# IPL/Start VSI:                bluexport_api.sh -vsistart VSI_NAME
#      Start (IPL) a Virtual Server Instance. VSI must be in SHUTOFF status.
#
# VSI Operations:               bluexport_api.sh -vsioper VSI_NAME BOOT_MODE OPERATING_MODE
#      Set IBM i boot/operating mode for a VSI.
#      BOOT_MODE: a | b | c | d
#      OPERATING_MODE: normal | manual
#
# VSI Tasks:                    bluexport_api.sh -vsitask VSI_NAME TASK
#      Run an IBM i operation task on a VSI.
#      TASK: dston | retrydump | consoleservice | iopreset | remotedstoff |
#            remotedston | iopdump | dumprestart
#
# Monitor VSI SRC:              bluexport_api.sh -vsisrcmon VSI_NAME START|SHUTOFF
#      START   -> Monitor until status=ACTIVE and SRC=00000000
#      SHUTOFF -> Monitor until status=SHUTOFF (SRC ignored)
#      Stops after 4h by default; BLUEXPORT_SRCMON_TIMEOUT overrides (seconds).
#      A timeout is reported as a timeout, never as a failed IPL - re-run the
#      same command to resume monitoring.
#
# Attach volumes by common name: bluexport_api.sh -attachvolumes VOLUMES_COMMON_NAME VSI_NAME
#      Attach all volumes in the workspace whose name contains VOLUMES_COMMON_NAME.
#      VSI must be SHUTOFF. Volumes already attached are skipped.
# Detach ALL volumes from a VSI: bluexport_api.sh -detachvolumes VSI_NAME
#      Detach all volumes currently attached to the VSI. VSI must be SHUTOFF.
#
# === Examples ===
# Capture all volumes:           bluexport_api.sh -a vsiprd vsiprd_img image-catalog daily
# Capture excluding ASP2_:       bluexport_api.sh -x ASP2_ vsiprd vsiprd_img both monthly
# Capture excluding ASP2_ & iASPname:
#                                bluexport_api.sh -x "ASP2_ iASPname" vsiprd vsiprd_img both monthly
#
# Test mode (no capture):        bluexport_api.sh -ta vsiprd vsiprd_img image-catalog daily
# Test mode (no capture):        bluexport_api.sh -tx ASP2_ vsiprd vsiprd_img both single
#
# Note: Recurrence "hourly" and "daily" only permits captures to image-catalog.
#
# Ricardo Martins - IBM Champion 2025|2026
# Blue Chip Portugal - 2025-2026
##########################################################################################
# Ensure required tools are in PATH (IBM i + Linux safe)
PATH="/QOpenSys/pkgs/bin:/QOpenSys/usr/bin:/usr/bin:${PATH}"
export PATH

       #####  START:CODE  #####

Version=1.23.0

conf_file="$HOME/bluexport_api_conf.json"

if [[ $1 == "-v" ]] || [[ $1 == "--version" ]]
then
	if [ $# -gt 1 ]
	then
		echo "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport_api.sh -v | --version"
		exit 0
	fi
echo
jq -M -n --arg version "$Version" '{tool:"bluexport_api.sh", version:$version, author:"Ricardo Martins", company:"Blue Chip Portugal", license:"MIT", maintained:"2025-2026"}'
echo "`date +%Y-%m-%d_%H:%M:%S`"
echo
exit 0
fi

if [ ! -f $conf_file ]
then
	echo
	echo "Flags Used: $@"
	echo "`date +%Y-%m-%d_%H:%M:%S` - Config file $conf_file Missing!! Aborting!..."
	echo
	exit 0
fi

log_file=$(jq -r '.log_file' "$conf_file")
bluexscrt=$(jq -r '.bluexscrt' "$conf_file")
end_log_file='==== END ========= $timestamp ========='

#### START:FUNCTION - Echo to log file and screen  ####
echoscreen() {
    msg="$1"
    flag="$2"

    # Quebra linhas a cada 377 colunas
    wrapped=$(printf '%s\n' "$msg" | fold -w 377 -s)

    # Interactive (TTY) OR forced (IBM i batch)
    if [ -t 1 ] || [[ "${ECHOSCREEN_FORCE_STDOUT:-0}" == "1" ]]; then
        printf '%s\n' "$wrapped"
    fi

    if [[ "$flag" == "1" ]]; then
        printf '%s\n' "$wrapped" >> "$log_file"
    fi
}
#### END:FUNCTION - Echo to log file and screen  ####

#### START:FUNCTION - Spinner while waiting on a poll interval  ####
# $1 = seconds to wait, $2 = optional label shown next to the spinner.
# Interactive terminal only: on a non-tty (batch job, redirected output,
# IBM i submitted job) this is a plain sleep, so no control characters ever
# end up in logs or spool files.
spin_wait() {
    local secs="$1" label="${2:-}" i=0
    local spin_chars='/-\|'
    if [[ ! -t 1 ]]
    then
        sleep "$secs"
        return
    fi
    while [[ $i -lt $secs ]]
    do
        printf '\r  %s %s (%ss)   ' "${spin_chars:$((i % 4)):1}" "$label" "$((secs - i))"
        sleep 1
        i=$((i + 1))
    done
    printf '\r%*s\r' 100 ""
}
#### END:FUNCTION - Spinner while waiting on a poll interval  ####

#### START:FUNCTION - Finish vsi_status=$(log file when aborting  ####
abort() {
        echo "$1" >> "$log_file"
        if [ -t 1 ]
        then
                echo ""
                echo "   ### $1"
                echo ""
        fi
        timestamp=$(date +%F" "%T" "%Z)
        eval echo $end_log_file >> $log_file
        exit "${2:-0}"
}
#### END:FUNCTION - Finish log file when aborting  ####

#### START:FUNCTION - Confirm a destructive action interactively  ####
# confirm_or_abort "<what will happen>" "<name to type>"
# (1.19.0) -vclone, -vclonedel, -vchtier and -insvchtier act on live volumes/VSIs with
# no way back; ask an interactive operator to type the name back before proceeding.
# When stdin/stdout are not both a terminal (IBM i batch, cron, pipes) or
# BLUEXPORT_ASSUME_YES=1, confirmation is skipped - one log line says so - so existing
# automation keeps working unchanged. A typed name that does not match aborts.
confirm_or_abort() {
	local what="$1" name="$2" typed
	if [ "$BLUEXPORT_ASSUME_YES" = "1" ] || ! [ -t 0 ] || ! [ -t 1 ]
	then
		echo "$(date +%Y-%m-%d_%H:%M:%S) - INFO - Confirmation skipped (non-interactive, or BLUEXPORT_ASSUME_YES=1): $what" >> "$log_file"
		return 0
	fi
	echoscreen ""
	echoscreen "   ### $what"
	echoscreen "   ### Type the name below exactly to continue, anything else cancels: $name"
	printf "   ### > " > /dev/tty
	read -r typed < /dev/tty
	if [[ "$typed" != "$name" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Confirmation did not match (expected '$name'); cancelled." 1
	fi
}
#### END:FUNCTION - Confirm a destructive action interactively  ####

if [[ $1 != "-chscrt" ]] && [[ $1 != "-viewscrt" ]] && [[ $1 != "-h" ]] && [[ $1 != "--help" ]] && [[ $1 != "-help" ]] && [[ $1 != "" ]]
then
	####  START: Check if Config File exists  ####
	if [ ! -f $bluexscrt ]
	then
		echoscreen ""
		timestamp=$(date +%F" "%T" "%Z)
		echo "==== START ======= $timestamp =========" >> $log_file
		echo "Flags Used: $@" >> $log_file
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Secrets file $bluexscrt Missing!! Aborting!..." "1"
		echo "==== END ========= $timestamp =========" >> $log_file
		echoscreen ""
		exit 0
	fi
	####  END: Check if Config File exists  ####

	echo
	echoscreen "   ### Building environment..."

	####  START: Constants Definition  #####
	capture_time=`date +%Y-%m-%d_%H%M`
	capture_date=`date +%Y-%m-%d`
	capture_hour=`date "+%H"`
	# (1.18.3): whether old_img is a bare hour rather than a full %Y-%m-%d date.
	# delete_previous_img anchors the comparison when it is; see there for why.
	old_is_hour=0
	flagj=0
	job_log=$(jq -r '.job_log' "$conf_file")
	job_test_log=$(jq -r '.job_test_log' "$conf_file")
	job_id_file=$(jq -r '.job_id' "$conf_file")
	job_log_short=$(jq -r '.job_log_short' "$conf_file")
	job_monitor=$(jq -r '.job_monitor' "$conf_file")
	operid_file=$(jq -r '.operid_file' "$conf_file")
	vsi_list_id_tmp=$(jq -r '.vsi_list_id_tmp' "$conf_file")
	vsi_list_tmp=$(jq -r '.vsi_list_tmp' "$conf_file")
	volumes_file=$(jq -r '.volumes_file' "$conf_file")
	vol_ch_tier=$(jq -r '.vol_ch_tier' "$conf_file")
	vol_failed_tst=$(jq -r '.vol_failed_tst' "$conf_file")
	snap_retention=$(jq -r '.snap_retention' "$conf_file")
	iasp_names_file=$(jq -r '.iasp_names_file' "$conf_file")
	single=0
	flags="$@"
	####  END: Constants Definition  #####

	####  START: Get Cloud Config Data  #####

	#############################
	#  START: Load Base Config  #
	#############################

	# SSH / VSI user information
	vsi_user=$(jq -r '.ssh.user'          "$bluexscrt")
	sshkeypath=$(jq -r '.ssh.keyPath'     "$bluexscrt")

	# PowerVS Resource Group
	resource_grp=$(jq -r '.resourceGroup' "$bluexscrt")

	# IBM Cloud Object Storage access keys
	accesskey=$(jq -r '.access.accessKey'     "$bluexscrt")
	secretkey=$(jq -r '.access.secretKey'     "$bluexscrt")
	bucket=$(jq -r '.access.bucketName'       "$bluexscrt")
	region=$(jq -r '.access.region'           "$bluexscrt")

	# IBM Cloud API key
	api_key=$(jq -r '.apikey' "$bluexscrt")


	###########################################
	#  START: Workspace Mapping (ALLWS, Names) #
	###########################################

	# Equivalent of ALLWS — list of workspace keys (e.g., "WSFRA1 WSFRA2 WSMAD2 WSMAD4")
	allws=$(jq -r '.workspaces | keys | join(" ")' "$bluexscrt")

	# Equivalent of WSNAMES — all workspace display names separated by ":" and ending with ":"
	wsnames=$(jq -r '.workspaces | to_entries | map(.value.name) | join(":") + ":"' "$bluexscrt")

	# Dynamically create environment variables for each workspace:
	#   WSFRA1     = workspace CRN
	#   WSFRA1ID   = workspace ID
	#   WSFRA1NAME = workspace display name
	for ws in $allws; do
	    crn=$(jq -r --arg ws "$ws" '.workspaces[$ws].crn'  "$bluexscrt")
	    id=$(jq -r  --arg ws "$ws" '.workspaces[$ws].id'   "$bluexscrt")
	    name=$(jq -r --arg ws "$ws" '.workspaces[$ws].name' "$bluexscrt")

	    # Variable containing the CRN (matches original behavior)
	    declare "${ws}=$crn"

	    # Additional helpful variables
	    declare "${ws}ID=$id"
	    declare "${ws}NAME=$name"
	done

	#########################################
	#  END: Workspace Mapping               #
	#########################################

	# Optional debugging
	#echo "vsi_user       = $vsi_user"
	#echo "sshkeypath     = $sshkeypath"
	#echo "resource_grp   = $resource_grp"
	#echo "accesskey      = $accesskey"
	#echo "secretkey      = $secretkey"
	#echo "bucket         = $bucket"
	#echo "region         = $region"
	#echo "api_key        = $api_key"
	#echo "allws          = $allws"
	#echo "wsnames        = $wsnames"
	#echo "WSFRA1         = $WSFRA1"
	#echo "WSFRA1ID       = $WSFRA1ID"
	#echo "WSFRA1NAME     = $WSFRA1NAME"
	#echo "WSFRA2         = $WSFRA2"
	#echo "WSFRA2ID       = $WSFRA2ID"
	#echo "WSFRA2NAME     = $WSFRA2NAME"
	#exit 0

	#### START: API Environment ###
	#  authentication
	header_json="Content-Type: application/json"
	header_accept="Accept: application/json"
	header_xml="Content-Type: application/xml"

	####  START:FUNCTION - Get/Refresh IAM Token  ####
	# IBM Cloud IAM access tokens expire after ~3600s. Long-running operations
	# (e.g. capture & export job monitoring) can outlive that TTL, so this is
	# called again mid-run (see job_monitor) to keep header_auth valid.
	# Pass "refresh" to return 1 on failure instead of aborting the script.
	get_iam_token() {
		local mode="$1" resp token
		echoscreen "   ### Retrieving IAM Token..."
		resp=""
		if ! resp=$(curl -sS --connect-timeout 30 --max-time 60 -X POST "https://iam.cloud.ibm.com/identity/token" -H "Content-Type: application/x-www-form-urlencoded" -H "$header_accept" -d "grant_type=urn:ibm:params:oauth:grant-type:apikey&apikey=${api_key}"  2>&1)
		then
			if [[ "$mode" == "refresh" ]]
			then
				echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - WARNING - Could not reach iam.cloud.ibm.com while refreshing IAM token, will retry. Response: $resp" "1"
				return 1
			fi
			timestamp=$(date +%F" "%T" "%Z)
			echoscreen "==== START ======= $timestamp =========" "1"
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - $resp" "1"
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - No internet connectivity (cannot reach iam.cloud.ibm.com). Check PVS egress / proxy / routing." 1
		fi
		token=$(printf '%s\n' "$resp" | jq -r '.access_token')
		if [[ -z "$token" || "$token" == "null" ]]
		then
			if [[ "$mode" == "refresh" ]]
			then
				echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - WARNING - IAM token refresh response did not contain access_token, will retry. Raw response: $resp" "1"
				return 1
			fi
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - IAM token response did not contain access_token. Raw response: $resp" 1
		fi
		iam_token="$token"
		header_auth="Authorization: Bearer $iam_token"
		iam_token_epoch=$(date +%s)
		# (1.19.0) Refresh at 75% of the token's own expires_in instead of a hardcoded
		# 2700s guess, so a shorter- or longer-lived token still gets refreshed before
		# it expires. Falls back to 2700 when expires_in is absent, non-numeric, or too
		# small (<120s) to be a sane token TTL.
		local expires_in
		expires_in=$(printf '%s\n' "$resp" | jq -r '.expires_in // empty')
		if [[ "$expires_in" =~ ^[0-9]+$ ]] && [ "$expires_in" -ge 120 ]
		then
			iam_refresh_secs=$(( expires_in * 75 / 100 ))
		else
			iam_refresh_secs=2700
		fi
		echoscreen "   ### IAM Token successfully retrieved!"
		return 0
	}
	####  END:FUNCTION - Get/Refresh IAM Token  ####

	echo
	get_iam_token

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
	echoscreen ""
	echoscreen "   ### Logging at $log_file" ""
	echoscreen ""
fi
       #####  START: FUNCTIONS  #####

#### START:FUNCTION - Help  ####
help() {
	echoscreen ""
	echoscreen "IBM Cloud PowerVS automation framework — API-driven (no IBM Cloud CLI required)."
	echoscreen "Manages: VSI lifecycle, Capture & Export, Snapshots, Images, Volume Clones,"
	echoscreen "         Volume Tier, Cloud Object Storage (COS), GRS, and Jobs."
	echoscreen "Version: $Version"
	echoscreen ""
	echoscreen "=== General ==="
	echoscreen "Changing secret file:       bluexport_api.sh -chscrt bluexscrt_file_name   (use full path, e.g. /home/user/bluexscrt_new.json)  (will also ask/update log file path)"
	echoscreen "View secret file in use:    bluexport_api.sh -viewscrt"
	echoscreen ""
	echoscreen "Show help:                  bluexport_api.sh -h | --help | -help"
	echoscreen "Show version:               bluexport_api.sh -v | --version"
	echoscreen "Detailed help per flag:     bluexport_api.sh -h -FLAG   (e.g. -h -imgimport)"
	echoscreen ""
	echoscreen "=== Capture & Export ==="
	echoscreen "Capture all volumes:          bluexport_api.sh -a VSI_NAME IMAGE_NAME both|image-catalog|cloud-storage hourly|daily|weekly|monthly|single"
	echoscreen "Capture excluding volumes:    bluexport_api.sh -x EXCLUDE_NAME VSI_NAME IMAGE_NAME both|image-catalog|cloud-storage hourly|daily|weekly|monthly|single"
	echoscreen "  Note: hourly and daily are only valid with image-catalog destination."
	echoscreen "  Test mode (no actual capture): use -ta instead of -a, or -tx instead of -x."
	echoscreen "Monitor running capture job:  bluexport_api.sh -j VSI_NAME IMAGE_NAME"
	echoscreen ""
	echoscreen "=== Snapshots ==="
	echoscreen "Create snapshot:            bluexport_api.sh -snapcr VSI_NAME SNAPSHOT_NAME 0|\"DESCRIPTION\" 0|\"VOL1,VOL2,...\""
	echoscreen "  Use 0 to omit DESCRIPTION or VOLUMES (0 = all volumes)."
	echoscreen "Update snapshot:            bluexport_api.sh -snapupd SNAPSHOT_NAME 0|NEW_SNAPSHOT_NAME 0|\"DESCRIPTION\""
	echoscreen "  Use 0 to keep current name or description unchanged."
	echoscreen "Delete snapshot:            bluexport_api.sh -snapdel SNAPSHOT_NAME"
	echoscreen "Restore snapshot:           bluexport_api.sh -snapres VSI_NAME SNAPSHOT_NAME"
	echoscreen "List all snapshots(all WS): bluexport_api.sh -snaplsall"
	echoscreen "LPAR compute and licences:  bluexport_api.sh -vsidetails"
	echoscreen ""
	echoscreen "=== Captured Images ==="
	echoscreen "List all captured images (all workspaces): bluexport_api.sh -imglsall"
	echoscreen "Delete image:               bluexport_api.sh -imgdel IMG_NAME"
	echoscreen "Import image from COS:"
	echoscreen "  bluexport_api.sh -imgimport IMGNAME BUCKET BUCKET_REGION WORKSPACE IMGNAME_WS STORAGE_TYPE CURRACCOUNT|OTHERACCOUNT [HMAC_JSON_FILE]"
	echoscreen ""
	echoscreen "  BUCKET_REGION:"
	echoscreen "    IBM COS S3 endpoint region where the source bucket exists."
	echoscreen "    Examples: eu-es, eu-de, us-east, us-south."
	echoscreen "    Do not use the PowerVS datacenter name here (e.g. mad02)."
	echoscreen ""
	echoscreen "  STORAGE_TYPE:"
	echoscreen "    tier0 | tier1 | tier3 | tier5k"
	echoscreen ""
	echoscreen "  OTHERACCOUNT:"
	echoscreen "    Requires HMAC JSON file from IBM Cloud COS Service Credentials."
	echoscreen ""
	echoscreen "  To get HMAC keys:"
	echoscreen "    IBM Cloud → COS → Service credentials → open/create → copy JSON"
	echoscreen ""
	echoscreen "  JSON must contain:"
	echoscreen "    .cos_hmac_keys.access_key_id"
	echoscreen "    .cos_hmac_keys.secret_access_key"
	echoscreen ""
	echoscreen "Export image to COS:"
	echoscreen "  bluexport_api.sh -imgexport IMGNAME BUCKET BUCKET_REGION CURRACCOUNT|OTHERACCOUNT [HMAC_JSON_FILE]"
	echoscreen ""
	echoscreen "  BUCKET_REGION:"
	echoscreen "    IBM COS S3 endpoint region where the destination bucket exists."
	echoscreen "    Examples: eu-es, eu-de, us-east, us-south."
	echoscreen ""
	echoscreen "  OTHERACCOUNT:"
	echoscreen "    Same HMAC JSON file format as -imgimport - copy hmac_keys_example.json"
	echoscreen "    to a file outside this repository (or at minimum a gitignored path)"
	echoscreen "    and fill in your keys. Never commit real HMAC credentials."
	echoscreen ""
	echoscreen "  Both -imgimport and -imgexport monitor the PowerVS job to completion and"
	echoscreen "  exit non-zero on failure, including if another import/export operation is"
	echoscreen "  already running in the target workspace."
	echoscreen ""
	echoscreen "Monitor an existing import/export job:"
	echoscreen "  bluexport_api.sh -ji WORKSPACE"
	echoscreen "  bluexport_api.sh -je IMAGE_NAME"
	echoscreen ""
	echoscreen "  Re-attaches monitoring to the last import/export job PowerVS has on"
	echoscreen "  record, without resubmitting anything - useful after a lost SSH"
	echoscreen "  session or a job submitted from a different machine. No job ID is"
	echoscreen "  stored locally; every call asks PowerVS directly."
	echoscreen ""
	echoscreen "=== Jobs (account-wide) ==="
	echoscreen "List every job in every workspace: bluexport_api.sh -jobslsall"
	echoscreen "List every job in one workspace:   bluexport_api.sh -jobsls WORKSPACE"
	echoscreen "Show one job's full detail:        bluexport_api.sh -jobget JOB_ID"
	echoscreen "Cancel/delete a job:               bluexport_api.sh -jobcancel JOB_ID"
	echoscreen ""
	echoscreen "  JOB_ID (for -jobget/-jobcancel) is searched across every configured"
	echoscreen "  workspace, the same lookup -imgdel/-je use for a bare name."
	echoscreen "  -jobcancel refuses a job whose own status is already completed or failed"
	echoscreen "  (nothing left to cancel) and asks for typed confirmation before sending"
	echoscreen "  the request, the same as -vclone/-vclonedel/-vchtier/-insvchtier."
	echoscreen ""
	echoscreen "=== Cloud Object Storage (COS) ==="
	echoscreen "List buckets for all COS instances: bluexport_api.sh -bucketslsall"
	echoscreen "List objects from a bucket:         bluexport_api.sh -bucketlsobjs         (interactive - guided selection)"
	echoscreen "Delete object from a bucket:        bluexport_api.sh -bucketdelobj         (interactive - guided selection)"
	echoscreen "Restore archived object:            bluexport_api.sh -restorefromarchive BUCKET OBJECT [DAYS] [ARCHIVE_TYPE]"
	echoscreen "  DAYS:         Number of days to make the object available. Default: 3."
	echoscreen "  ARCHIVE_TYPE: Restore tier. Default: Accelerated. Options: Bulk | Accelerated."
	echoscreen ""
	echoscreen "=== Volume Clones ==="
	echoscreen "Create volume clone:"
	echoscreen "  bluexport_api.sh -vclone REQUEST_CLONE_NAME VOLUME_BASE_NAME LPAR_NAME \\"
	echoscreen "    True|False(replication-enabled) True|False(rollback-prepare) \\"
	echoscreen "    tier0|tier1|tier3|tier5k ALL|\"VOL1,VOL2,...\""
	echoscreen "Delete volume clone:        bluexport_api.sh -vclonedel REQUEST_CLONE_NAME 0|delete_volumes"
	echoscreen "  0              = delete the clone request only (keep cloned volumes)"
	echoscreen "  delete_volumes = delete the clone request AND the cloned volumes"
	echoscreen "List volume clones(all WS): bluexport_api.sh -vclonelsall"
	echoscreen ""
	echoscreen "=== Volume Tier ==="
	echoscreen "Change volume tier (by name):         bluexport_api.sh -vchtier VSI_NAME VOLUMES_NAME TIER_TO_CHANGE_TO"
	echoscreen "Change volume tier (all VSI volumes): bluexport_api.sh -insvchtier VSI_NAME TIER_TO_CHANGE_TO"
	echoscreen ""
	echoscreen "  TIER_TO_CHANGE_TO:"
	echoscreen "    0 | 1 | 3 | 5k"
	echoscreen ""
	echoscreen "=== GRS (Global Replication Services) ==="
	echoscreen "Create GRS Volume Group and onboard auxiliary volumes:"
	echoscreen "  bluexport_api.sh -creategrs SOURCE_VSI TARGET_VSI VG_NAME SOURCE_VOLUMES_NAME"
	echoscreen "Delete GRS Volume Group and auxiliary volumes:"
	echoscreen "  bluexport_api.sh -deletegrs SOURCE_VSI TARGET_VSI VG_NAME SOURCE_VOLUMES_NAME"
	echoscreen "Failover GRS Volume Group (activate target):"
	echoscreen "  bluexport_api.sh -grsfailover SOURCE_VSI VG_NAME NO_ATTACH|ATTACH [TARGET_VSI]"
	echoscreen "Cancel GRS failover (resync master->aux, reactivate replication):"
	echoscreen "  bluexport_api.sh -grscancelfailover SOURCE_VSI VG_NAME NO_DETACH|DETACH TARGET_VSI"
	echoscreen "Failback GRS Volume Group (sync aux->master, re-enable replication):"
	echoscreen "  bluexport_api.sh -grsfailback SOURCE_VSI TARGET_VSI VG_NAME"
	echoscreen "Reverse GRS replication direction (sync aux->master):"
	echoscreen "  bluexport_api.sh -grsreversereplica SOURCE_VSI TARGET_VSI VG_NAME"
	echoscreen ""
	echoscreen "  SOURCE_VSI / TARGET_VSI:    Logical PowerVS instance names as defined in your JSON."
	echoscreen "  VG_NAME:                    Name for the Volume Group to create on the source workspace."
	echoscreen "  SOURCE_VOLUMES_NAME:        Common name/prefix to identify source VSI volumes (e.g. IBMiGRS)."
	echoscreen ""
	echoscreen "=== VSI Operations ==="
	echoscreen "IPL/Start VSI:              bluexport_api.sh -vsistart VSI_NAME"
	echoscreen "      Start (IPL) a Virtual Server Instance. VSI must be in SHUTOFF status."
	echoscreen ""
	echoscreen "VSI Operations:             bluexport_api.sh -vsioper VSI_NAME BOOT_MODE OPERATING_MODE"
	echoscreen "      Set IBM i boot/operating mode for a VSI."
	echoscreen "      BOOT_MODE: a | b | c | d"
	echoscreen "      OPERATING_MODE: normal | manual"
	echoscreen ""
	echoscreen "VSI Tasks:                  bluexport_api.sh -vsitask VSI_NAME TASK"
	echoscreen "      Run an IBM i operation task on a VSI."
	echoscreen "      TASK: dston | retrydump | consoleservice | iopreset | remotedstoff |"
	echoscreen "            remotedston | iopdump | dumprestart"
	echoscreen ""
	echoscreen "Monitor VSI SRC:            bluexport_api.sh -vsisrcmon VSI_NAME START|SHUTOFF"
	echoscreen "      START   -> Monitor until VSI reaches ACTIVE and SRC 00000000"
	echoscreen "      SHUTOFF -> Monitor until VSI reaches SHUTOFF (SRC ignored)"
	echoscreen ""
	echoscreen "Attach volumes by common name: bluexport_api.sh -attachvolumes VOLUMES_COMMON_NAME VSI_NAME"
	echoscreen "      Attach all volumes in the workspace whose name contains VOLUMES_COMMON_NAME."
	echoscreen "      VSI must be SHUTOFF. Volumes already attached are skipped."
	echoscreen ""
	echoscreen "Detach ALL volumes from a VSI: bluexport_api.sh -detachvolumes VSI_NAME"
	echoscreen "      Detach all volumes currently attached to the VSI. VSI must be SHUTOFF."
	echoscreen ""
	echoscreen "=== Reports ==="
	echoscreen "Inventory report (all workspaces): bluexport_api.sh -invreport"
	echoscreen "  [FORMAT] [PATH] [OLD_DAYS]"
	echoscreen "  FORMAT: md|csv|html|all (default md). Read-only; never"
	echoscreen "  aborts on one bad workspace/group/bucket - see -h -invreport"
	echoscreen ""
	echoscreen "=== Examples ==="
	echoscreen "Capture all volumes:        bluexport_api.sh -a vsiprd vsiprd_img image-catalog daily"
	echoscreen "Capture excluding ASP2_:    bluexport_api.sh -x ASP2_ vsiprd vsiprd_img both monthly"
	echoscreen "Capture excluding ASP2_ & iASPname:"
	echoscreen '                            bluexport_api.sh -x "ASP2_ iASPname" vsiprd vsiprd_img both monthly'
	echoscreen ""
	echoscreen "Test mode (no capture):     bluexport_api.sh -ta vsiprd vsiprd_img image-catalog daily"
	echoscreen "Test mode (no capture):     bluexport_api.sh -tx ASP2_ vsiprd vsiprd_img both single"
	echoscreen ""
	echoscreen "Note: Recurrence \"hourly\" and \"daily\" only permits captures to image-catalog."
	echoscreen ""
	echoscreen "Ricardo Martins - IBM Champion 2025|2026"
	echoscreen "Blue Chip Portugal - 2025-2026"
	echoscreen ""
}
#### END:FUNCTION - Help  ####

#### START:FUNCTIONS - API Commands ####
##  Workspace management aliases
ws_ls() {
	curl -sX GET "$base_url/v1/workspaces" -H "$header_auth" -H "$header_json"
}

## Instance (VSI) management functions
ins_get() {
	curl -sX GET "$base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/pvm-instances/$PVM_ID" -H "$header_auth" -H "CRN: $CRN" -H "$header_json"
}

ins_get_code() {
	# Same request as ins_get(), but appends the HTTP status code as the last
	# line - the identical trick job_get() uses, and for the identical reason:
	# without it a caller cannot tell "the API says the LPAR is in state X"
	# apart from "the API refused to answer". An expired IAM token returns an
	# error body with no .status field, and `jq -r '.status // "UNKNOWN"'`
	# renders that as the literal string UNKNOWN - indistinguishable from a
	# real LPAR state. That is how a monitor outliving its token came to
	# report a perfectly healthy IPL as an LPAR that was not starting.
	#
	# Deliberately a SEPARATE function rather than a change to ins_get(): that
	# one has nine other callers which parse a bare JSON body, and appending a
	# trailing line would break every one of them.
	#
	# Caller must split the code back out (see do_vsi_srcmon) - this runs via
	# command substitution, so it cannot hand it back in a global.
	curl -sS --connect-timeout 30 --max-time 60 -w '\n%{http_code}' -X GET "$base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/pvm-instances/$PVM_ID" -H "$header_auth" -H "CRN: $CRN" -H "$header_json" 2>>"$log_file"
}

ins_vol_ls() {
	curl -sX GET "$base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/pvm-instances/$PVM_ID/volumes" -H "$header_auth" -H "CRN: $CRN" -H "$header_json"
}

ins_vol_bdet() {
	curl -sX DELETE "$base_url/pcloud/v2/cloud-instances/$CLOUD_INSTANCE_ID/pvm-instances/$PVM_ID/volumes" -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -d "{$ACTIONS}"
}

# (1.20.0) Same request as ins_vol_bdet(), with the HTTP status appended as the last line,
# used at the GRS delete/cancel-failover call sites (see grs_check_write). Other callers of
# ins_vol_bdet() are unchanged.
ins_vol_bdet_status() {
	curl -sX DELETE "$base_url/pcloud/v2/cloud-instances/$CLOUD_INSTANCE_ID/pvm-instances/$PVM_ID/volumes" -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -d "{$ACTIONS}" -w '\n%{http_code}'
}

ins_ls() {
	curl -sX GET "$base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/pvm-instances" -H "$header_auth" -H "CRN: $CRN" -H "$header_json"
}

ins_act() {
	curl -sX POST "$base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/pvm-instances/$PVM_ID/action" -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -d "{$ACTIONS}"
}

ins_cap() {
	# Appends the HTTP status code as a trailing line (see job_get for why
	# this can't be handed back via a global var: command substitution runs
	# this in a subshell). Callers must check it - the API returns a normal
	# JSON error body (no "id" field) when e.g. a capture is already running,
	# and jq would otherwise silently render that as the literal text "null".
	curl -sS --connect-timeout 30 --max-time 60 -w '\n%{http_code}' -X POST "$base_url/pcloud/v2/cloud-instances/$CLOUD_INSTANCE_ID/pvm-instances/$PVM_ID/capture" -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -d "{$ACTIONS}" 2>>"$log_file"
}

# Splits an ins_cap() response (body + trailing HTTP-code line), logs the
# body, and sets $job_id. Returns 1 (and leaves job_id empty) on any failure
# - non-2xx status, or a body with no real "id" field - instead of letting a
# missing id silently become the literal string "null". Never calls abort
# itself: this is invoked directly (not via command substitution) so the
# caller can abort in its own process.
parse_cap_response() {
	local raw="$1" body code api_msg
	code="${raw##*$'\n'}"
	body="${raw%$'\n'*}"
	printf '%s\n' "$body" | tee -a "$log_file" "$job_id_file" >/dev/null
	job_id=$(printf '%s' "$body" | jq -r '.id // empty' 2>>"$log_file")
	if [[ -z "$job_id" || "$code" != 2* ]]; then
		api_msg=$(printf '%s' "$body" | jq -r '.message // .error // .description // .errors[0].message // empty' 2>/dev/null)
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - FAILED to start capture (HTTP ${code:-?}): ${api_msg:-$body}" "1"
		job_id=""
		return 1
	fi
	return 0
}

ins_oper() {
	curl -sX POST $base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/pvm-instances/$PVM_ID/operations -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -d "{$ACTIONS}"
}
## Volume management
vol_ls() {
	curl -sX GET "$base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/volumes" -H "$header_auth" -H "CRN: $CRN" -H "$header_json"
}

vol_get() {
	curl -sX GET "$base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/pvm-instances/$PVM_ID/volumes/$VOL_ID" -H "$header_auth" -H "CRN: $CRN" -H "$header_json"
}

# (1.19.2) Workspace-level volume read. vol_get only answers for a volume attached to
# PVM_ID, so it cannot read a volume that was just detached.
vol_ws_get() {
	curl -sX GET "$base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/volumes/$VOL_ID" -H "$header_auth" -H "CRN: $CRN" -H "$header_json"
}

vol_act() {
	curl -sX POST "$base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/volumes/$VOL_ID/action" -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -d "{$ACTIONS}"
}

# (1.19.0) Same request as vol_act(), with the HTTP status appended as the last line
# (curl -w), so a caller can tell success from failure without inferring it from the
# body. A separate function, not a change to vol_act() itself, because vol_act() has
# other callers that pipe its plain body straight to tee.
vol_act_status() {
	curl -sX POST "$base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/volumes/$VOL_ID/action" -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -d "{$ACTIONS}" -w '\n%{http_code}'
}

vol_att() {
	curl -sX POST "$base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/pvm-instances/$PVM_ID/volumes/$VOL_ID" -H "$header_auth" -H "CRN: $CRN" -H "$header_json"
}

vol_att_multi() {
	curl -sX POST "$base_url/pcloud/v2/cloud-instances/$CLOUD_INSTANCE_ID/pvm-instances/$PVM_ID/volumes" -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -d "{$ACTIONS}"
}

# (1.20.0) Same request as vol_att_multi(), with the HTTP status appended as the last line,
# used at the GRS failover ATTACH call sites (see grs_check_write). Other callers of
# vol_att_multi() are unchanged.
vol_att_multi_status() {
	curl -sX POST "$base_url/pcloud/v2/cloud-instances/$CLOUD_INSTANCE_ID/pvm-instances/$PVM_ID/volumes" -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -d "{$ACTIONS}" -w '\n%{http_code}'
}

vol_del() {
	curl -sX DELETE "$base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/volumes/$VOL_ID" -H "$header_auth" -H "CRN: $CRN" -H "$header_json"
}

vol_bdel() {
	curl -sX DELETE "$base_url/pcloud/v2/cloud-instances/$CLOUD_INSTANCE_ID/volumes" -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -d "{$ACTIONS}"
}

# (1.20.0) Same request as vol_bdel(), with the HTTP status appended as the last line, used
# at the GRS delete call site (see grs_check_write). Other callers of vol_bdel() are
# unchanged.
vol_bdel_status() {
	curl -sX DELETE "$base_url/pcloud/v2/cloud-instances/$CLOUD_INSTANCE_ID/volumes" -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -d "{$ACTIONS}" -w '\n%{http_code}'
}

vol_rcr() {
	curl -sX GET $base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/volumes/$VOL_ID/remote-copy -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -d "{$ACTIONS}"
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
	# (1.18.8) HTTP status appended as the last line, read by delete_check.
	curl -sX DELETE "$base_url/pcloud/v2/cloud-instances/$CLOUD_INSTANCE_ID/volumes-clone/$VOL_CLONE_ID" -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -w '\n%{http_code}'
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

# (1.20.0) Same request as vg_cr(), with the HTTP status appended as the last line, used at
# the GRS create call site (see grs_check_write).
vg_cr_status() {
	curl -sX POST "$base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/volume-groups" -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -d "{$ACTIONS}" -w '\n%{http_code}'
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

# (1.20.0) Same request as vg_act(), with the HTTP status appended as the last line, used at
# the GRS failover/cancel-failover/failback/reverse-replica call sites (see grs_check_write).
vg_act_status() {
	curl -sX POST "$base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/volume-groups/$VOLUME_GROUP_ID/action" -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -d "{$ACTIONS}" -w '\n%{http_code}'
}

vg_del() {
	curl -sX DELETE "$base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/volume-groups/$VOLUME_GROUP_ID" -H "$header_auth" -H "CRN: $CRN" -H "$header_json"
}

# (1.20.0) Same request as vg_del(), with the HTTP status appended as the last line, used at
# the GRS delete call site (see grs_check_write).
vg_del_status() {
	curl -sX DELETE "$base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/volume-groups/$VOLUME_GROUP_ID" -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -w '\n%{http_code}'
}

vg_upd() {
	curl -sX PUT "$base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/volume-groups/$VOLUME_GROUP_ID" -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -d "{$ACTIONS}"
}

# (1.20.0) Same request as vg_upd(), with the HTTP status appended as the last line, used at
# the GRS delete call sites (see grs_check_write).
vg_upd_status() {
	curl -sX PUT "$base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/volume-groups/$VOLUME_GROUP_ID" -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -d "{$ACTIONS}" -w '\n%{http_code}'
}


## Auxiliary volume onboarding
on_ls() {
	curl -sX GET "$base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/volumes/onboarding" -H "$header_auth" -H "CRN: $CRN" -H "$header_json"
}

on_cr() {
	curl -sX POST "$base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/volumes/onboarding" -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -d "{$ACTIONS}"
}

# (1.20.0) Same request as on_cr(), with the HTTP status appended as the last line, used at
# the GRS create call site (see grs_check_write).
on_cr_status() {
	curl -sX POST "$base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/volumes/onboarding" -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -d "{$ACTIONS}" -w '\n%{http_code}'
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
	# Appends the HTTP status code as the last line so callers can tell a
	# transient/auth failure (e.g. expired IAM token) apart from a real
	# "job not found". Caller must split it back out (see job_monitor) -
	# this runs via command substitution, so it cannot hand back a status
	# via a global variable.
	# (1.19.0) $1, when given, is a file path to receive the response headers
	# (curl -D) so a caller can read Retry-After on a 429 without a second call.
	local hdr_file="${1:-/dev/null}"
	curl -sS --connect-timeout 30 --max-time 60 -D "$hdr_file" -w '\n%{http_code}' -X GET $base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/jobs/$JOB_ID -H "$header_auth" -H "CRN: $CRN" -H "$header_json" 2>>"$log_file"
}

# (1.21.0) Same request as job_ls(), with the HTTP status appended as the last line - the
# same idiom job_get() already uses - so -jobslsall/-jobsls can tell an empty workspace
# ("no jobs") apart from a failed request (expired IAM token, wrong CRN, deleted workspace).
job_ls_status() {
	curl -sS --connect-timeout 30 --max-time 60 -w '\n%{http_code}' -X GET $base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/jobs -H "$header_auth" -H "CRN: $CRN" -H "$header_json" 2>>"$log_file"
}

# (1.21.0) Cancels/deletes a job. HTTP status appended as the last line, same idiom as
# img_del()/vol_cl_del(); read by delete_check() in do_job_cancel(). Uses $JOB_ID, the same
# global job_get() reads, set by job_find_ws() before this is called.
job_del() {
	curl -sX DELETE $base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/jobs/$JOB_ID -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -w '\n%{http_code}'
}

## Images
img_ls() {
	curl -sX GET $base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/images -H "$header_auth" -H "CRN: $CRN" -H "$header_json"
}

img_del() {
	# (1.18.6) The HTTP status is appended as the last line, as img_import_api does, so the
	# caller can tell a refused delete (4xx) from a successful one; the body alone could not.
	curl -sX DELETE $base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/images/$IMAGE_ID -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -w '\n%{http_code}'
}

img_import_api() {
	curl -sX POST $base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/cos-images -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -d "{$ACTIONS}" -w '\n%{http_code}'
}

img_export_api() {
	curl -sX POST $base_url/pcloud/v2/cloud-instances/$CLOUD_INSTANCE_ID/images/$IMAGE_ID/export -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -d "{$ACTIONS}" -w '\n%{http_code}'
}

img_import_status_api() {
	curl -sX GET $base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/cos-images -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -w '\n%{http_code}'
}

img_export_status_api() {
	curl -sX GET $base_url/pcloud/v2/cloud-instances/$CLOUD_INSTANCE_ID/images/$IMAGE_ID/export -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -w '\n%{http_code}'
}

## Snapshots
snap_ls() {
	curl -sX GET $base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/snapshots -H "$header_auth" -H "CRN: $CRN" -H "$header_json"
}

snap_cr() {
	curl -sX POST $base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/pvm-instances/$PVM_ID/snapshots -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -d "{$ACTIONS}"
}

snap_del() {
	curl -sX DELETE $base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/snapshots/$SNAP_ID -H "$header_auth" -H "CRN: $CRN" -H "$header_json"
}

snap_upd() {
	curl -sX PUT $base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/snapshots/$SNAP_ID -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -d "{$ACTIONS}"
}

snap_res() {
	curl -sX POST $base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/pvm-instances/$PVM_ID/snapshots/$SNAP_ID/restore -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -d "{$ACTIONS}"
}

## COS
list_object() {
	curl -sX GET https://s3.$REGION.cloud-object-storage.appdomain.cloud/$BUCKET?list-type=2 -H "$header_auth"
}

# (1.23.0) Same GET as list_object(), with an optional S3 continuation token
# (CONTINUATION_TOKEN, set by the caller) appended - used by -invreport's
# bounded COS object-count pagination loop (see invreport_bucket_objects).
# A separate function, not a change to list_object(): that one has another
# caller (-bucketlsobjs) that always wants exactly one, unparameterised page.
list_object_page() {
	local qs="list-type=2"
	if [ -n "$CONTINUATION_TOKEN" ]
	then
		qs="$qs&continuation-token=$(printf '%s' "$CONTINUATION_TOKEN" | jq -sRr @uri)"
	fi
	curl -sX GET "https://s3.$REGION.cloud-object-storage.appdomain.cloud/$BUCKET?$qs" -H "$header_auth"
}

object_delete() {
	# (1.18.6) HTTP status appended as the last line; S3 answers a failed delete with an XML
	# <Error> body and a 4xx, and the caller has to read one or the other to notice.
	curl -sX DELETE https://s3.$REGION.cloud-object-storage.appdomain.cloud/$BUCKET/$KEY -H "$header_auth" -w '\n%{http_code}'
}

cos_ins_ls() {
	curl -sX GET https://resource-controller.cloud.ibm.com/v2/resource_instances?type=service_instance -H "$header_auth" -H "$header_accept"
}

cos_ls_buckets() {
	curl -sX GET https://s3.$REGION.cloud-object-storage.appdomain.cloud/ -H "$header_auth" -H "ibm-service-instance-id: $SERVICE_INSTANCE_ID"
}

cos_rest_arch() {
	# (1.18.6) The body is XML (see do_object_restore_from_archive), so say so; it was sent
	# under Content-Type: application/json.
	#
	# (1.18.7) COS requires an integrity header on a restore request: Content-MD5, the base64
	# MD5 of the exact body sent. It is computed with openssl when the system has it; without
	# openssl the request goes as before and a warning is logged.
	local content_md5=""
	if command -v openssl >/dev/null 2>&1
	then
		content_md5=$(printf '%s' "$ACTIONS" | openssl dgst -md5 -binary | openssl base64)
	fi
	if [ -n "$content_md5" ]
	then
		curl -sX POST https://s3.$REGION.cloud-object-storage.appdomain.cloud/$BUCKET/$OBJECT?restore -H "$header_auth" -H "Content-Type: application/xml" -H "Content-MD5: $content_md5" -d "$ACTIONS"
	else
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - WARNING - openssl not found: the restore request is sent without Content-MD5 and Cloud Object Storage may refuse it." "1"
		curl -sX POST https://s3.$REGION.cloud-object-storage.appdomain.cloud/$BUCKET/$OBJECT?restore -H "$header_auth" -H "Content-Type: application/xml" -d "$ACTIONS"
	fi
}
#### END:FUNCTIONS - API Commands ####

#### START:FUNCTIONS - Helper vg_is_sync_aux_to_master
vg_is_sync_aux_to_master() {
	# Returns:
	#  0 -> already syncing aux->master (replicationStatus=enabled, state=consistent_copying, primaryRole=aux)
	#  1 -> not in desired state
	#  2 -> could not read VG status (caller should abort)
	local t_rep t_state t_primary
	t_rep=$(vg_get 2>>"$log_file" | jq -r '.replicationStatus // empty' 2>>"$log_file")
	t_state=$(vg_sd 2>>"$log_file" | jq -r '.state // empty' 2>>"$log_file")
	t_primary=$(vg_get 2>>"$log_file" | jq -r '.primaryRole // empty' 2>>"$log_file")
	if [[ -z "$t_rep" || -z "$t_state" ]]
	then
		return 2
	fi
	if [[ "$t_rep" == "enabled" && "$t_state" == "consistent_copying" && "$t_primary" == "aux" ]]
	then
		return 0
	fi
	return 1
}
#### END:FUNCTIONS - Helper vg_is_sync_aux_to_master

#### START:FUNCTIONS - Helper vg_wait_sync_aux_to_master
vg_wait_sync_aux_to_master() {
	# Wait until VG reaches aux->master syncing steady state:
	# replicationStatus=enabled AND state=consistent_copying AND primaryRole=aux
	# Args:
	#  $1 -> label (e.g. TARGET)
	#  $2 -> max_wait (minutes), default 60
	#  $3 -> purpose string for error messages (optional)
	local label max_wait purpose
	label="$1"
	max_wait="$2"
	purpose="$3"
	if [[ -z "$label" ]]
	then
		label="VG"
	fi
	if [[ -z "$max_wait" ]]
	then
		max_wait=60
	fi
	if [[ -z "$purpose" ]]
	then
		purpose="aux->master sync"
	fi

	local i=0
	while true
	do
		local t_rep t_state t_primary
		t_rep=$(vg_get 2>>"$log_file" | jq -r '.replicationStatus // empty' 2>>"$log_file")
		t_state=$(vg_sd 2>>"$log_file" | jq -r '.state // empty' 2>>"$log_file")
		t_primary=$(vg_get 2>>"$log_file" | jq -r '.primaryRole // empty' 2>>"$log_file")

		if [[ -z "$t_rep" || -z "$t_state" ]]
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Could not read $label VG status while monitoring $purpose." 1
		fi

		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - $label VG status: state=$t_state, replicationStatus=$t_rep, primaryRole=${t_primary:-UNKNOWN}" "1"

		if [[ "$t_rep" == "enabled" && "$t_state" == "consistent_copying" && "$t_primary" == "aux" ]]
		then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - $label VG is now syncing aux->master (enabled + consistent_copying + primaryRole=aux)." "1"
			break
		fi

		i=$((i + 1))
		if (( i >= max_wait ))
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - $label VG did not reach aux->master syncing state after $max_wait minutes (last: state=$t_state, replicationStatus=$t_rep, primaryRole=${t_primary:-UNKNOWN})." 1
		fi
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Waiting 60 seconds..." "1"
		sleep 60
	done
}
#### END:FUNCTIONS - Helper vg_wait_sync_aux_to_master

#### START:FUNCTIONS - GRS Code Helpers ####
## Helper: checks a GRS write call's HTTP status
# (1.20.0) The GRS write calls (vg_cr, vg_act, vg_del, vg_upd, on_cr, the replicationEnabled
# vol_act, ins_vol_bdet, vol_att_multi, vol_bdel) used to be piped straight to the log, or
# checked only by grepping the body for ".code"/".error" - a field a non-2xx error body does
# not have to carry. A rejected request could look identical to a success and the flow kept
# going onto volumes/groups the API never touched. This reads the trailing HTTP status that
# each call's "*_status" wrapper appends (same shape as vol_act_status/ins_cap) and aborts on
# anything but 2xx, naming the step and, when given, what earlier steps in this call already
# reached the API.
# Args: $1 raw response (body + trailing "\n%{http_code}" line)  $2 step description
#       $3 optional note on what was already sent before this step
grs_check_write() {
	local raw="$1" desc="$2" prior="${3:-}" code body api_msg
	code="${raw##*$'\n'}"
	body="${raw%$'\n'*}"
	printf '%s\n' "$body" >>"$log_file"
	if [[ ! "$code" =~ ^2[0-9][0-9]$ ]]
	then
		api_msg=$(printf '%s' "$body" | jq -r '.description // .message // .error // .errors[0].message // empty' 2>/dev/null)
		if [[ -n "$prior" ]]
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - $desc (HTTP ${code:-?}): ${api_msg:-$body}. Note: $prior." 1
		else
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - $desc (HTTP ${code:-?}): ${api_msg:-$body}." 1
		fi
	fi
}

## Helper: check and enable replication on volumes, then wait until all are replicationEnabled=true
chk_vol_rep() {
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Checking and enabling replication on source volumes if needed..." "1"
	flag=0
	for i in $vol_ids
	do
		VOL_ID=$i
		rep_enabled=$(vol_get | jq -r '.replicationEnabled' 2>>"$log_file")
		if [[ "$rep_enabled" == "false" ]]
		then
			flag=1
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Volume ID: $i replicationEnabled=false. Enabling replication..." "1"
			ACTIONS='"replicationEnabled": true'
			# (1.20.0) HTTP status checked instead of just logged: a rejected
			# replicationEnabled=true would otherwise wait forever below for a state
			# the API never reached.
			resp_rep=$(vol_act_status 2>>"$log_file")
			grs_check_write "$resp_rep" "enabling replication on volume $i"
		fi
	done
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Replication check done." "1"
	if [[ "$flag" == "1" ]]
	then
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Some volumes had replicationEnabled=false and were changed to true. Rechecking until all are updated..." "1"
		sleep 10
		# (1.20.0) Bounded: 180 checks at 10s = 30 minutes.
		local rep_wait=0
		while true
		do
			if vol_ls | jq -r '.volumes[]? | "\(.name) \(.replicationEnabled)"' | grep -w "$vol_com_name" | grep false >/dev/null
			then
				rep_wait=$((rep_wait + 1))
				if [ "$rep_wait" -ge 180 ]
				then
					abort "`date +%Y-%m-%d_%H:%M:%S` - chk_vol_rep did not finish: some $vol_com_name volumes still show replicationEnabled=false after 30 minutes." 1
				fi
				echoscreen "`date +%Y-%m-%d_%H:%M:%S` - There are still volumes with replicationEnabled=false. Waiting 10 seconds..." "1"
				sleep 10
			else
				break
			fi
		done
	fi
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - All volumes are replicationEnabled=true." "1"
}

## Helper: wait until all volumes with the given prefix are in consistent_copying
chk_vol_mirror() {
	# (1.20.0) Bounded: volumes copy whole disks, so this defaults to 24h; override in
	# minutes with BLUEXPORT_GRS_MIRROR_MAX_MIN. The sleep interval is 180s (3 minutes),
	# so the loop count is ceil(max_min/3).
	local max_min="${BLUEXPORT_GRS_MIRROR_MAX_MIN:-1440}"
	local max_loops=$(( (max_min + 2) / 3 ))
	local loop=0
	while true
	do
		# Só volumes com o padrão vol_com_name e ainda em inconsistent_copying
		inc_vols=$(vol_ls 2>>"$log_file" | jq -r --arg pat "$vol_com_name" '
			.volumes[]?
			| select(.name | contains($pat))
			| select(.mirroringState == "inconsistent_copying")
			| "\(.volumeID) \(.name)"
		')
		# Se já não há volumes em inconsistent_copying, terminamos
		if [ -z "$inc_vols" ]
		then
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - All volumes are in consistent_copying state." "1"
			break
		fi
		# Quantos volumes ainda estão inconsistent
		num_inc=$(printf "%s\n" "$inc_vols" | wc -l | awk '{print $1}')
		if [ $num_inc -lt 6 ]
		then
			cyclemsg=""
		else
			cyclemsg="Showing progress for up to 5 volumes this cycle..."
		fi
		if [ $num_inc -eq 1 ]
		then
			plural=""
			verb="is"
		else
			plural="s"
			verb="are"
		fi
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - $num_inc volume$plural $verb still in inconsistent_copying. $cyclemsg" "1"
		shown=0
		# Para cada volume inconsistente, chamar vol_rcr e mostrar progresso – até 5 por ciclo
		while read -r vol_id vol_name
		do
			[ -z "$vol_id" ] && continue
			VOL_ID="$vol_id"
			rcr_json=$(vol_rcr 2>>"$log_file")
			rcr_rc=$?
			if [ $rcr_rc -ne 0 ] || [ -z "$rcr_json" ]
			then
				if echo "$rcr_json" | grep -q "Too Many Requests"
				then
					echoscreen "`date +%Y-%m-%d_%H:%M:%S` - WARNING: vol_rcr rate limited for volume $vol_name ($vol_id). Backend returned 429 Too Many Requests. Progress for this volume will be retried in the next cycle..." "1"
				else
					echoscreen "`date +%Y-%m-%d_%H:%M:%S` - WARNING: Could not retrieve remote copy relationship for volume $vol_name ($vol_id). Will retry in next cycle..." "1"
				fi
			else
				prog=$(echo "$rcr_json"  | jq -r '.progress // 0'       2>>"$log_file")
				state=$(echo "$rcr_json" | jq -r '.state // "unknown"'  2>>"$log_file")
				echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Volume $vol_name ($vol_id): state = $state, progress = ${prog}%." "1"
			fi
			shown=$((shown + 1))
			if [ "$shown" -ge 5 ]
			then
				break
			fi
		done <<< "$inc_vols"
		if [ "$num_inc" -gt 5 ]
		then
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Reached 5 vol_rcr calls in this cycle. Remaining volumes will be checked in the next cycles..." "1"
		fi
		loop=$((loop + 1))
		if [ "$loop" -ge "$max_loops" ]
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` - chk_vol_mirror did not finish: volumes still inconsistent_copying after ${max_min} minutes: $(printf '%s' "$inc_vols" | tr '\n' ' ')" 1
		fi
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Sleeping 180 seconds..." "1"
                sleep 180
        done
}

## Helper: monitor onboarding status until completion
chk_on_status() {
	# (1.20.0) Bounded: 60 checks at 60s = 60 minutes.
	local on_wait=0
	while true
	do
		on_status=$(on_get | jq -r '.status' 2>>"$log_file")
		if [[ "$on_status" == "RUNNING" ]]
		then
			on_progress=$(on_get | jq -r '.progress' 2>>"$log_file")
			on_wait=$((on_wait + 1))
			if [ "$on_wait" -ge 60 ]
			then
				abort "`date +%Y-%m-%d_%H:%M:%S` - chk_on_status did not finish: onboarding still RUNNING at ${on_progress}% after 60 minutes." 1
			fi
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Onboarding status RUNNING at ${on_progress}% - waiting 60 seconds..." "1"
			sleep 60
		else
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Onboarding finished with status: $on_status" "1"
			break
		fi
	done
}
#### END:FUNCTIONS - GRS Code Helpers ####

#### START:FUNCTION - Check if image-catalog and Cloud Object has images from last time and delete them (API) ####
delete_previous_img() {
	REGION="$region"
	BUCKET="$bucket"
	# --- Image Catalog (PowerVS Images) via img_ls() ---
	# Look for an image whose name contains both $vsi and $old_img.
	#
	# Fix (1.18.3): WHEN $old_img IS A BARE HOUR, THE COMPARISON IS ANCHORED.
	# Capture names carry a full ISO date, and the date begins right after an
	# underscore just as the time segment does - so "_20" matched
	# NAME_2026-09-13_1400 as readily as NAME_20, and head -n1 then deleted whichever
	# the API happened to list first. On an LPAR with both an hourly rotation and a
	# nightly keep, that was the nightly image, one hour a day, for as long as the
	# year begins 20.
	#
	# The anchor is "not followed by another digit", which is exactly the property
	# that separates NAME_20 and NAME_20.ova from NAME_2026-... It holds whatever
	# suffix an object key carries, which a plain endswith would not.
	#
	# The daily/weekly/monthly tokens are full %Y-%m-%d dates and stay on contains:
	# the name is NAME_YYYY-MM-DD_HHMM, so the date is not at the end and the token
	# is long enough not to collide by accident.
	local img_json
	img_json=$(img_ls 2>>"$log_file")
	img_id_old=$(echo "$img_json" | jq -r \
		--arg vsi "$vsi" \
		--arg old "$old_img" \
		--arg anchor "$old_is_hour" '
		.images[]?
		| select((.name | contains($vsi))
		         and (if $anchor == "1"
		              then (.name | test($old + "([^0-9]|$)"))
		              else (.name | contains($old)) end))
		| .imageID
	' 2>>"$log_file" | head -n1)
	img_name_old=$(echo "$img_json" | jq -r \
		--arg vsi "$vsi" \
		--arg old "$old_img" \
		--arg anchor "$old_is_hour" '
		.images[]?
		| select((.name | contains($vsi))
		         and (if $anchor == "1"
		              then (.name | test($old + "([^0-9]|$)"))
		              else (.name | contains($old)) end))
		| .name
	' 2>>"$log_file" | head -n1)
	# --- COS (Object Storage) via list_object() ---
	# list_object() returns XML (S3 ListBucketResult). We parse <Key>...</Key> lines.
	local list_xml
	list_xml=$(list_object 2>>"$log_file")
	# Previous export object (old_img)
	# Fix (1.18.3): same anchoring as the image-catalog match above. An object
	# key carries a suffix, so this is a "not followed by a digit" test rather than a
	# suffix comparison - see the reasoning there.
	objstg_img=$(echo "$list_xml" | \
		awk -v vsi="$vsi" -v old="$old_img" -v anchor="$old_is_hour" '
			match($0, /<Key>([^<]+)<\/Key>/, m) {
				key = m[1]
				if (index(key, vsi) > 0) {
					if (anchor == "1") {
						if (key ~ (old "([^0-9]|$)")) { print key }
					} else {
						if (index(key, old) > 0) { print key }
					}
				}
			}
		' | head -n1)
	# Today export object (capture_date)
	today_img=$(echo "$list_xml" | \
		awk -v vsi="$vsi" -v today="$capture_date" '
			match($0, /<Key>([^<]+)<\/Key>/, m) {
				key = m[1]
				if (index(key, vsi) > 0 && index(key, today) > 0) {
					print key
				}
			}
		' | head -n1)
	# --- Delete from Image Catalog (if found) ---
	if [[ -z "$img_id_old" ]]
	then
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - There is no Image from $old_img - Nothing to delete in image catalog." "1"
	else
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - == Deleting from image catalog image name $img_name_old - image ID $img_id_old - from day $old_img... ==" "1"
		IMAGE_ID="$img_id_old"
		del_raw=$(img_del 2>>"$log_file")
		printf '%s\n' "$del_raw" >> "$log_file"
		delete_check "$del_raw" "image $img_name_old" || true
	fi
	# --- Delete from Object Storage (if safe) ---
	if [[ -z "$objstg_img" ]]
	then
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - No image from previous export to delete in Object Storage." "1"
	else
		if [[ -z "$today_img" ]]
		then
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - == Something went wrong... Today's image is not in Bucket $bucket. Keeping (Not deleted) image name $objstg_img from day $old_img... ==" "1"
		else
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - == Deleting from Bucket $bucket, image name $objstg_img from day $old_img... ==" "1"
			KEY="$objstg_img"
			del_raw=$(object_delete 2>>"$log_file")
			printf '%s\n' "$del_raw" >> "$log_file"
			delete_check "$del_raw" "object $KEY in bucket $bucket" || true
		fi
	fi
}
#### END:FUNCTION - Check if image-catalog as images from last saturday and deleted it ####

####  START:FUNCTION - Target DC and List all VSI in the POWERVS DC and Get VSI Name and ID  ####
dc_vsi_list() {
  # List all VSIs in this PowerVS DC and get VSI Name and ID
	base_url=$default_base_url
	region_api=$(ws_ls | jq -r --arg s "$shortnamecrn" '.workspaces[] | select(.details.crn == $s) | .location.region | gsub("-"; "_")')
	base_url_var="base_${region_api}"
	base_url="${!base_url_var}"
	# (1.19.0) An empty region_api (workspace not found in ws_ls, or its CRN region has
	# no matching base_<region> variable) used to leave base_url blank via the indirect
	# expansion above - every subsequent API call would then hit a bare/wrong host. Stop
	# instead of silently keeping (or losing) a default; a wrong endpoint is worse.
	if [[ -z "$region_api" || -z "$base_url" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Could not resolve base_url for CRN $shortnamecrn (region_api='$region_api'); no $base_url_var variable is defined." 1
	fi
	CRN="$shortnamecrn"
	PVM_ID="$vsi_id"
	CLOUD_INSTANCE_ID=$(jq -r --arg ws "$vsiwsshort" '.workspaces[$ws].id' "$bluexscrt")
	ins_ls | jq -r --arg pvmid "$PVM_ID" '.pvmInstances[] | select(.pvmInstanceID == $pvmid) | "\(.pvmInstanceID) \(.serverName)"'# > "$vsi_list_id_tmp" 2>> "$log_file"
	vsi_id=$(grep -wi "$vsi" "$vsi_list_id_tmp" | awk '{print $1}')
	if [[ -z "$vsi_id" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Instance $vsi exists in your config file ($bluexscrt), but does not exist on IBM Cloud. Please update the JSON config!" 1
	fi
	awk '{print $2}' "$vsi_list_id_tmp" > "$vsi_list_tmp"
}
####  END:FUNCTION - Target DC and List all VSI in the POWERVS DC and Get VSI Name and ID  ####

####  START:FUNCTION - Job poll retry delay (job_monitor and wait_for_job)  ####
# job_poll_delay FAIL_COUNT HTTP_CODE HDR_FILE
# (1.19.0) A job poll that comes back with no readable status used to retry every
# 30s flat, for up to job_get_max_fail attempts - hammering an API that is already
# struggling. Backs off instead: 30s, 60s, 120s, 240s, then holds at 300s. On HTTP
# 429 the server's own Retry-After (seconds form) wins when present; otherwise the
# same backoff applies. HDR_FILE is the curl -D header dump from job_get.
job_poll_delay() {
	local fail_count="$1" http_code="$2" hdr_file="$3" retry_after
	if [[ "$http_code" == "429" ]] && [[ -s "$hdr_file" ]]
	then
		retry_after=$(awk 'tolower($1) ~ /^retry-after:$/ {gsub(/\r/,""); print $2; exit}' "$hdr_file" 2>/dev/null)
		if [[ "$retry_after" =~ ^[0-9]+$ ]]
		then
			echo "$retry_after"
			return
		fi
	fi
	case "$fail_count" in
		1) echo 30 ;;
		2) echo 60 ;;
		3) echo 120 ;;
		4) echo 240 ;;
		*) echo 300 ;;
	esac
}
####  END:FUNCTION - Job poll retry delay  ####

####  START:FUNCTION - Monitor Capture and Export Job  ####
job_monitor() {
  # Get Capture & Export Job ID
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Job log in file $job_log" "1"
	if [ "$flagj" -eq 1 ]
	then
        	# Reuse existing job mapping from operid_file: <capture_name> <job_id>
		job_id=$(awk -v name="$capture_name" '$1 == name {print $2; exit}' "$operid_file")
		if [[ -z "$job_id" || "$job_id" == "null" ]]; then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - No Job ID found for capture $capture_name in $operid_file" 1
		fi
	else
		if [[ -z "$job_id" || "$job_id" == "null" ]]
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - Capturing instance $vsi has failed, see log file!" 1
		fi
		echo "$capture_name $job_id" >> "$operid_file"
	fi
  # Check Capture & Export Job Status
	echo "Job Monitoring of VM Capture $capture_name - Job ID: $job_id" >> "$job_log"
	operation_before=""
	job_get_fail_count=0
	job_get_max_fail=10          # abort only after this many consecutive bad polls
	token_refresh_secs="${iam_refresh_secs:-2700}"      # refresh IAM token before it expires
	job_hdr_file="/tmp/bluexport_job_headers_$$.out"    # (1.19.0) curl -D dump, for Retry-After
	while true
	do
		JOB_ID="$job_id"

		# Proactively refresh the IAM token before it expires so a long-running
		# capture/export never hits an auth failure mid-poll.
		if [[ -n "$iam_token_epoch" ]] && (( $(date +%s) - iam_token_epoch >= token_refresh_secs ))
		then
			get_iam_token refresh
		fi

		# Get current job JSON once and reuse. job_get appends the HTTP code
		# as a trailing line; split it back out here (must happen in this
		# process, not inside job_get, since command substitution runs it
		# in a subshell where a global variable couldn't be read back).
		job_raw=$(job_get "$job_hdr_file")
		http_code="${job_raw##*$'\n'}"
		job_json="${job_raw%$'\n'*}"
		job_status=$(printf '%s' "$job_json" | jq -r '.status.state // empty' 2>/dev/null)

		# Transient failure: network error, non-2xx HTTP, empty/invalid JSON.
		# Retry with backoff instead of aborting the whole export outright.
		if [[ -z "$job_status" ]]
		then
			job_get_fail_count=$((job_get_fail_count + 1))
			echo "$(date +%Y-%m-%d_%H:%M:%S) - WARNING - Could not read Job $job_id status (HTTP ${http_code:-?}, attempt $job_get_fail_count/$job_get_max_fail). Response: $job_json" >> "$job_log"
			if [[ "$http_code" == "401" ]]
			then
				echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - IAM token was rejected (HTTP 401). Refreshing token..." "1"
				get_iam_token refresh
			fi
			if [[ "$job_get_fail_count" -ge "$job_get_max_fail" ]]
			then
				echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - FAILED Getting Job ID or no Job Running after $job_get_max_fail consecutive attempts!" "1"
				rm -f "$job_hdr_file"
				abort "$(date +%Y-%m-%d_%H:%M:%S) - Check file $job_monitor and $job_log for more details." 1
			fi
			# (1.19.0) Exponential backoff (30/60/120/240, capped 300s); a 429's own
			# Retry-After wins when the API sent one.
			job_retry_delay=$(job_poll_delay "$job_get_fail_count" "$http_code" "$job_hdr_file")
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - WARNING - Transient error reading Job $job_id status (HTTP ${http_code:-?}). Retrying in ${job_retry_delay}s ($job_get_fail_count/$job_get_max_fail)..." "1"
			spin_wait "$job_retry_delay" "Retrying job status check"
			continue
		fi
		job_get_fail_count=0

		# Save job output:
		#  - overwrite $job_monitor with the latest state
		#  - append to $job_log and $log_file for history
		printf '%s\n' "$job_json" | tee "$job_monitor" >>"$job_log"
		message=$(jq -r '.status.message // empty'     "$job_monitor")
		operation=$(jq -r '.status.progress // empty'  "$job_monitor")
		if [[ "$job_status" == "completed" ]]
		then
			if [[ "$destination" == "cloud-storage" ]]
			then
				echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Image Capture and Export of $vsi to Bucket $bucket Completed !!" "1"
			elif [[ "$destination" == "both" ]]
			then
				echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Image Capture and Export of $vsi to Image Catalog Completed !!" "1"
				echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Image Capture and Export of $vsi to Bucket $bucket Completed !!" "1"
			else
				echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Image Capture and Export of $vsi to Image Catalog Completed !!" "1"
			fi
			if [ "$single" -eq 0 ] && [ "$flagj" -ne 1 ]
			then
				# Fix (1.18.4): in the repeated hour of an autumn clock change, "1 hour
				# ago" is the same wall-clock hour as now, so the hourly token is THIS
				# capture's own name suffix and the cleanup could delete the image just made.
				# Skipping deletes nothing; the older same-named image is left for a later cleanup.
				if [ "$old_is_hour" -eq 1 ] && [ "$old_img" = "_$capture_hour" ]
				then
					echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Previous capture cleanup skipped: the previous hour's token $old_img is this capture's own name (repeated hour of a clock change). Nothing deleted." "1"
				else
					delete_previous_img
				fi
			fi
			echo "$(date +%Y-%m-%d_%H:%M:%S) - Finished Successfully!!" >> "$job_log"
			job_log_perm="${job_log_short}_${capture_name}.log"
			cp "$job_log" "$job_log_perm"
			if [ "$flagj" -eq 1 ] && [ -t 1 ]
			then
				echoscreen ""
				echoscreen "   ### Log files used:"
				echoscreen "   ### $log_file"
				echoscreen "   ### $job_log"
				echoscreen "   ### $job_monitor"
				echoscreen "   ### $job_log_perm"
				echoscreen ""
			fi
			abort "$(date +%Y-%m-%d_%H:%M:%S) - Finished Successfully!!"
		elif [[ "$job_status" == "queued" ]]
		then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Job ID $job_id Status: ${job_status^^}" "1"
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Message: $message" "1"
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Waiting for Operation Change... Operation Running Now: ${operation^^}" "1"
			echo "$(date +%Y-%m-%d_%H:%M:%S) - Running ${operation^^}... Sleeping 60 seconds..." >> "$job_log"
			spin_wait 60 "Running ${operation^^}"
			operation_before="$operation"
		elif [[ "$job_status" == "failed" ]]
		then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Job ID $job_id Status: ${job_status^^}" "1"
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Message: $message" "1"
			abort "$(date +%Y-%m-%d_%H:%M:%S) - Job Failed, check message!!" 1
		else
			if [[ "$operation" != "$operation_before" ]]
			then
        		        echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Job ID $job_id Status: ${job_status^^}" "1"
	        	       	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Message: $message" "1"
        	        	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Waiting for Operation Change... Operation Running Now: ${operation^^}" "1"
	                	echo "$(date +%Y-%m-%d_%H:%M:%S) - Running ${operation^^}... Sleeping 60 seconds..." >> "$job_log"
		                spin_wait 60 "Running ${operation^^}"
        		        operation_before="$operation"
			else
        		        echo "$(date +%Y-%m-%d_%H:%M:%S) - Still Running ${operation^^}... Sleeping 60 seconds..." >> "$job_log"
                		spin_wait 60 "Still running ${operation^^}"
			fi
		fi
	done
}
####  END:FUNCTION - Monitor Capture and Export Job  ####

####  START:FUNCTION - Generic Job Wait (image import/export, and future non-capture jobs) ####
# wait_for_job JOB_ID LABEL
#   JOB_ID: PowerVS job ID to poll (GET /pcloud/v1/.../jobs/$JOB_ID - same unified jobs
#           queue used by captures, image import, and image export).
#   LABEL:  short description used in progress/completion/failure messages,
#           e.g. "Image import of myimage" or "Image export of myimage to bucket mybucket".
# Same polling/retry logic as job_monitor() (proven in production for captures), but
# without anything capture-specific (no capture_name/vsi/destination, no delete_previous_img,
# no operid_file reuse, no per-capture permanent log file) - job_monitor() itself is left
# untouched. Exits the process 0 on success, 1 on failure (via abort()) - this function
# never returns to its caller.
wait_for_job() {
	local job_id="$1"
	local label="$2"
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Job log in file $job_log" "1"
	echo "Job Monitoring of $label - Job ID: $job_id" >> "$job_log"

	# The job may take a few seconds to actually register after being submitted;
	# a poll that lands too early can see "not found" and burn a retry attempt
	# for no reason. Give it a moment before the first check.
	spin_wait 10 "Waiting for job to register"

	local operation_before="" job_get_fail_count=0 job_get_max_fail=10
	local token_refresh_secs="${iam_refresh_secs:-2700}"
	local job_hdr_file="/tmp/bluexport_job_headers_$$.out"    # (1.19.0) curl -D dump, for Retry-After
	# (1.18.6) A wall-clock bound. A job that keeps answering a readable, non-terminal state
	# used to be polled forever; 24 hours by default, BLUEXPORT_JOB_MAX_SECS overrides it.
	# Stopping the monitor does not stop the job - re-attach with -j, -ji or -je.
	local job_max_secs="${BLUEXPORT_JOB_MAX_SECS:-86400}" job_started_epoch
	job_started_epoch=$(date +%s)

	while true
	do
		JOB_ID="$job_id"

		if [ $(( $(date +%s) - job_started_epoch )) -ge "$job_max_secs" ]
		then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - $label has not finished after $job_max_secs seconds. Monitoring stopped; the job itself CONTINUES in IBM Cloud. Re-attach later with -j, -ji or -je." "1"
			rm -f "$job_hdr_file"
			abort "$(date +%Y-%m-%d_%H:%M:%S) - Job ID $job_id monitoring timed out (limit BLUEXPORT_JOB_MAX_SECS=$job_max_secs)." 1
		fi

		if [[ -n "$iam_token_epoch" ]] && (( $(date +%s) - iam_token_epoch >= token_refresh_secs ))
		then
			get_iam_token refresh
		fi

		local job_raw http_code job_json job_status
		job_raw=$(job_get "$job_hdr_file")
		http_code="${job_raw##*$'\n'}"
		job_json="${job_raw%$'\n'*}"
		job_status=$(printf '%s' "$job_json" | jq -r '.status.state // empty' 2>/dev/null)

		if [[ -z "$job_status" ]]
		then
			job_get_fail_count=$((job_get_fail_count + 1))
			echo "$(date +%Y-%m-%d_%H:%M:%S) - WARNING - Could not read Job $job_id status (HTTP ${http_code:-?}, attempt $job_get_fail_count/$job_get_max_fail). Response: $job_json" >> "$job_log"
			if [[ "$http_code" == "401" ]]
			then
				echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - IAM token was rejected (HTTP 401). Refreshing token..." "1"
				get_iam_token refresh
			fi
			if [[ "$job_get_fail_count" -ge "$job_get_max_fail" ]]
			then
				echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - FAILED Getting Job ID or no Job Running after $job_get_max_fail consecutive attempts!" "1"
				rm -f "$job_hdr_file"
				abort "$(date +%Y-%m-%d_%H:%M:%S) - Check file $job_monitor and $job_log for more details." 1
			fi
			# (1.19.0) Exponential backoff (30/60/120/240, capped 300s); a 429's own
			# Retry-After wins when the API sent one.
			local job_retry_delay
			job_retry_delay=$(job_poll_delay "$job_get_fail_count" "$http_code" "$job_hdr_file")
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - WARNING - Transient error reading Job $job_id status (HTTP ${http_code:-?}). Retrying in ${job_retry_delay}s ($job_get_fail_count/$job_get_max_fail)..." "1"
			spin_wait "$job_retry_delay" "Retrying job status check"
			continue
		fi
		job_get_fail_count=0

		printf '%s\n' "$job_json" | tee "$job_monitor" >>"$job_log"
		local message operation
		message=$(jq -r '.status.message // empty'    "$job_monitor")
		operation=$(jq -r '.status.progress // empty' "$job_monitor")

		if [[ "$job_status" == "completed" ]]
		then
			echo "$(date +%Y-%m-%d_%H:%M:%S) - Finished Successfully!!" >> "$job_log"
			abort "$(date +%Y-%m-%d_%H:%M:%S) - $label completed successfully!!"
		elif [[ "$job_status" == "failed" ]]
		then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Job ID $job_id Status: ${job_status^^}" "1"
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Message: $message" "1"
			abort "$(date +%Y-%m-%d_%H:%M:%S) - $label failed, check message!!" 1
		elif [[ "$job_status" == "queued" ]]
		then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Job ID $job_id Status: ${job_status^^}" "1"
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Message: $message" "1"
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Waiting for Operation Change... Operation Running Now: ${operation^^}" "1"
			echo "$(date +%Y-%m-%d_%H:%M:%S) - Running ${operation^^}... Sleeping 60 seconds..." >> "$job_log"
			spin_wait 60 "Running ${operation^^}"
			operation_before="$operation"
		else
			if [[ "$operation" != "$operation_before" ]]
			then
				echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Job ID $job_id Status: ${job_status^^}" "1"
				echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Message: $message" "1"
				echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Waiting for Operation Change... Operation Running Now: ${operation^^}" "1"
				echo "$(date +%Y-%m-%d_%H:%M:%S) - Running ${operation^^}... Sleeping 60 seconds..." >> "$job_log"
				spin_wait 60 "Running ${operation^^}"
				operation_before="$operation"
			else
				echo "$(date +%Y-%m-%d_%H:%M:%S) - Still Running ${operation^^}... Sleeping 60 seconds..." >> "$job_log"
				spin_wait 60 "Still running ${operation^^}"
			fi
		fi
	done
}
####  END:FUNCTION - Generic Job Wait ####

####  START:FUNCTION - Locate a job's workspace (job_find_ws) ####
# (1.21.0) job_find_ws JOB_ID
#   A bare JOB_ID (as given to -jobget/-jobcancel) is scoped to the workspace/cloud instance
#   that owns it, which the caller does not name, so every configured workspace is tried with
#   job_get() (1.19.0's trailing-HTTP-status idiom, reused unchanged) until one answers 200 -
#   the same "search every workspace" idiom -imgdel/-je already use for a bare name.
#   Deliberately NOT called via command substitution: job_get()'s own comment explains why a
#   status can't come back through a global from inside $(...) - the same is true here, and
#   abort() itself needs to actually exit the script (not a subshell) on a hard failure, so
#   this function is called directly and reports through the globals below instead of stdout.
# Sets on a match: CRN/CLOUD_INSTANCE_ID/base_url/full_ws_name (the matched workspace, same
#   globals job_get() and the workspace-resolving flags already use), JOB_ID, JOB_JSON (the
#   job body) and JOB_FOUND_WS/JOB_FOUND_WS_NAME; returns 0. Returns 1 (nothing found) if no
#   configured workspace has this job. A workspace that answers something other than 200/404
#   (auth failure, network error) aborts immediately naming that workspace, instead of being
#   silently skipped and mis-reported as "job not found".
job_find_ws() {
	local job_id="$1" ws
	JOB_ID="$job_id"
	JOB_FOUND_WS=""
	JOB_FOUND_WS_NAME=""
	JOB_JSON=""
	read -r -a allws_array <<< "$allws"
	for ws in "${allws_array[@]}"
	do
		CRN=$(jq -r --arg ws "$ws" '.workspaces[$ws].crn' "$bluexscrt")
		CLOUD_INSTANCE_ID=$(jq -r --arg ws "$ws" '.workspaces[$ws].id' "$bluexscrt")
		full_ws_name=$(jq -r --arg ws "$ws" '.workspaces[$ws].name // $ws' "$bluexscrt")
		if [[ -z "$CRN" || "$CRN" == "null" || -z "$CLOUD_INSTANCE_ID" || "$CLOUD_INSTANCE_ID" == "null" ]]
		then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Workspace $ws ($full_ws_name) missing CRN or ID in $bluexscrt, skipping." "1"
			continue
		fi
		region_api=$(echo "$CRN" | sed -n 's/.*power-iaas:\([^:]*\):.*/\1/p' | tr '-' '_')
		if [[ -z "$region_api" ]]
		then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Could not parse region from CRN $CRN for workspace $full_ws_name, skipping." "1"
			continue
		fi
		base_url_var="base_${region_api}"
		base_url="${!base_url_var}"
		local job_raw job_http_code
		job_raw=$(job_get 2>>"$log_file")
		job_http_code="${job_raw##*$'\n'}"
		JOB_JSON="${job_raw%$'\n'*}"
		case "$job_http_code" in
			200)
				JOB_FOUND_WS="$ws"
				JOB_FOUND_WS_NAME="$full_ws_name"
				return 0
				;;
			404)
				continue
				;;
			*)
				abort "$(date +%Y-%m-%d_%H:%M:%S) - Failed to query Job $job_id in Workspace $full_ws_name, HTTP status ${job_http_code:-?}." 1
				;;
		esac
	done
	return 1
}
####  END:FUNCTION - Locate a job's workspace (job_find_ws) ####

####  START:FUNCTION - List every job in one workspace (do_jobs_ls) ####
# (1.21.0) Shared by -jobsls WORKSPACE and, per workspace, by -jobslsall. Prints one table:
# JOB_ID, OPERATION, TARGET, STATUS, PROGRESS, CREATED - the API's own status.state string,
# never re-worded (same rule job_monitor()/wait_for_job() already follow).
do_jobs_ls() {
	local workspace_arg="$1" ws_key
	if [[ -z "$workspace_arg" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - WORKSPACE is missing. Syntax: bluexport_api.sh -jobsls WORKSPACE" 1
	fi
	ws_key=$(jq -r --arg ws "$workspace_arg" '
		.workspaces
		| to_entries[]?
		| select((.key | ascii_downcase) == ($ws | ascii_downcase) or (.value.name | ascii_downcase) == ($ws | ascii_downcase))
		| .key
	' "$bluexscrt" 2>>"$log_file" | head -n1)
	if [[ -z "$ws_key" || "$ws_key" == "null" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Workspace $workspace_arg not found in $bluexscrt. Use the workspace short name or full workspace name from your JSON." 1
	fi
	CRN=$(jq -r --arg ws "$ws_key" '.workspaces[$ws].crn' "$bluexscrt")
	CLOUD_INSTANCE_ID=$(jq -r --arg ws "$ws_key" '.workspaces[$ws].id' "$bluexscrt")
	full_ws_name=$(jq -r --arg ws "$ws_key" '.workspaces[$ws].name // $ws' "$bluexscrt")
	if [[ -z "$CRN" || "$CRN" == "null" || -z "$CLOUD_INSTANCE_ID" || "$CLOUD_INSTANCE_ID" == "null" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Workspace $ws_key ($full_ws_name) missing CRN or ID in $bluexscrt. Aborting..." 1
	fi
	region_api=$(echo "$CRN" | sed -n 's/.*power-iaas:\([^:]*\):.*/\1/p' | tr '-' '_')
	if [[ -z "$region_api" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Could not resolve PowerVS API endpoint for workspace $full_ws_name." 1
	fi
	base_url_var="base_${region_api}"
	base_url="${!base_url_var}"
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - === Starting listing Jobs in Workspace $full_ws_name !" "1"
	local jobs_raw jobs_http jobs_body
	jobs_raw=$(job_ls_status 2>>"$log_file")
	jobs_http="${jobs_raw##*$'\n'}"
	jobs_body="${jobs_raw%$'\n'*}"
	case "$jobs_http" in
		2[0-9][0-9]) ;;
		*)
			abort "$(date +%Y-%m-%d_%H:%M:%S) - Failed to list Jobs in Workspace $full_ws_name, HTTP status ${jobs_http:-?}." 1
			;;
	esac
	if ! printf '%s' "$jobs_body" | jq -e '(.jobs // []) | length > 0' >/dev/null 2>&1
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - === No Jobs Found in Workspace $full_ws_name"
	fi
	printf "%-38s %-16s %-20s %-11s %-8s %-25s\n" "JOB_ID" "OPERATION" "TARGET" "STATUS" "PROGRESS" "CREATED" | tee -a "$log_file"
	printf -- "-----------------------------------------------------------------------------------------------------------------\n" | tee -a "$log_file"
	printf '%s' "$jobs_body" | jq -r '
		.jobs[]? |
		[
			(.id // "N/A"),
			(.operation.action // .operation.id // "N/A"),
			(.operation.target // "N/A"),
			(.status.state // "N/A"),
			(.status.progress // "N/A"),
			(.createTimestamp // "N/A")
		] | @tsv
	' 2>>"$log_file" | while IFS=$'\t' read -r j_id j_op j_target j_status j_progress j_created
	do
		printf "%-38s %-16s %-20s %-11s %-8s %-25s\n" "$j_id" "$j_op" "$j_target" "$j_status" "$j_progress" "$j_created" | tee -a "$log_file"
	done
	abort "$(date +%Y-%m-%d_%H:%M:%S) - === Finished listing Jobs in Workspace $full_ws_name"
}
####  END:FUNCTION - List every job in one workspace (do_jobs_ls) ####

####  START:FUNCTION - List every job in every workspace (do_jobs_lsall) ####
# (1.21.0) -jobslsall: one merged table across every configured workspace, with a leading
# WORKSPACE column - unlike -imglsall/-snaplsall/-vclonelsall, which print a separate section
# per workspace, the brief for this flag asks for a single table. A workspace missing CRN/ID
# in the secrets file is skipped (a config problem, not an API call, so nothing to check the
# status of); once a call IS made, a non-2xx response aborts naming that workspace.
do_jobs_lsall() {
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - === Starting listing all Jobs in all Workspaces !" "1"
	read -r -a allws_array <<< "$allws"
	printf "%-20s %-38s %-16s %-20s %-11s %-8s %-25s\n" "WORKSPACE" "JOB_ID" "OPERATION" "TARGET" "STATUS" "PROGRESS" "CREATED" | tee -a "$log_file"
	printf -- "-------------------------------------------------------------------------------------------------------------------------------\n" | tee -a "$log_file"
	local any_rows=0
	local ws
	for ws in "${allws_array[@]}"
	do
		CRN=$(jq -r --arg ws "$ws" '.workspaces[$ws].crn' "$bluexscrt")
		CLOUD_INSTANCE_ID=$(jq -r --arg ws "$ws" '.workspaces[$ws].id' "$bluexscrt")
		full_ws_name=$(jq -r --arg ws "$ws" '.workspaces[$ws].name // $ws' "$bluexscrt")
		if [[ -z "$CRN" || "$CRN" == "null" || -z "$CLOUD_INSTANCE_ID" || "$CLOUD_INSTANCE_ID" == "null" ]]
		then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Workspace $ws ($full_ws_name) missing CRN or ID in $bluexscrt, skipping..." "1"
			continue
		fi
		region_api=$(echo "$CRN" | sed -n 's/.*power-iaas:\([^:]*\):.*/\1/p' | tr '-' '_')
		if [[ -z "$region_api" ]]
		then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Could not parse region from CRN $CRN for workspace $full_ws_name, skipping." "1"
			continue
		fi
		base_url_var="base_${region_api}"
		base_url="${!base_url_var}"
		local jobs_raw jobs_http jobs_body
		jobs_raw=$(job_ls_status 2>>"$log_file")
		jobs_http="${jobs_raw##*$'\n'}"
		jobs_body="${jobs_raw%$'\n'*}"
		case "$jobs_http" in
			2[0-9][0-9]) ;;
			*)
				abort "$(date +%Y-%m-%d_%H:%M:%S) - Failed to list Jobs in Workspace $full_ws_name, HTTP status ${jobs_http:-?}." 1
				;;
		esac
		if ! printf '%s' "$jobs_body" | jq -e '(.jobs // []) | length > 0' >/dev/null 2>&1
		then
			continue
		fi
		any_rows=1
		printf '%s' "$jobs_body" | jq -r '
			.jobs[]? |
			[
				(.id // "N/A"),
				(.operation.action // .operation.id // "N/A"),
				(.operation.target // "N/A"),
				(.status.state // "N/A"),
				(.status.progress // "N/A"),
				(.createTimestamp // "N/A")
			] | @tsv
		' 2>>"$log_file" | while IFS=$'\t' read -r j_id j_op j_target j_status j_progress j_created
		do
			printf "%-20s %-38s %-16s %-20s %-11s %-8s %-25s\n" "$full_ws_name" "$j_id" "$j_op" "$j_target" "$j_status" "$j_progress" "$j_created" | tee -a "$log_file"
		done
	done
	if [ "$any_rows" -eq 0 ]
	then
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - No Jobs Found in any configured Workspace." "1"
	fi
	abort "$(date +%Y-%m-%d_%H:%M:%S) - === Finished listing all Jobs in all Workspaces"
}
####  END:FUNCTION - List every job in every workspace (do_jobs_lsall) ####

####  START:FUNCTION - Show one job's full detail (do_job_get) ####
do_job_get() {
	local job_id="$1"
	if [[ -z "$job_id" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - JOB_ID is missing. Syntax: bluexport_api.sh -jobget JOB_ID" 1
	fi
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - === Looking up Job $job_id in all Workspaces ===" "1"
	if ! job_find_ws "$job_id"
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Job $job_id not found in any configured Workspace." 1
	fi
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Job $job_id found in Workspace $JOB_FOUND_WS_NAME:" "1"
	printf '%s\n' "$JOB_JSON" | jq -r '
		"Job ID: \(.id // "N/A")\n" +
		"Operation: \(.operation.action // .operation.id // "N/A")\n" +
		"Target: \(.operation.target // "N/A")\n" +
		"Status: \(.status.state // "N/A")\n" +
		"Progress: \(.status.progress // "N/A")\n" +
		"Message: \(.status.message // "N/A")\n" +
		"Created: \(.createTimestamp // "N/A")"
	' 2>>"$log_file" | tee -a "$log_file"
	abort "$(date +%Y-%m-%d_%H:%M:%S) - === Finished Job $job_id detail lookup in Workspace $JOB_FOUND_WS_NAME ==="
}
####  END:FUNCTION - Show one job's full detail (do_job_get) ####

####  START:FUNCTION - Cancel/delete a job (do_job_cancel) ####
# (1.21.0) Refuses unless the job's own status, read fresh via job_find_ws()/job_get(), is
# still one an API-side cancel is meaningful for: "completed" and "failed" are terminal - the
# job already finished and there is nothing left to cancel, so this refuses locally rather
# than sending a DELETE the API would answer with a 4xx anyway. Any other state (queued,
# running, or anything not yet recognized as terminal) reaches confirm_or_abort(), 1.19.0's
# typed-confirmation helper (-vclone/-vclonedel/-vchtier/-insvchtier's), then job_del(); its
# HTTP status is read by delete_check() exactly as do_img_delete() does for -imgdel.
do_job_cancel() {
	local job_id="$1" job_status job_status_lc del_output
	if [[ -z "$job_id" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - JOB_ID is missing. Syntax: bluexport_api.sh -jobcancel JOB_ID" 1
	fi
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - === Looking up Job $job_id in all Workspaces before cancelling ===" "1"
	if ! job_find_ws "$job_id"
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Job $job_id not found in any configured Workspace. Nothing cancelled." 1
	fi
	job_status=$(printf '%s' "$JOB_JSON" | jq -r '.status.state // empty' 2>/dev/null)
	if [[ -z "$job_status" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Could not read Job $job_id status in Workspace $JOB_FOUND_WS_NAME. Nothing cancelled." 1
	fi
	job_status_lc="${job_status,,}"
	if [[ "$job_status_lc" == "completed" || "$job_status_lc" == "failed" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Job $job_id in Workspace $JOB_FOUND_WS_NAME is already $job_status - nothing to cancel." 1
	fi
	confirm_or_abort "Cancel/delete Job $job_id (status $job_status) in Workspace $JOB_FOUND_WS_NAME. This cannot be undone." "$job_id"
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Cancelling Job $job_id in Workspace $JOB_FOUND_WS_NAME..." "1"
	del_output=$(job_del 2>>"$log_file")
	if ! delete_check "$del_output" "Job $job_id"
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Job $job_id in Workspace $JOB_FOUND_WS_NAME was NOT cancelled." 1
	fi
	abort "$(date +%Y-%m-%d_%H:%M:%S) - === Job $job_id in Workspace $JOB_FOUND_WS_NAME cancelled successfully. ==="
}
####  END:FUNCTION - Cancel/delete a job (do_job_cancel) ####

####  START:FUNCTION - Get iASP name  ####
get_iASP_name() {
	vsi_status=$(ins_get | jq -r '.status')
	shutoff=0
	if [ $test -eq 0 ]
	then
		vsi_ip=$(jq -r --arg name "$vsi" '.systems[] | select((.name | ascii_downcase) == ($name | ascii_downcase)) | .ip' "$bluexscrt")
		if [[ -z "$vsi_ip" || "$vsi_ip" == "null" ]]
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - VSI $vsi not found in JSON systems[] section. Aborting..." 1
		fi
		# Detect local execution
		local_name=$(hostname -s 2>/dev/null)
		if [[ "$local_name" == "${vsi^^}" ]]
		then
			###################################################################
			# WE ARE RUNNING ON THE SAME VSI — NO PING, NO SSH, DIRECT EXECUTION
			###################################################################
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Running locally on VSI $vsi — skipping ping and ssh checks." "1"
			if [[ "$vsi_status" == "SHUTOFF" ]]
			then
				echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - VSI $vsi is SHUTOFF" "1"
				shutoff=1
				return
			fi
			if [[ "$vsi_os" != "ibmi" ]]
			then
				echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - VSI $vsi is $vsi_os - skipping iASP discovery (IBM i-only, not applicable)." "1"
				echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - VSI $vsi is in Status: $vsi_status" "1"
				return
			fi
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - VSI $vsi is in Status: $vsi_status" "1"
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Getting $vsi iASP Names locally..." "1"
			cmd="system 'WRKCFGSTS CFGTYPE(*DEV) CFGD(*ASP)'"
			iasp_output=$(eval "$cmd")
		else
			###################################################################
			# REMOTE VSI — NORMAL FLOW (PING + SSH)
			###################################################################
			if [[ "$vsi_status" != "SHUTOFF" ]]
			then
				if [[ "$vsi_os" != "ibmi" ]]
				then
					echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - VSI $vsi is $vsi_os - skipping iASP discovery (IBM i-only, not applicable)." "1"
					echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - VSI $vsi is in Status: $vsi_status" "1"
					return
				fi
				if [[ "$(uname -s)" == "OS400" ]]
				then
					PING="system \"PING RMTSYS('$vsi_ip') NBRPKT(1) WAITTIME(3)\""
				else
					PING="ping -c1 -w3 $vsi_ip"
				fi
				if eval $PING &> /dev/null
				then
					echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - VSI $vsi is in Status: $vsi_status" "1"
					echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Ping VSI $vsi at IP $vsi_ip OK." "1"
					echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Getting $vsi iASP Names..." "1"
				else
					echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - First ping to $vsi_ip failed, retrying..." "1"
					if ! eval $PING &> /dev/null
					then
						abort "$(date +%Y-%m-%d_%H:%M:%S) - Cannot ping VSI $vsi at $vsi_ip ! Aborting..." 1
					fi
				fi
			else
				echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - VSI $vsi is SHUTOFF" "1"
				shutoff=1
				return
			fi
			# SSH test (only remote)
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Trying to ssh into VSI $vsi..." "1"
			ssh -T -q -i "$sshkeypath" "$vsi_user@$vsi_ip" exit
			if [ $? -eq 255 ]
			then
				abort "$(date +%Y-%m-%d_%H:%M:%S) - Unable to SSH to $vsi! Try STRTCPSVR *SSHD. Aborting..." 1
			fi
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - ssh into VSI $vsi succeeded..." "1"
			cmd="system 'WRKCFGSTS CFGTYPE(*DEV) CFGD(*ASP)'"
			iasp_output=$(ssh -T -i "$sshkeypath" "$vsi_user@$vsi_ip" "$cmd")
		fi
		###################################################################
		# COMMON BLOCK — PARSING iASP OUTPUT (LOCAL OR REMOTE)
		###################################################################
		iasp_name=$(echo "$iasp_output" | tail -n+4 | head -n-1 | awk '{print $1":"$3}')
		echo "" > "$iasp_names_file"
		for line in $iasp_name
		do
			line_status=$(echo "$line" | cut -d ":" -f2-)
			if [[ "$line_status" == "AVAILABLE" ]]
			then
				echo "$line" | cut -d: -f1 >> "$iasp_names_file"
			fi
		done
		iasp_names=$(cat "$iasp_names_file")
		if [[ -z "$iasp_names" ]]
		then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - VSI $vsi has no AVAILABLE iASPs... Moving on..." "1"
		else
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - VSI $vsi iASP Names: $iasp_names" "1"
		fi
	else
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Running in test mode, skipping get iASP name." "1"
		if [[ "$vsi_status" == "SHUTOFF" ]]
		then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - VSI $vsi is SHUTOFF" "1"
			shutoff=1
			return
		fi
	fi
}
####  END:FUNCTION - Check if VSI exists in secret file and Get VSI IP and iASP NAME if exists  ####

####  START:FUNCTION - Check if VSI exists in secret file and Get VSI IP and iASP NAME if exists  ####
check_locally_VSI_exists() {
	# Clear job log
	: > "$job_log"
	vsi_os=""
	# Case-insensitive check if VSI exists in JSON
	if jq -e --arg vsi "$vsi" 'any(.systems[]; (.name | ascii_downcase) == ($vsi | ascii_downcase))' "$bluexscrt" > /dev/null
	then
		# Get workspace short name (e.g., WSMAD2) for this VSI (case-insensitive)
		vsiwsshort=$(jq -r --arg vsi "$vsi" '.systems[]	| select((.name | ascii_downcase) == ($vsi | ascii_downcase)) | .workspace' "$bluexscrt")
		# Get OS category for this VSI (case-insensitive match on name). Only assigned
		# here, after existence is confirmed above - missing os field (pre-upgrade
		# .systems[] entries) falls back to ibmi, the only OS the tool ever stored
		# before this field existed.
		vsi_os=$(jq -r --arg vsi "$vsi" '.systems[] | select((.name | ascii_downcase) == ($vsi | ascii_downcase)) | (.os // "ibmi")' "$bluexscrt")
		if [[ "$vsi_os" == "other" ]]
		then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - WARNING: VSI $vsi has os=other (unclassified) - ASP flush will be skipped. If this is actually an IBM i LPAR, fix it with: bluexscrt_config_api.sh -addlpar $vsi <ip> <pvmid> <workspace> ibmi" "1"
		fi
		# Get workspace CRN for that short name
		shortnamecrn=$(jq -r --arg ws "$vsiwsshort" '.workspaces[$ws].crn' "$bluexscrt")
		# Call function that lists VSIs in that workspace (writes to $vsi_list_tmp)
		dc_vsi_list "$shortnamecrn"
		# Get the cloud VSI name from the list file (grep -wi já é case-insensitive)
		vsi_cloud_name=$(grep -wi "$vsi" "$vsi_list_tmp" | awk '{print $1}')
		# Get full workspace name directly from JSON
		full_ws_name=$(jq -r --arg ws "$vsiwsshort" '.workspaces[$ws].name' "$bluexscrt")
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - VSI $vsi_cloud_name was found in $full_ws_name..." "1"
		if [ "$flagj" -eq 0 ]
		then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - VSI to Capture: $vsi_cloud_name" "1"
			get_iASP_name
		fi	else
		echoscreen ""
		abort "   ### VSI $vsi not found in any of the workspaces available in $bluexscrt!" 1
	fi
}
####  END:FUNCTION - Check if VSI exists in secret file and Get VSI IP and iASP NAME if exists  ####

####  START:FUNCTION Flush ASPs and iASP Memory to Disk  ####
flush_asps() {
	if [ $test -eq 0 ]
	then
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Flushing Memory to Disk for SYSBAS..." "1"
		local_name=$(hostname -s 2>/dev/null)
		# If running locally on the same VSI, run system commands directly
		if [[ "$local_name" == "${vsi^^}" ]]
		then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Running locally on $vsi, executing SYSBAS flush without SSH..." "1"
			# Fix (1.18.1): capture the status BEFORE anything is piped. "$?" after a
			# pipeline is the LAST command's status - it was tee's, and tee always succeeds,
			# so the guard below could never fire. A flush that did not happen then looked
			# exactly like one that did, and the snapshot was taken anyway. POSIX capture
			# rather than PIPESTATUS, which is a bashism.
			flush_out=$(system "CHGASPACT ASPDEV(*SYSBAS) OPTION(*FRCWRT)" 2>&1)
			flush_rc=$?
			printf '%s\n' "$flush_out" | tee -a "$log_file"
			if [ "$flush_rc" -ne 0 ]
			then
				abort "$(date +%Y-%m-%d_%H:%M:%S) - CHGASPACT on *SYSBAS failed (rc=$flush_rc). The snapshot would capture disk the partition has not finished writing to. Aborting."
			fi
			if [[ -n "$iasp_names" ]]
			then
				for iasp_name in $iasp_names
				do
					echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Flushing Memory to Disk for $iasp_name ..." "1"
					# Fix (1.18.1): capture the status BEFORE anything is piped. "$?" after a
					# pipeline is the LAST command's status - it was tee's, and tee always succeeds,
					# so the guard below could never fire. A flush that did not happen then looked
					# exactly like one that did, and the snapshot was taken anyway. POSIX capture
					# rather than PIPESTATUS, which is a bashism.
					flush_out=$(system "CHGASPACT ASPDEV($iasp_name) OPTION(*FRCWRT)" 2>&1)
					flush_rc=$?
					printf '%s\n' "$flush_out" | tee -a "$log_file"
					if [ "$flush_rc" -ne 0 ]
					then
						abort "$(date +%Y-%m-%d_%H:%M:%S) - CHGASPACT on iASP $iasp_name failed (rc=$flush_rc). The snapshot would capture disk the partition has not finished writing to. Aborting."
					fi
				done
			fi
		else
			# Remote via SSH
			# Fix (1.18.1): capture the status BEFORE anything is piped. "$?" after a
			# pipeline is the LAST command's status - it was tee's, and tee always succeeds,
			# so the guard below could never fire. A flush that did not happen then looked
			# exactly like one that did, and the snapshot was taken anyway. POSIX capture
			# rather than PIPESTATUS, which is a bashism.
			flush_out=$(ssh -T -i "$sshkeypath" "$vsi_user@$vsi_ip" 'system "CHGASPACT ASPDEV(*SYSBAS) OPTION(*FRCWRT)"' 2>&1)
			flush_rc=$?
			printf '%s\n' "$flush_out" | tee -a "$log_file"
			if [ "$flush_rc" -ne 0 ]
			then
				abort "$(date +%Y-%m-%d_%H:%M:%S) - CHGASPACT on *SYSBAS failed (rc=$flush_rc). The snapshot would capture disk the partition has not finished writing to. Aborting."
			fi
			if [[ -n "$iasp_names" ]]
			then
				for iasp_name in $iasp_names
				do
					echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Flushing Memory to Disk for $iasp_name ..." "1"
					# Fix (1.18.1): capture the status BEFORE anything is piped. "$?" after a
					# pipeline is the LAST command's status - it was tee's, and tee always succeeds,
					# so the guard below could never fire. A flush that did not happen then looked
					# exactly like one that did, and the snapshot was taken anyway. POSIX capture
					# rather than PIPESTATUS, which is a bashism.
					flush_out=$(ssh -T -i "$sshkeypath" "$vsi_user@$vsi_ip" "system \"CHGASPACT ASPDEV($iasp_name) OPTION(*FRCWRT)\"" 2>&1)
					flush_rc=$?
					printf '%s\n' "$flush_out" | tee -a "$log_file"
					if [ "$flush_rc" -ne 0 ]
					then
						abort "$(date +%Y-%m-%d_%H:%M:%S) - CHGASPACT on iASP $iasp_name failed (rc=$flush_rc). The snapshot would capture disk the partition has not finished writing to. Aborting."
					fi
				done
			fi
		fi
	else
		# Test mode
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Simulating Flushing Memory to Disk for SYSBAS..." "1"
	fi
}
####  END:FUNCTION Flush ASPs and iASP Memory to Disk  ####

####  START:FUNCTION - Do the Snapshot Create  ####
do_snap_create() {
	if [[ "$vsi_os" == "ibmi" ]]
	then
		flush_asps
	else
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - VSI $vsi is $vsi_os - CHGASPACT not applicable, skipping ASP flush." "1"
	fi
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - == Executing Snapshot $snap_name of Instance $vsi with volumes $volumes_to_echo" "1"
	# Construir lista de volumeIDs (se tiveres indicado volumes; se não, o serviço decide)
	local json_ids=""
	if [[ -n "$volumes_to_snap" ]]
	then
		# Obter lista de volumes da VSI via API
		local vols_json
		vols_json=$(ins_vol_ls 2>>"$log_file")
		if [[ -z "$vols_json" ]]
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Could not list instance volumes via API. Check log above this line..." 1
		fi
		# volumes_to_snap é comma-separated de nomes ou IDs
		IFS=',' read -r -a snap_vols_array <<< "$volumes_to_snap"
		for vtoken in "${snap_vols_array[@]}"
		do
			local vtrim
			vtrim=$(echo "$vtoken" | xargs)
			[[ -z "$vtrim" ]] && continue
			# Match por volumeID OU por name
			local vol_id
			vol_id=$(echo "$vols_json" | jq -r --arg t "$vtrim" '
				.volumes[]? | select(.volumeID == $t or .name == $t) | .volumeID
			' 2>>"$log_file" | head -n1)
			if [[ -z "$vol_id" || "$vol_id" == "null" ]]
			then
				abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Volume '$vtrim' not found on VSI $vsi. Use exact Volume Name or Volume ID." 1
			fi
			json_ids="$json_ids\"$vol_id\","
		done
		# remover última vírgula
		json_ids="${json_ids%,}"
		if [[ -z "$json_ids" ]]
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - No valid volumes resolved from '$volumes_to_snap'." 1
		fi
	fi
	# Construir payload JSON (ACTIONS) só com name, description, volumeIDs
	ACTIONS="\"name\":\"$snap_name\""
	if [[ -n "$snap_description" ]]
	then
		ACTIONS="$ACTIONS,\"description\":\"$snap_description\""
	fi
	if [[ -n "$json_ids" ]]
	then
		ACTIONS="$ACTIONS,\"volumeIDs\":[${json_ids}]"
	fi
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - == Calling snapshots API (snap_cr) with payload: {$ACTIONS}" "1"
	# Chamada API para criar Snapshot
	local resp
	resp=$(snap_cr 2>>"$log_file")
	if [ $? -ne 0 ] || [[ -z "$resp" ]]
	then
		echo "$resp" >>"$log_file"
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Error calling snapshot create API. Check log above this line..." 1
	fi

	# Verificar se veio algum erro no JSON
	if echo "$resp" | jq -e '.error? // .errors? | length > 0' >/dev/null 2>&1
	then
		echo "$resp" | jq >>"$log_file"
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Snapshot creation returned error. Check log above this line..." 1
	fi

	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Waiting for Snapshot $snap_name to reach 100%..." "1"
	# Tentar obter o snapshotID a partir da resposta; se não vier, vamos buscá-lo à lista
	local snap_id
	snap_id=$(echo "$resp" | jq -r '.snapshotID // .id // empty' 2>/dev/null)
	if [[ -z "$snap_id" || "$snap_id" == "null" ]]
	then
		local snaps_json
		snaps_json=$(snap_ls 2>>"$log_file")
		snap_id=$(echo "$snaps_json" | jq -r --arg name "$snap_name" '.snapshots[]? | select(.name == $name) | .snapshotID' 2>>"$log_file" | head -n1)
	fi
	if [[ -z "$snap_id" || "$snap_id" == "null" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Could not retrieve snapshot ID for $snap_name. Check IBM Cloud portal / API." 1
	fi
	# Loop de monitorização do percentComplete
	local snap_percent=0
	local snap_percent_before=0
	while [ "$snap_percent" -lt 100 ]
	do
		sleep 10
		local status_json
		status_json=$(snap_ls 2>>"$log_file")
		if [ $? -ne 0 ] || [[ -z "$status_json" ]]
		then
			echo "$status_json" >>"$log_file"
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Error reading snapshot status from API." 1
		fi
		# Fix (1.18.1): a snapshot that has left the list yields nothing from select,
		# snap_percent became empty, the coercion below made it 0, and "while [ -lt 100 ]"
		# stayed true forever - an unbounded spin at 10s intervals, after flush_asps had
		# already run. do_snap_restore checks for exactly this (its "not found in list while
		# monitoring restore" abort); the create watch did not.
		snap_present=$(echo "$status_json" | jq -r --arg id "$snap_id" \
			'.snapshots[]? | select(.snapshotID == $id) | .snapshotID' 2>>"$log_file")
		if [ -z "$snap_present" ] || [ "$snap_present" = "null" ]
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Snapshot $snap_name (ID $snap_id) is no longer in the list; creation did not complete." 1
		fi
		snap_percent=$(echo "$status_json" | jq -r --arg id "$snap_id" '
			.snapshots[]? | select(.snapshotID == $id) | .percentComplete // 0
		' 2>>"$log_file")
		[[ "$snap_percent" =~ ^[0-9]+$ ]] || snap_percent=0
		if [ "$snap_percent" -ne "$snap_percent_before" ]
		then
			if [ "$snap_percent" -ge 100 ]
			then
				echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Snapshot $snap_name reached 100% - Done!" "1"
				break
			else
				echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Snapshot $snap_name at ${snap_percent}%." "1"
				snap_percent_before=$snap_percent
			fi
		fi
	done
}
####  END:FUNCTION - Do the Snapshot Create  ####

####  START:FUNCTION - Do the Snapshot Update  ####
do_snap_update() {
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - == Executing Snapshot $snap_name Update $new_name_echo $new_description_echo" "1"
	# Construir JSON ACTIONS com os campos a atualizar
	local actions=""
	if [[ -n "$snap_new_name" ]]; then
		actions="\"name\":\"$snap_new_name\""
	fi
	if [[ -n "$snap_new_description" ]]; then
		if [[ -n "$actions" ]]; then
			actions="$actions,\"description\":\"$snap_new_description\""
		else
			actions="\"description\":\"$snap_new_description\""
		fi
	fi
	if [[ -z "$actions" ]]; then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - INTERNAL ERROR - No fields to update for snapshot $snap_name (ACTIONS empty)." 1
	fi
	ACTIONS="$actions"
	if [[ -z "$SNAP_ID" ]]; then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - INTERNAL ERROR - SNAP_ID not set before do_snap_update." 1
	fi
	local resp
	resp=$(snap_upd 2>>"$log_file")
	if [ $? -ne 0 ] || [[ -z "$resp" ]]; then
		echo "$resp" >>"$log_file"
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Error calling snapshot update API. Check log above this line..." 1
	fi
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Snapshot $snap_name updated $new_name_echo $new_description_echo - Done!" "1"
}
####  END:FUNCTION - Do the Snapshot Update  ####

####  START:FUNCTION - Do the Snapshot Restore  ####
do_snap_restore() {
	# 1) Confirmar estado da VSI antes de fazer restore
	vsi_status=$(ins_get 2>>"$log_file" | jq -r '.status // empty' 2>>"$log_file")
	if [[ -z "$vsi_status" || "$vsi_status" == "null" ]]; then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Could not retrieve VSI status for $vsi (PVM_ID $PVM_ID). Aborting snapshot restore." 1
	fi
	# Regra: SÓ fazemos restore se estiver SHUTOFF
	if [[ "$vsi_status" != "SHUTOFF" ]]; then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - VSI $vsi is in status $vsi_status. Snapshot restore is only allowed when VSI is SHUTOFF." 1
	fi
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - VSI $vsi is in status: $vsi_status. Proceeding with snapshot restore..." "1"
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Searching Snapshot with name $snap_name for VSI $vsi (PVM_ID $PVM_ID) in current workspace..." "1"
	# 2) List snapshots in this workspace
	snaps_json=$(snap_ls 2>>"$log_file")
	if [[ -z "$snaps_json" ]]; then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Could not list snapshots in current workspace. Check log file $log_file." 1
	fi
	# 3) Encontrar snapshot por NOME + PVM_ID (para evitar confusões entre VSIs)
	SNAP_ID=$(
		echo "$snaps_json" | jq -r \
			--arg name "$snap_name" \
			--arg pvm "$PVM_ID" \
			'.snapshots // [] | .[] | select(.name == $name and .pvmInstanceID == $pvm) | .snapshotID' \
			2>>"$log_file" | head -n1
	)

	if [[ -z "$SNAP_ID" || "$SNAP_ID" == "null" ]]; then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Snapshot with name $snap_name for VSI $vsi (PVM_ID $PVM_ID) not found in this workspace." 1
	fi
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Snapshot $snap_name found with ID: $SNAP_ID" "1"
	# 4) Chamar API de restore
	# A API quer um bool em 'force', não uma string
	ACTIONS="\"force\": true"
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Calling Snapshot Restore API for VSI $vsi (PVM_ID $PVM_ID), Snapshot ID $SNAP_ID ..." "1"
	restore_output=$(snap_res 2>>"$log_file")
	ret=$?
	# Guardar sempre o output no log
	echo "$restore_output" >>"$log_file"
	# Se o curl falhar, já é erro
	if [ $ret -ne 0 ]; then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - curl error calling snapshot restore API. Check log file $log_file." 1
	fi

	# Confirmar que é JSON válido
	if ! echo "$restore_output" | jq . >/dev/null 2>&1; then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Snapshot restore API did not return valid JSON. Raw output logged above." 1
	fi

	# Verificar erros no JSON: .error/.errors/.code
	has_error_fields="no"
	if echo "$restore_output" | jq -e '.error? // .errors? | length > 0' >/dev/null 2>&1; then
		has_error_fields="yes"
	fi
	err_code=$(echo "$restore_output" | jq -r '.code // empty' 2>>"$log_file")
	err_msg=$(echo "$restore_output" | jq -r '.message // empty' 2>>"$log_file")
	if [[ "$has_error_fields" == "yes" ]] || { [[ -n "$err_code" ]] && [[ "$err_code" != "0" ]] && [[ "$err_code" != "200" ]]; }; then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Snapshot restore API returned an error (code=$err_code, message=\"$err_msg\"). Check log file $log_file." 1
	fi
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Snapshot restore request accepted by API. Starting monitoring..." "1"
	# 5) Monitorizar progresso do restore (sem timeout, até 100%)
	local snap_status=""
	local snap_percent=0
	local snap_percent_before=-1
	while true
	do
		snaps_json=$(snap_ls 2>>"$log_file")
		if [[ -z "$snaps_json" ]]
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Error reading snapshot status during restore monitoring." 1
		fi
		# Ler status e percentComplete do snapshot específico
		snap_status=$(echo "$snaps_json" | jq -r --arg id "$SNAP_ID" '.snapshots // [] | .[] | select(.snapshotID == $id) | .status // empty' 2>>"$log_file")

		snap_percent=$(echo "$snaps_json" | jq -r --arg id "$SNAP_ID" '.snapshots // [] | .[] | select(.snapshotID == $id) | .percentComplete // 0' 2>>"$log_file")
		if [[ -z "$snap_status" || "$snap_status" == "null" ]]
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Snapshot ID $SNAP_ID not found in list while monitoring restore." 1
		fi
		[[ "$snap_percent" =~ ^[0-9]+$ ]] || snap_percent=0
		# Só escreve no log quando há alteração de percentagem
		if [ "$snap_percent" -ne "$snap_percent_before" ]
		then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Snapshot $snap_name restore status=$snap_status, progress=${snap_percent}%." "1"
			snap_percent_before=$snap_percent
		fi
		# Condição de fim: percent >= 100
		if [[ "$snap_percent" -ge 100 ]]
		then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Snapshot $snap_name restore completed (status=$snap_status, ${snap_percent}%)." "1"
			break
		fi
		sleep 30
	done
	abort "$(date +%Y-%m-%d_%H:%M:%S) - === Snapshot Restore completed successfully for Snapshot $snap_name (ID $SNAP_ID) on VSI $vsi (PVM_ID $PVM_ID). ==="
	abort "$(date +%Y-%m-%d_%H:%M:%S) - === Snapshot Restore completed successfully for Snapshot $snap_name (ID $SNAP_ID) on VSI $vsi (PVM_ID $PVM_ID). ==="
}
####  END:FUNCTION - Do the Snapshot Restore  ####


####  START:FUNCTION - Do the Snapshot Delete  ####
do_snap_delete() {
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - === Starting Snapshot Delete for snapshot named '$snap_name'!" "1"
	snaps_json=$(snap_ls 2>>"$log_file")
	# Find snapshot ID by name (exact match)
	snap_id=$(echo "$snaps_json" | jq -r --arg name "$snap_name" '.snapshots[]? | select(.name == $name) | .snapshotID ')
	if [[ -z "$snap_id" || "$snap_id" == "null" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Snapshot '$snap_name' does not exist. Choose another name or use -snapcr to create one." 1
	fi
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Snapshot '$snap_name' found with ID: $snap_id" "1"
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Executing delete for snapshot ID $snap_id ..." "1"
	SNAP_ID=$snap_id
	resp=$(snap_del 2>>"$log_file")
	# Check API response
	if echo "$resp" | grep -q '"error"'
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED deleting snapshot '$snap_name'. API error: $resp" 1
	fi
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Snapshot '$snap_name' delete request sent successfully." "1"
	# Optional: Poll snapshot list until it disappears
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Waiting for snapshot deletion to complete..." "1"
	while :
	do
		sleep 5
		still_exists=$(snap_ls 2>>"$log_file" | jq -e --arg id "$snap_id" '.snapshots[]? | select(.snapshotID == $id)' >/dev/null 2>&1 ; echo $?)
		if [[ $still_exists -ne 0 ]]; then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Snapshot '$snap_name' deleted successfully!" "1"
			abort "$(date +%Y-%m-%d_%H:%M:%S) - === Successfully finished - Snapshot $snap_name Deleted!"
		fi
	done
	abort "$(date +%Y-%m-%d_%H:%M:%S) - WARNING: Snapshot delete requested but snapshot still appears in list. Check IBM Cloud." 1
}
####  END:FUNCTION - Do the Snapshot Delete  ####


####  START:FUNCTION - Volume clone failure and time bound  ####
# (1.18.8) Usage: vclone_failure "$clone_json"  -> prints the failure reason, or nothing.
# A volumes-clone object is failed when its status is "failed" or it carries a failureMessage
# (the API's own field for the reason a clone request failed). Case-insensitive on status.
vclone_failure() {
	printf '%s' "$1" | jq -r 'if ((.status // "") | ascii_downcase) == "failed" or ((.failureMessage // "") != "") then (.failureMessage // "status failed, no reason given") else empty end' 2>/dev/null
}
# (1.18.8) Usage: vclone_time_left "$started_epoch" "what" -> aborts once the bound is passed.
# Same bound as wait_for_job: BLUEXPORT_JOB_MAX_SECS, default 24 hours. The clone keeps running.
vclone_time_left() {
	local max_secs="${BLUEXPORT_JOB_MAX_SECS:-86400}"
	if [ $(( $(date +%s) - $1 )) -ge "$max_secs" ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - $2 has not finished after $max_secs seconds. Monitoring stopped; the clone itself CONTINUES in IBM Cloud (limit BLUEXPORT_JOB_MAX_SECS)." 1
	fi
}
####  END:FUNCTION - Volume clone failure and time bound  ####
####  START:FUNCTION - Do the Volume Clone Execute ####
do_volume_clone_execute() {
	# Flush ASPs na origem antes de executar o clone (IBM i only)
	if [[ $shutoff == "0" ]]
	then
		if [[ "$vsi_os" == "ibmi" ]]
		then
			flush_asps
		else
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - VSI $vsi is $vsi_os - CHGASPACT not applicable, skipping ASP flush." "1"
		fi
	fi
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - == Executing Volume Clone with name $vclone_name ..." "1"
	if [[ -z "$vclone_id" ]]; then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - vclone_id not set before do_volume_clone_execute." 1
	fi
	VOL_CLONE_ID="$vclone_id"
	ACTIONS="\"name\":\"$base_name\",\"rollbackPrepare\": $rollback,\"targetReplicationEnabled\": $replication, \"targetStorageTier\":\"$target_tier\""
	# Chamada API para execute
	local resp_ex
	resp_ex=$(vol_cl_ex 2>>"$log_file")
	rc=$?
	# 1) curl / command failure OR empty body
	if [[ $rc -ne 0 || -z "$resp_ex" ]]
	then
		echo "$resp_ex" >>"$log_file"
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Error executing Volume Clone $vclone_name (API call failed or empty response)." 1
	fi
	# 2) response must be valid JSON (otherwise jq will blow up later)
	if ! echo "$resp_ex" | jq . >/dev/null 2>&1
	then
		echo "$resp_ex" >>"$log_file"
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Volume Clone execute returned non-JSON response. Check log for raw payload." 1
	fi
	# 3) if API returned an error payload (e.g., {"code":400,"message":"..."}) abort immediately
	api_code=$(echo "$resp_ex" | jq -r '.code // empty' 2>>"$log_file")
	api_msg=$(echo "$resp_ex" | jq -r '.message // .error // empty' 2>>"$log_file")

	if [[ -n "$api_code" && "$api_code" != "null" ]]
	then
		echo "$resp_ex" >>"$log_file"
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Volume Clone execute API error (code=$api_code): $api_msg" 1
	fi

	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Waiting for Volume Clone $vclone_name execution to finish..." "1"
	local vcloneex_percent=0
	local vcloneex_percent_before=0
	local vcloneex_started
	vcloneex_started=$(date +%s)
	while :
	do
		sleep 5
		vclone_time_left "$vcloneex_started" "Volume Clone $vclone_name execution"
		local status_json
		status_json=$(vol_cl_get 2>>"$log_file")
		if [ $? -ne 0 ] || [ -z "$status_json" ]
		then
			echo "$status_json" >>"$log_file"
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Error getting status for Volume Clone execution $vclone_name." 1
		fi
		# (1.18.8) A failed clone used to be polled until percentComplete reached 100, i.e. forever.
		local vclone_fail_reason
		vclone_fail_reason=$(vclone_failure "$status_json")
		if [ -n "$vclone_fail_reason" ]
		then
			echo "$status_json" >>"$log_file"
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Volume Clone $vclone_name execution failed: $vclone_fail_reason" 1
		fi
		vcloneex_percent=$(echo "$status_json" | jq -r '.percentComplete // .status.percentComplete // 0' 2>/dev/null)
		[[ "$vcloneex_percent" =~ ^[0-9]+$ ]] || vcloneex_percent=0
		if [ "$vcloneex_percent" -ne "$vcloneex_percent_before" ]
		then
			if [ "$vcloneex_percent" -ge 100 ]
			then
				echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Volume Clone $vclone_name Done and ready to be used!" "1"
				break
			else
				echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Volume Clone $vclone_name execution at ${vcloneex_percent}%." "1"
				vcloneex_percent_before=$vcloneex_percent
			fi
		fi
	done
}
####  END:FUNCTION -  Do the Volume Clone Execute ####

####  START:FUNCTION - Do the Volume Clone Start ####
do_volume_clone_start() {
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - == Starting Volume Clone with name $vclone_name ..." "1"
	# Garantir que temos o ID do clone na variável global
	if [[ -z "$vclone_id" ]]; then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - vclone_id not set before do_volume_clone_start." 1
	fi
	VOL_CLONE_ID="$vclone_id"
	local resp_start
	resp_start=$(vol_cl_st 2>>"$log_file")
	if [ $? -ne 0 ]
	then
		echo "$resp_start" >>"$log_file"
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Error starting Volume Clone $vclone_name (API call failed)." 1
	fi
	# (1.19.0) The start POST only asks the API to begin the state transition; checking
	# status once, immediately after, could catch it still mid-transition and fail a
	# start that was actually fine. Poll every 5s, the same failure/time-bound helpers
	# do_volume_clone_execute already uses, until it actually reaches action=start and
	# status=available.
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Waiting for Volume Clone $vclone_name to reach action=start/status=available..." "1"
	local vclonest_started
	vclonest_started=$(date +%s)
	local status_json vclone_start_action vclone_start_status vclone_fail_reason
	while :
	do
		sleep 5
		vclone_time_left "$vclonest_started" "Volume Clone $vclone_name start"
		status_json=$(vol_cl_get 2>>"$log_file")
		if [ $? -ne 0 ] || [ -z "$status_json" ]
		then
			echo "$status_json" >>"$log_file"
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Error reading status after start for Volume Clone $vclone_name." 1
		fi
		vclone_fail_reason=$(vclone_failure "$status_json")
		if [ -n "$vclone_fail_reason" ]
		then
			echo "$status_json" >>"$log_file"
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Volume Clone $vclone_name start failed: $vclone_fail_reason" 1
		fi
		vclone_start_action=$(echo "$status_json" | jq -r '.action // .status.action // empty')
		vclone_start_status=$(echo "$status_json" | jq -r '.status // .state // .status.state // empty')
		if [[ "$vclone_start_action" == "start" && "$vclone_start_status" == "available" ]]
		then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Volume Clone $vclone_name Started and ready to execute..." "1"
			break
		fi
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Volume Clone $vclone_name not ready yet (action=$vclone_start_action status=$vclone_start_status). Waiting..." "1"
	done
}
####  END:FUNCTION -  Do the Volume Clone Start ####

####  START:FUNCTION - Do the Volume Clone  ####
do_volume_clone() {
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - == Creating Volume Clone Request with name $vclone_name ..." "1"
	# volumes_to_clone é uma lista comma-separated de IDs (id1,id2,...)
	IFS=',' read -r -a vc_array <<< "$volumes_to_clone"
	# Construir JSON array de IDs: ["id1","id2",...]
	json_ids=""
	for vid in "${vc_array[@]}"
	do
		# trim básico de espaços, por segurança
		vid_trimmed=$(echo "$vid" | xargs)
		[ -z "$vid_trimmed" ] && continue
		json_ids="$json_ids\"$vid_trimmed\","
	done
	# remover última vírgula
	json_ids="${json_ids%,}"
	ACTIONS="\"name\":\"$vclone_name\",\"volumeIDs\":[${json_ids}]"
	output=$(vol_cl_cr 2>>"$log_file")
	ret=$?
	if echo "$output" | jq -e '.error? | length > 0' >/dev/null
	then
		echo "$output" | jq | tee -a "$log_file"
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Check message above" "1"
	fi
	if [ $ret -eq 0 ]
	then
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Waiting for Volume Clone Request $vclone_name creation to finish..." "1"
		vclone_id=$(vol_cl_ls 2>>"$log_file" | jq -r --arg name "$vclone_name" '.volumesClone[]? | select(.name == $name) | .volumesCloneID' | head -n1)
		if [[ -z "$vclone_id" ]]
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Could not retrieve Volume Clone Request ID for $vclone_name. Check the log above this line..." 1
		fi
		vclone_percent=0
		local vclone_started vclone_obj vclone_fail_reason
		vclone_started=$(date +%s)
		while [ "$vclone_percent" -lt 100 ]
		do
			vclone_percent_before=$vclone_percent
			sleep 5
			vclone_time_left "$vclone_started" "Volume Clone Request $vclone_name creation"
			vclone_obj=$(vol_cl_ls 2>>"$log_file" | jq -c --arg id "$vclone_id" '.volumesClone[]? | select(.volumesCloneID == $id)')
			# (1.18.8) A failed request used to be polled forever; stop and say why.
			vclone_fail_reason=$(vclone_failure "$vclone_obj")
			if [ -n "$vclone_fail_reason" ]
			then
				echo "$vclone_obj" >>"$log_file"
				abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Volume Clone Request $vclone_name failed: $vclone_fail_reason" 1
			fi
			vclone_percent=$(printf '%s' "$vclone_obj" | jq -r '.percentComplete // 0' 2>/dev/null)
			# Garantir valor numérico
			[[ "$vclone_percent" =~ ^[0-9]+$ ]] || vclone_percent=0
			if [ "$vclone_percent" != "$vclone_percent_before" ]
			then
				if [ "$vclone_percent" -eq 100 ]
				then
					echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Volume Clone Request $vclone_name Done!" "1"
				else
					echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Volume Clone Request $vclone_name creation at $vclone_percent%" "1"
				fi
			fi
		done
	else
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Error creating Volume Clone Request $vclone_name (API call failed). See $log_file for details." 1
	fi
}
####  END:FUNCTION -  Do the Volume Clone ####

####  START:FUNCTION  Check if VSI ID exists in bluexscrt file  ####
vsi_id_bluexscrt() {
	# Match VSI name in bluexscrt.json ignoring case (IBM i sends upper-case)
	vsi_ip=$(jq -r --arg name "$vsi" '.systems[] | select((.name | ascii_downcase) == ($name | ascii_downcase)) | .ip' "$bluexscrt")
	vsi_id=$(jq -r --arg name "$vsi" '.systems[] | select((.name | ascii_downcase) == ($name | ascii_downcase)) | .pvmInstanceID' "$bluexscrt")
	PVM_ID="$vsi_id"

	if [[ -z "$vsi_id" || "$vsi_id" == "null" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - VSI ID missing or VSI Name '$vsi' not found in $bluexscrt. Please add it to the JSON or check the name." 1
	fi
#	vsi_ip=$(jq -r --arg name "$vsi" '.systems[] | select(.name == $name) | .ip' "$bluexscrt")
#	vsi_id=$(jq -r --arg name "$vsi" '.systems[] | select(.name == $name) | .pvmInstanceID' "$bluexscrt")
#	PVM_ID="$vsi_id"
#	if [[ -z "$vsi_id" || "$vsi_id" == "null" ]]
#	then
#		abort "$(date +%Y-%m-%d_%H:%M:%S) - VSI ID missing or VSI Name '$vsi' not found in $bluexscrt. Please add it to the JSON..."
#	fi
#	# Retrieve workspace key, example: "WSMAD2"
#	vsi_ws=$(jq -r --arg name "$vsi" '.systems[] | select(.name == $name) | .workspace' "$bluexscrt")
#	# Retrieve workspace ID using the workspace key
#	vsi_ws_id=$(jq -r --arg ws "$vsi_ws" '.workspaces[$ws].id' "$bluexscrt")
}
####  END:FUNCTION  Check if VSI ID exists in bluexscrt file  ####

####  START:FUNCTION  Change Instance Volumes Tier  ####
vchtier() {
	if [[ -z "$volumes" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - There are no volumes with any of these words \"${volchtier_names[*]}\" in instance $vsi_cloud_name" 1
	fi
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Volume IDs to be changed to tier $tier: $volumes" "1"
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Volume names to be changed to tier $tier: $volumes_name" "1"
	volumes_ids=$(echo "$volumes" | sed 's/,/ /g')
	: > "$vol_ch_tier"
	failed_vol=""
	same_tier=0
	api_error=0
	for vol in $volumes_ids
	do
		vol_name=$(awk -v v="$vol" '$1 == v {print $2}' "$volumes_file")
		VOL_ID="$vol"
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Changing volume $vol_name with Volume ID $vol to tier $tier" "1"
		ACTIONS="\"targetStorageTier\": \"$tier\""
		# (1.19.0) The call's own HTTP status decides success, not a grep for "Failed"/
		# "Performing" in the accumulated JSON (which never matched real API output and
		# so never fired) - vol_act's status used to be discarded entirely.
		resp_raw=$(vol_act_status 2>&1)
		http_code="${resp_raw##*$'\n'}"
		resp="${resp_raw%$'\n'*}"
		printf '%s\n' "$resp" | tee -a "$log_file" >/dev/null
		echo "$resp" > "$vol_failed_tst"
		if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]
		then
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Volume $vol_name ($vol) changed to tier $tier." "1"
		elif echo "$resp" | grep -q "current storage tier"
		then
			# Already at the requested tier - not an error.
			same_tier=1
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Volume $vol_name ($vol) is already in tier $tier, no change required." "1"
		else
			api_error=1
			failed_vol="$failed_vol $vol"
			err_msg=$(printf '%s' "$resp" | jq -r '.description // .message // .error // empty' 2>/dev/null)
			echo "$resp" >> "$vol_ch_tier"
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - FAILED changing volume $vol_name ($vol) to tier $tier (HTTP $http_code): ${err_msg:-$resp}" "1"
		fi
	done
	if [[ -n "$failed_vol" || $api_error -ne 0 ]]
	then
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Some volumes failed to change tier!" "1"
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Try changing the tier manually with the following commands..." "1"
		for vol in $failed_vol
		do
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - vol_act for volume ID: $vol change to tier $tier" "1"
		done
		abort "`date +%Y-%m-%d_%H:%M:%S` - Tier change finished, but there were errors! Please check the log above..." 1
	fi
	if [ $same_tier -eq 1 ]
	then
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Some volumes were already in tier $tier, no action done on those volumes!" "1"
	fi
	abort "`date +%Y-%m-%d_%H:%M:%S` - Tier change finished successfully!"
}
####  END:FUNCTION  Change Instance Volumes Tier  ####

####  START:FUNCTION COS Head Bucket  ####
# HEAD request for a bucket. Logs raw headers to $log_file.
cos_head_bucket() {
	local bucket_name="$1"

	curl -sI "https://s3.$REGION.cloud-object-storage.appdomain.cloud/$bucket_name" \
		-H "$header_auth" 2>>"$log_file" | tee -a "$log_file"
}
####  END:FUNCTION COS Head Bucket  ####

####  START:FUNCTION COS Head Object  ####
# HEAD request for an object. Logs raw headers to $log_file.
# Sets globals:
#   COS_OBJ_STORAGE_CLASS
#   COS_OBJ_RESTORE_HEADER
cos_head_object() {
	local bucket_name="$1"
	local object_key="$2"
	local head_out

	COS_OBJ_STORAGE_CLASS=""
	COS_OBJ_RESTORE_HEADER=""

	head_out=$(curl -sI "https://s3.$REGION.cloud-object-storage.appdomain.cloud/$bucket_name/$object_key" \
		-H "$header_auth" 2>>"$log_file" | tee -a "$log_file")

	COS_OBJ_STORAGE_CLASS=$(echo "$head_out" | tr -d '\r' | grep -i '^x-amz-storage-class:' | head -n 1 | cut -d':' -f2- | sed 's/^[[:space:]]*//')
	COS_OBJ_RESTORE_HEADER=$(echo "$head_out" | tr -d '\r' | grep -i '^x-amz-restore:'       | head -n 1 | cut -d':' -f2- | sed 's/^[[:space:]]*//')

	echo "$head_out"
}
####  END:FUNCTION COS Head Object  ####

####  START:FUNCTION  Resolve COS Bucket Region  ####
# Tries to determine the correct COS S3 endpoint region for a given bucket.
# If it cannot be determined, it keeps current REGION (usually loaded from secrets).
cos_resolve_bucket_region() {
	local bucket_name="$1"
	local detected_region=""
	local head_out http_code line location_hdr

	# If REGION already set and bucket works there, keep it (fast path)
	if [[ -n "$REGION" ]]
	then
		head_out=$(curl -sI "https://s3.$REGION.cloud-object-storage.appdomain.cloud/$bucket_name" -H "$header_auth" 2>>"$log_file" | tee -a "$log_file")
		http_code=$(echo "$head_out" | awk 'NR==1{print $2}')
		# If we get a response (200/403/301), attempt to read x-amz-bucket-region
		detected_region=$(echo "$head_out" | awk -F': ' 'tolower($1)=="x-amz-bucket-region"{print $2}' | tr -d '\r')
		if [[ -n "$detected_region" ]]
		then
			REGION="$detected_region"
			return 0
		fi
		# If not present but request succeeded in this REGION, accept it
		if [[ "$http_code" == "200" || "$http_code" == "403" ]]
		then
			return 0
		fi
	fi

	# Otherwise, brute-force common COS regions (cheap and reliable)
	for r in eu-de eu-gb us-south us-east jp-tok au-syd br-sao ca-tor
	do
		head_out=$(curl -sI "https://s3.$r.cloud-object-storage.appdomain.cloud/$bucket_name" -H "$header_auth" 2>>"$log_file" | tee -a "$log_file")
		http_code=$(echo "$head_out" | awk 'NR==1{print $2}')
		detected_region=$(echo "$head_out" | awk -F': ' 'tolower($1)=="x-amz-bucket-region"{print $2}' | tr -d '\r')
		if [[ -n "$detected_region" ]]
		then
			REGION="$detected_region"
			return 0
		fi
		# Sometimes there is no x-amz-bucket-region, but 200/403 indicates bucket exists on that endpoint
		if [[ "$http_code" == "200" || "$http_code" == "403" ]]
		then
			REGION="$r"
			return 0
		fi
		# If redirected, try to parse region from Location
		location_hdr=$(echo "$head_out" | awk -F': ' 'tolower($1)=="location"{print $2}' | tr -d '\r')
		if [[ "$http_code" == "301" && -n "$location_hdr" ]]
		then
			# Extract 's3.<region>.cloud-object-storage' from Location if present
			detected_region=$(echo "$location_hdr" | sed -n 's#.*s3\.\([a-z0-9-]*\)\.cloud-object-storage.*#\1#p')
			if [[ -n "$detected_region" ]]
			then
				REGION="$detected_region"
				return 0
			fi
		fi
	done

	return 1
}
####  END:FUNCTION  Resolve COS Bucket Region  ####

####  START:FUNCTION - Read a DELETE answer whose last line is the HTTP status  ####
# (1.18.6) Usage: delete_check "$raw_output" "what was being deleted"
# Sets delete_http and delete_body; returns 0 on a 2xx with no error payload, 1 otherwise,
# with delete_err holding the API's message. POSIX-safe parameter expansion only.
delete_check() {
	local raw="$1" what="$2"
	delete_http="${raw##*$'\n'}"
	delete_body="${raw%$'\n'*}"
	[ "$delete_body" = "$raw" ] && delete_body=""
	delete_err=""
	case "$delete_http" in
		2[0-9][0-9]) ;;
		*)
			delete_err="HTTP ${delete_http:-unknown}"
			;;
	esac
	if printf '%s' "$delete_body" | grep -q "<Error>"
	then
		delete_err="$(printf '%s' "$delete_body" | sed -n 's/.*<Code>\([^<]*\)<\/Code>.*/\1/p' | head -n1) $(printf '%s' "$delete_body" | sed -n 's/.*<Message>\([^<]*\)<\/Message>.*/\1/p' | head -n1)"
	elif printf '%s' "$delete_body" | jq -e '.code? != null or .error? != null' >/dev/null 2>&1
	then
		delete_err=$(printf '%s' "$delete_body" | jq -r '.message // .error // .description // "Unknown error"' 2>/dev/null)
	fi
	if [ -n "$delete_err" ]
	then
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Delete of $what was refused: $delete_err" "1"
		return 1
	fi
	return 0
}
####  END:FUNCTION - Read a DELETE answer  ####

####  START:FUNCTION  Restore object from Archive to COS Bucket  ####
do_object_restore_from_archive() {
	local bucket_name object_key days archive_type
	bucket_name="$1"
	object_key="$2"
	days="$3"
	archive_type="$4"

	# Defaults
	if [[ -z "$days" ]]
	then
		days=3
	fi
	if [[ -z "$archive_type" ]]
	then
		archive_type="Accelerated"
	fi

	# Validate DAYS numeric
	if ! echo "$days" | grep -Eq '^[0-9]+$'
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - DAYS must be a number (received: $days)." 1
	fi

	# Normalize ARCHIVE_TYPE (Bulk|Accelerated)
	archive_type=$(echo "$archive_type" | tr '[:upper:]' '[:lower:]')
	if [[ "$archive_type" == "bulk" ]]
	then
		archive_type="Bulk"
	elif [[ "$archive_type" == "accelerated" ]]
	then
		archive_type="Accelerated"
	else
		abort "$(date +%Y-%m-%d_%H:%M:%S) - ARCHIVE_TYPE must be Bulk or Accelerated (received: $4)." 1
	fi

	# Resolve bucket region (best effort). Start with configured region from secrets.
	REGION="$region"
	if cos_resolve_bucket_region "$bucket_name"
	then
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Using COS region '$REGION' for bucket '$bucket_name'." "1"
	else
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - WARNING - Could not auto-detect COS region for bucket '$bucket_name'. Using configured region '$REGION'." "1"
	fi

	# 1) Check bucket exists (HEAD bucket)
	local bucket_hdrs bucket_code
	bucket_hdrs=$(cos_head_bucket "$bucket_name" "$REGION" 2>>"$log_file")
	bucket_code=$(echo "$bucket_hdrs" | awk 'NR==1{print $2}')
	if [[ "$bucket_code" == "404" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Bucket '$bucket_name' does not exist (HEAD returned 404)." 1
	fi
	if [[ "$bucket_code" == "403" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Access denied when accessing bucket '$bucket_name' (HEAD returned 403). Check COS credentials/policies." 1
	fi
	if [[ -z "$bucket_code" || "$bucket_code" != "200" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Unexpected response when checking bucket '$bucket_name' (HTTP $bucket_code). Check connectivity/credentials/region." 1
	fi

	# 2) Check object exists (HEAD object)
	local obj_hdrs obj_code
	obj_hdrs=$(cos_head_object "$bucket_name" "$object_key" "$REGION" 2>>"$log_file")
	obj_code=$(echo "$obj_hdrs" | awk 'NR==1{print $2}')
	if [[ "$obj_code" == "404" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Object '$object_key' does not exist in bucket '$bucket_name' (HEAD returned 404)." 1
	fi
	if [[ "$obj_code" == "403" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Access denied when accessing object '$object_key' in bucket '$bucket_name' (HEAD returned 403)." 1
	fi
	if [[ -z "$obj_code" || "$obj_code" != "200" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Unexpected response when checking object '$object_key' (HTTP $obj_code)." 1
	fi

	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Object storage class detected: ${COS_OBJ_STORAGE_CLASS:-UNKNOWN}" "1"
	if [[ -n "$COS_OBJ_RESTORE_HEADER" ]]
	then
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Object restore header: $COS_OBJ_RESTORE_HEADER" "1"
	fi

	# 3) Build XML actions
	ACTIONS="<RestoreRequest><Days>$days</Days><GlacierJobParameters><Tier>$archive_type</Tier></GlacierJobParameters></RestoreRequest>"

	# 4) Submit restore request
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - === Starting restore request for object '$object_key' in bucket '$bucket_name' (Days=$days, Tier=$archive_type) ===" "1"
	BUCKET="$bucket_name"
	OBJECT="$object_key"
	resp=$(cos_rest_arch 2>>"$log_file")
	# resp already logged by cos_rest_arch (tee)
	if [[ -z "$resp" ]]
	then
		# Successful restore is often empty body (200 OK). We still log headers in $log_file via tee.
		# (1.18.6) Exit 0: abort's second argument is the EXIT CODE, and this line used to pass
		# "1" to it, so every successful restore ended the script as a failure.
		abort "$(date +%Y-%m-%d_%H:%M:%S) - SUCCESS - Restore request submitted (empty body). Check restore status with HEAD (x-amz-restore) or in COS UI."
	fi

	if echo "$resp" | grep -q "<Error>"
	then
		local err_code err_msg
		# (1.18.6) sed, not grep -P: PCRE grep is not a given on every PASE.
		err_code=$(printf '%s' "$resp" | sed -n 's/.*<Code>\([^<]*\)<\/Code>.*/\1/p' | head -n1)
		err_msg=$(printf '%s' "$resp" | sed -n 's/.*<Message>\([^<]*\)<\/Message>.*/\1/p' | head -n1)

		if [[ "$err_code" == "RestoreAlreadyInProgress" ]]
		then
			# A restore already under way is information, not a failure: exit 0.
			abort "$(date +%Y-%m-%d_%H:%M:%S) - INFO - Restore already in progress for '$object_key' in bucket '$bucket_name'."
		fi
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Restore request returned error: ${err_code:-Unknown} ${err_msg:-Unknown}" 1
	fi

	# Otherwise, just log the response and exit OK
	abort "$(date +%Y-%m-%d_%H:%M:%S) - Restore request response: $resp"
}
####  END:FUNCTION  Restore object from Archive to COS Bucket  ####

####  START:FUNCTION  Main GRS function: create VG in source and onboard aux volumes in target  ####
create_grs() {
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - === Starting GRS configuration between source VSI $source_vsi and target VSI $target_vsi (VG: $vg_name) ===" "1"
	####################################
	# 1. SOURCE WORKSPACE / SOURCE VSI #
	####################################
	# Restaurar contexto da workspace/source VSI
	base_url="$source_base_url"
	CRN="$source_ws_crn"
	CLOUD_INSTANCE_ID="$source_CLOUD_INSTANCE_ID"
	PVM_ID="$source_PVM_ID"
	# 2.3 – Obter volumes associados ao SOURCE_VSI
	vol_ids=$(ins_vol_ls | jq -r '.volumes[]? | .volumeID' 2>>"$log_file")
	if [[ -z "$vol_ids" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - No volumes attached to source VSI $source_vsi. Aborting GRS creation." 1
	fi
	vol_count=$(echo "$vol_ids" | wc -w)
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Source VSI $source_vsi has $vol_count attached volumes." "1"
	# 2.4 – Garantir que todos os volumes estão com replicationEnabled=true
	chk_vol_rep
	# 2.4 (cont.) – Assegurar consistent_copying antes de criar o VG
	chk_vol_mirror
	# 2.5 – Criar Volume Group no SOURCE
	# Construir JSON array de volumeIDs sem quebras de linha
	json_vol_ids=""
	for vid in $vol_ids
	do
		json_vol_ids="$json_vol_ids\"$vid\","
	done
	# remover última vírgula
	json_vol_ids="${json_vol_ids%,}"
	ACTIONS="\"name\":\"$vg_name\",\"volumeIDs\":[${json_vol_ids}]"
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Creating Volume Group $vg_name in source workspace with volumeIDs: [${json_vol_ids}]..." "1"
	resp_vg=$(vg_cr_status 2>>"$log_file")
	grs_check_write "$resp_vg" "creating Volume Group $vg_name"
	# Confirmar ID do VG
	VOLUME_GROUP_ID=$(vg_ls | jq -r --arg vg_name "$vg_name" '.volumeGroups[]? | select(.name == $vg_name) | .id' 2>>"$log_file")
	if [[ -z "$VOLUME_GROUP_ID" || "$VOLUME_GROUP_ID" == "null" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Could not find Volume Group ID for $vg_name after creation." 1
	fi
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Volume Group $vg_name created with ID $VOLUME_GROUP_ID." "1"
	# 2.6 / 2.8 – Esperar VG estabilizar e ter TODOS os aux volumes
	max_wait_loops=30          # ~30 minutos se usarmos sleep 60
	loop=0
	while true
	do
		vg_details=$(vg_sd 2>>"$log_file")
		vg_state=$(echo "$vg_details"   | jq -r '.state // "unknown"'    2>>"$log_file")
		vg_numvols=$(echo "$vg_details" | jq -r '.numOfvols // 0'        2>>"$log_file")
		auxvol_names=$(vg_rcr 2>>"$log_file" | jq -r '.remoteCopyRelationships[]? | select(.primaryRole=="master") | .auxVolumeName')
		aux_count=$(echo "$auxvol_names" | wc -w | awk '{print $1}')
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - VG $vg_name state: $vg_state - numOfvols=$vg_numvols - auxVolumes=$aux_count/$vol_count" "1"
		if [[ "$aux_count" -eq "$vol_count" && "$aux_count" -gt 0 ]]
		then
			# OK – já temos todos os aux volumes
			break
		fi
		loop=$((loop + 1))
		if (( loop >= max_wait_loops ))
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` - VG $vg_name did not reach expected aux volume count ($vol_count) after $max_wait_loops minutes. Aborting." 1
		fi

		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Waiting for VG $vg_name aux volumes to match source count... Sleeping 60 seconds..." "1"
		sleep 60
	done
	if [[ -z "$auxvol_names" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - No auxiliary volumes found in remote-copy relationships for $vg_name after waiting. Aborting." 1
	fi
	auxvolnames=$(echo $auxvol_names | tr ' ' ',')
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Auxiliary volumes on target storage: $auxvol_names" "1"
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Found $aux_count auxiliary volumes for VG $vg_name." "1"
	# 2.7 – Boot volume aux name (apenas logging)
	bootvol_auxname=$(ins_vol_ls 2>>"$log_file" | jq -r '.volumes[]? | "\(.bootable) \(.auxVolumeName) \(.name)"' \
		| grep "$vol_com_name" | grep true | awk '{print $2}')
	if [[ -n "$bootvol_auxname" ]]
	then
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Boot auxiliary volume: $bootvol_auxname" "1"
	fi
	# 2.8 – Detalhes do VG e RCRs (apenas para log)
	echo "$vg_details" | jq -r '"State: \(.state) - Number of Volumes: \(.numOfvols)"' | tee -a "$log_file"
	vg_get 2>>"$log_file" | tee -a "$log_file" #>/dev/null
	vg_rcr 2>>"$log_file" | jq -r '.remoteCopyRelationships[]? | "Progress: \(.progress) -- RCR: \(.name) -- Master: \(.masterVolumeName)"' | tee -a "$log_file"
	cgname=$(vg_ls 2>>"$log_file" | jq -r --arg vg_name "$vg_name" '.volumeGroups[]? | select(.name == $vg_name) | .consistencyGroupName')
	if [[ -z "$cgname" || "$cgname" == "null" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Could not retrieve consistencyGroupName for VG $vg_name." 1
	fi
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Consistency group name: $cgname" "1"
	###################################
	# 2. TARGET WORKSPACE / TARGET VSI #
	###################################
	base_url="$target_base_url"
	CRN="$target_ws_crn"
	CLOUD_INSTANCE_ID="$target_CLOUD_INSTANCE_ID"
	PVM_ID="$target_PVM_ID"
	# 2.10 – Onboarding dos auxiliary volumes no TARGET
	ondesc="onboard_aux_vols_$vol_com_name"
	# Construir JSON array de auxiliaryVolumes sem quebras de linha
	aux_json=""
	for name in $auxvol_names
	do
		# cada entrada: {"auxVolumeName":"..."},
		aux_json="$aux_json{\"auxVolumeName\":\"$name\"},"
	done
	# remover última vírgula
	aux_json="${aux_json%,}"
	ACTIONS=$(cat <<EOF
		"Volumes": [
		{
		"auxiliaryVolumes": [
			$aux_json
		],
		"sourceCRN": "$source_ws_crn"
		}
		],
		"description": "$ondesc"
EOF
)
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Starting auxiliary volume onboarding on target workspace for VSI $target_vsi." "1"
	# Chamada ao onboarding e validação de erro
	resp_on=$(on_cr_status 2>>"$log_file")
	grs_check_write "$resp_on" "creating volume onboarding" "the source Volume Group was already created"
	VOLUME_ONBOARDING_ID=$(on_ls | jq -r --arg desc "$ondesc" '[.onboardings[]? | select(.description == $desc)][-1].id' 2>>"$log_file")
	if [[ -z "$VOLUME_ONBOARDING_ID" || "$VOLUME_ONBOARDING_ID" == "null" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Could not find onboarding ID for description $ondesc." 1
	fi
	if [[ -z "$VOLUME_ONBOARDING_ID" || "$VOLUME_ONBOARDING_ID" == "null" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Could not find onboarding ID for description $ondesc." 1
	fi
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Onboarding request ID: $VOLUME_ONBOARDING_ID" "1"
	# 2.11 – Monitor onboarding
	chk_on_status
	# 2.12 – Validar Volume Group no TARGET (mesmo consistencyGroupName)
	VOLUME_GROUP_ID=$(vg_ls | jq -r --arg cgname "$cgname" '.volumeGroups[]? | select(.consistencyGroupName == $cgname) | .id' 2>>"$log_file")
	if [[ -z "$VOLUME_GROUP_ID" || "$VOLUME_GROUP_ID" == "null" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Onboarding finished, but target Volume Group with consistencyGroupName $cgname not found." 1
	fi
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - GRS completed. Target Volume Group ID: $VOLUME_GROUP_ID" "1"
	abort "`date +%Y-%m-%d_%H:%M:%S` - === GRS successfully configured between $source_vsi -> $target_vsi (VG: $vg_name). ==="
}
####  END:FUNCTION  Main GRS function: create VG in source and onboard aux volumes in target  ####

#### START:FUNCTION - Delete GRS (without deleting primary volumes) ####
delete_grs() {
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - === Starting GRS delete between source VSI $source_vsi and target VSI $target_vsi (VG: $vg_name) ===" "1"
	####################################
	# 1. SOURCE WORKSPACE / SOURCE VG  #
	####################################
	base_url="$source_base_url"
	CRN="$source_ws_crn"
	CLOUD_INSTANCE_ID="$source_CLOUD_INSTANCE_ID"
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Working on SOURCE workspace for VSI $source_vsi..." "1"
	local vg_json
	vg_json=$(vg_ls 2>>"$log_file")
	VOLUME_GROUP_ID=$(echo "$vg_json" | jq -r --arg vg "$vg_name" '
		.volumeGroups[]? | select(.name == $vg) | .id
	' 2>>"$log_file")
	if [[ -z "$VOLUME_GROUP_ID" || "$VOLUME_GROUP_ID" == "null" ]]; then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Volume Group $vg_name not found in source workspace. Aborting GRS delete." 1
	fi
	cgname=$(echo "$vg_json" | jq -r --arg vg "$vg_name" '
		.volumeGroups[]? | select(.name == $vg) | .consistencyGroupName
	' 2>>"$log_file")
	if [[ -z "$cgname" || "$cgname" == "null" ]]; then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Could not retrieve consistencyGroupName for VG $vg_name in source workspace." 1
	fi
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Source VG $vg_name has ID $VOLUME_GROUP_ID and consistencyGroupName $cgname." "1"
	# (1.19.2) Refuse before changing anything when the target side has more than one VG
	# with this consistencyGroupName.
	local src_vg_id="$VOLUME_GROUP_ID" pre_tg_count
	base_url="$target_base_url"; CRN="$target_ws_crn"; CLOUD_INSTANCE_ID="$target_CLOUD_INSTANCE_ID"
	pre_tg_count=$(vg_ls 2>>"$log_file" | jq -r --arg cg "$cgname" '[.volumeGroups[]? | select(.consistencyGroupName == $cg)] | length' 2>>"$log_file")
	base_url="$source_base_url"; CRN="$source_ws_crn"; CLOUD_INSTANCE_ID="$source_CLOUD_INSTANCE_ID"; VOLUME_GROUP_ID="$src_vg_id"
	case "$pre_tg_count" in
		0|1) ;;
		*) abort "$(date +%Y-%m-%d_%H:%M:%S) - Target workspace has ${pre_tg_count:-an unreadable number of} Volume Groups with consistencyGroupName $cgname. Aborting GRS delete; nothing was changed." 1 ;;
	esac
	# 1.1 Remover volumes do VG (source)
	# (1.19.2) The volumes are the VG's own members (volumeIDs from the VG details), not
	# every volume in the workspace whose name starts with VOLUMES_COMMON_NAME, which also
	# caught volumes of other LPARs and other volume groups.
	local src_vg_details
	src_vg_details=$(vg_get 2>>"$log_file")
	if ! echo "$src_vg_details" | jq -e '.volumeIDs | type == "array"' >/dev/null 2>&1; then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Could not read the member volumes of VG $vg_name in source workspace. Aborting GRS delete; nothing was changed." 1
	fi
	src_vol_ids=$(echo "$src_vg_details" | jq -r '.volumeIDs[]' 2>>"$log_file")
	if [[ -z "$src_vol_ids" ]]; then
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Source VG $vg_name has no member volumes to remove. Continuing..." "1"
	else
		local json_ids=""
		for vid in $src_vol_ids; do
			json_ids="$json_ids\"$vid\","
		done
		json_ids="${json_ids%,}"
		ACTIONS="\"removeVolumes\":[${json_ids}]"
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Removing source volumes from VG $vg_name: [${json_ids}]..." "1"
		resp_upd=$(vg_upd_status 2>>"$log_file")
		grs_check_write "$resp_upd" "removing source volumes from VG $vg_name"
		# 1.2 Esperar o VG ficar em estado empty
		# (1.19.2) Bounded: 60 checks at 30s.
		local vg_empty_wait=0
		while true
		do
			local vg_state
			vg_state=$(vg_sd 2>>"$log_file" | jq -r '.state // empty')
			if [[ "$vg_state" == "empty" ]]; then
				echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Source Volume Group $vg_name is in state 'empty'." "1"
				break
			fi
			vg_empty_wait=$((vg_empty_wait + 1))
			if [ "$vg_empty_wait" -ge 60 ]; then
				abort "$(date +%Y-%m-%d_%H:%M:%S) - Source VG $vg_name did not become empty after 30 minutes (state '$vg_state'). Aborting before deleting it." 1
			fi
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Source VG $vg_name still in state '$vg_state'. Waiting 30 seconds..." "1"
			sleep 30
		done
	fi
	# 1.3 Apagar o VG no source
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Deleting source Volume Group $vg_name..." "1"
	resp_del=$(vg_del_status 2>>"$log_file")
	grs_check_write "$resp_del" "deleting source Volume Group $vg_name" "its member volumes were already removed"
	# 1.4 Desativar replication nos volumes de origem (sem os apagar)
	if [[ -n "$src_vol_ids" ]]; then
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Disabling replication on the source VG's member volumes..." "1"
		for vid in $src_vol_ids
		do
			VOL_ID="$vid"
			ACTIONS='"replicationEnabled": false'
			resp_rep=$(vol_act_status 2>>"$log_file")
			grs_check_write "$resp_rep" "disabling replication on source volume $vid" "the source Volume Group was already deleted"
		done
		# Esperar até todos ficarem replicationEnabled=false
		# (1.19.2) Checks exactly those volumes, and a volume that cannot be read counts as
		# not yet disabled. Bounded: 180 checks at 10s.
		local rep_wait=0 still_on
		while true
		do
			still_on=""
			for vid in $src_vol_ids
			do
				VOL_ID="$vid"
				if [[ "$(vol_ws_get 2>>"$log_file" | jq -r '.replicationEnabled' 2>/dev/null)" != "false" ]]; then
					still_on="$still_on $vid"
				fi
			done
			if [[ -z "$still_on" ]]; then
				echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - All source VG member volumes now have replicationEnabled=false." "1"
				break
			fi
			rep_wait=$((rep_wait + 1))
			if [ "$rep_wait" -ge 180 ]; then
				abort "$(date +%Y-%m-%d_%H:%M:%S) - Source volumes still not replicationEnabled=false after 30 minutes:$still_on. Aborting before touching the target." 1
			fi
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Some source volumes still have replicationEnabled=true:$still_on. Waiting 10 seconds..." "1"
			sleep 10
		done
	else
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - No source volumes to disable replication for." "1"
	fi
	####################################
	# 2. TARGET WORKSPACE / TARGET VG  #
	####################################
	base_url="$target_base_url"
	CRN="$target_ws_crn"
	CLOUD_INSTANCE_ID="$target_CLOUD_INSTANCE_ID"
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Working on TARGET workspace for VSI $target_vsi..." "1"
	vg_json=$(vg_ls 2>>"$log_file")
	# (1.19.2) The target VG is matched by consistencyGroupName, as every other GRS flow
	# does, and must be exactly one; a name prefix could match several volume groups.
	local tg_vg_count
	VOLUME_GROUP_ID=$(echo "$vg_json" | jq -r --arg cg "$cgname" '
		.volumeGroups[]? | select(.consistencyGroupName == $cg) | .id
	' 2>>"$log_file")
	tg_vg_count=$(printf '%s\n' "$VOLUME_GROUP_ID" | grep -c .)
	if [ "$tg_vg_count" -gt 1 ]; then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - More than one target Volume Group has consistencyGroupName $cgname: $(echo $VOLUME_GROUP_ID). Aborting; nothing was changed on target." 1
	fi
	tg_vol_ids=""
	if [[ -z "$VOLUME_GROUP_ID" || "$VOLUME_GROUP_ID" == "null" ]]; then
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Target Volume Group for consistencyGroupName $cgname not found. Skipping VG delete on target." "1"
	else
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Target VG found with ID $VOLUME_GROUP_ID (consistencyGroupName $cgname)." "1"
		# 2.1 Remover auxiliary volumes do VG no target
		# (1.19.2) The auxiliary volumes are the target VG's own members. Selecting every
		# target-workspace volume whose name contains VOLUMES_COMMON_NAME also caught volumes
		# of other LPARs, clones and other volume groups, which were then deleted in 3.2.
		local tg_vg_details
		tg_vg_details=$(vg_get 2>>"$log_file")
		if ! echo "$tg_vg_details" | jq -e '.volumeIDs | type == "array"' >/dev/null 2>&1; then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - Could not read the member volumes of target VG $VOLUME_GROUP_ID. Aborting; nothing was changed on target." 1
		fi
		tg_vol_ids=$(echo "$tg_vg_details" | jq -r '.volumeIDs[]' 2>>"$log_file")
		if [[ -z "$tg_vol_ids" ]]
		then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Target VG has no member volumes to remove. Continuing..." "1"
		else
			local tg_json_ids=""
			for vid in $tg_vol_ids
			do
				tg_json_ids="$tg_json_ids\"$vid\","
			done
			tg_json_ids="${tg_json_ids%,}"
			ACTIONS="\"removeVolumes\":[${tg_json_ids}]"
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Removing target volumes from VG (CG: $cgname): [${tg_json_ids}]..." "1"
			resp_tupd=$(vg_upd_status 2>>"$log_file")
			grs_check_write "$resp_tupd" "removing target volumes from VG (CG: $cgname)" "the source side was already cleaned up"
		fi
	fi
	####################################
	# 3. TARGET VSI: Detach & delete aux volumes #
	####################################
	# Contexto da VSI target para detach volumes
	PVM_ID="$target_PVM_ID"
	# 3.1 Detach de todos os volumes (incluindo boot) do TARGET_VSI
	ACTIONS='"detachAllVolumes": true, "detachPrimaryBootVolume": true'
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Detaching all volumes (including boot) from target VSI $target_vsi..." "1"
	resp_bdet=$(ins_vol_bdet_status 2>>"$log_file")
	grs_check_write "$resp_bdet" "detaching volumes from target VSI $target_vsi" "the target VG's volumes were already removed"
	# Esperar até não haver volumes anexados
	# (1.19.2) Bounded: 60 checks at 30s.
	local detach_wait=0
	while true
	do
		local attached
		attached=$(ins_vol_ls 2>>"$log_file" | jq -r '.volumes[]? | .name' 2>/dev/null)
		if [[ -z "$attached" ]]; then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - No volumes attached to target VSI $target_vsi." "1"
			break
		fi
		detach_wait=$((detach_wait + 1))
		if [ "$detach_wait" -ge 60 ]; then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - Target VSI $target_vsi still has attached volumes after 30 minutes. Aborting before deleting any volume." 1
		fi
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Target VSI $target_vsi still has attached volumes. Waiting 30 seconds..." "1"
		sleep 30
	done
	# SAFETY CHECK – ensure aux volumes are NOT replicationEnabled
	# (1.19.2) Read at workspace level: vol_get asked the target VSI for volumes that had
	# just been detached from it, so the read failed and "// false" let every volume pass.
	# Now a volume passes only when it reads replicationEnabled=false and is attached to no
	# LPAR; unreadable counts as unsafe.
	local vol_json
	unsafe_aux=""
	for vid in $tg_vol_ids
	do
		VOL_ID="$vid"
		vol_json=$(vol_ws_get 2>>"$log_file")
		if ! echo "$vol_json" | jq -e '.replicationEnabled == false and ((.pvmInstanceIDs // []) | length == 0)' >/dev/null 2>&1
		then
			unsafe_aux="$unsafe_aux $vid"
		fi
	done
	if [[ -n "$unsafe_aux" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Some target (aux) volumes are unreadable, still have replicationEnabled=true, or are attached to an LPAR: $unsafe_aux. Aborting GRS delete to avoid impacting primary volumes." 1
	fi
	# 3.2 Apagar auxiliary volumes no target (os mesmos IDs apanhados antes)
	if [[ -n "$tg_vol_ids" ]]; then
		local tg_del_ids=""
		for vid in $tg_vol_ids; do
			tg_del_ids="$tg_del_ids\"$vid\","
		done
		tg_del_ids="${tg_del_ids%,}"
		ACTIONS="\"volumeIDs\":[${tg_del_ids}]"
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Deleting auxiliary volumes on target: [${tg_del_ids}]..." "1"
		resp_vbdel=$(vol_bdel_status 2>>"$log_file")
		grs_check_write "$resp_vbdel" "deleting auxiliary volumes on target" "the target VSI was already detached"
	else
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - No auxiliary volumes to delete on target." "1"
	fi
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - === GRS delete completed between $source_vsi and $target_vsi (VG: $vg_name). Primary VSI remains with its volumes; auxiliary side cleaned up. ===" "1"
}
#### END:FUNCTION - Delete GRS ####

#### START:FUNCTION - GRS Failover (Activate Target) ####
do_grs_failover() {
	# Expected globals:
	#   source_vsi, vg_name, attach_mode, target_vsi (optional)
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - === Starting GRS failover (activate target) for SOURCE_VSI=$source_vsi, VG_NAME=$vg_name, MODE=$attach_mode ===" "1"

	############################
	# 1) Resolve SOURCE context #
	############################
	vsi="$source_vsi"
	vsi_id_bluexscrt
	check_locally_VSI_exists

	local source_ws_key="$vsiwsshort"
	local source_ws_name
	source_ws_name=$(jq -r --arg ws "$source_ws_key" '.workspaces[$ws].name' "$bluexscrt")
	local source_ws_crn_local="$shortnamecrn"
	local source_cloud_instance_id_local="$CLOUD_INSTANCE_ID"
	local source_base_url_local="$base_url"
	local source_pvm_id_local="$PVM_ID"

	# Force SOURCE workspace context
	base_url="$source_base_url_local"
	CRN="$source_ws_crn_local"
	CLOUD_INSTANCE_ID="$source_cloud_instance_id_local"
	PVM_ID="$source_pvm_id_local"

	# Find SOURCE VG and consistencyGroupName
	local vg_json
	vg_json=$(vg_ls 2>>"$log_file")
	local source_vg_id
	source_vg_id=$(echo "$vg_json" | jq -r --arg vg "$vg_name" '.volumeGroups[]? | select(.name == $vg) | .id' 2>>"$log_file")
	if [[ -z "$source_vg_id" || "$source_vg_id" == "null" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Source Volume Group $vg_name not found in source workspace $source_ws_name. Aborting failover." 1
	fi
	local cgname
	cgname=$(echo "$vg_json" | jq -r --arg vg "$vg_name" '.volumeGroups[]? | select(.name == $vg) | .consistencyGroupName' 2>>"$log_file")
	if [[ -z "$cgname" || "$cgname" == "null" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Could not retrieve consistencyGroupName for source VG $vg_name (workspace $source_ws_name)." 1
	fi
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Source workspace: $source_ws_name (id=$source_cloud_instance_id_local) - Source VG ID=$source_vg_id - consistencyGroupName=$cgname" "1"

	# Identify BOOT auxiliary volume name (from SOURCE VSI attached volumes list)
	local boot_aux_name
	boot_aux_name=$(ins_vol_ls 2>>"$log_file" | jq -r '.volumes[]? | select(.bootable == true) | .auxVolumeName // empty' 2>>"$log_file" | head -n1)
	if [[ -z "$boot_aux_name" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Could not determine boot auxiliary volume name from source VSI $source_vsi. Aborting." 1
	fi
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Boot auxiliary volume name (from source): $boot_aux_name" "1"

	# Collect ALL auxiliary volume names for this VG (from SOURCE VG remote-copy relationships)
	VOLUME_GROUP_ID="$source_vg_id"
	local aux_names
	aux_names=$(vg_rcr 2>>"$log_file" | jq -r '.remoteCopyRelationships[]? | select(.primaryRole=="master") | .auxVolumeName' 2>>"$log_file")
	if [[ -z "$aux_names" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Could not retrieve auxiliary volumes from remote-copy relationships for source VG $vg_name. Aborting." 1
	fi
	local aux_count
	aux_count=$(echo "$aux_names" | wc -w | awk '{print $1}')
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Found $aux_count auxiliary volume names in VG $vg_name: $(echo "$aux_names" | tr '\n' ' ')" "1"

	##############################################
	# 2) Find TARGET workspace and TARGET VG (by cgname)
	##############################################
	local allws_keys
	allws_keys=$(jq -r '.workspaces | keys | join(" ")' "$bluexscrt")
	local target_ws_key=""
	local target_ws_name=""
	local target_ws_crn=""
	local target_cloud_instance_id=""
	local target_base_url=""
	local target_vg_id=""

	local tg_ws_list=""
	for ws in $allws_keys
	do
		local ws_crn
		ws_crn=$(jq -r --arg k "$ws" '.workspaces[$k].crn' "$bluexscrt")
		# Skip SOURCE workspace
		if [[ "$ws_crn" == "$source_ws_crn_local" ]]
		then
			continue
		fi

		CRN="$ws_crn"
		CLOUD_INSTANCE_ID=$(jq -r --arg k "$ws" '.workspaces[$k].id' "$bluexscrt")
		region_api=$(jq -r --arg k "$ws" '.workspaces[$k].crn | capture("power-iaas:(?<region>[^:]+)") | .region | gsub("-"; "_")' "$bluexscrt")
		base_url_var="base_${region_api}"
		base_url="${!base_url_var}"

		# List VGs here and look for the same consistencyGroupName
		local vg_tmp
		vg_tmp=$(vg_ls 2>>"$log_file")
		local found_id found_count
		found_id=$(echo "$vg_tmp" | jq -r --arg cg "$cgname" '.volumeGroups[]? | select(.consistencyGroupName == $cg) | .id' 2>>"$log_file")
		# (1.20.0) head -n1 used to silently pick the first of several matches. Count them:
		# no write has happened yet in this function, so an ambiguous match aborts here.
		found_count=$(printf '%s\n' "$found_id" | grep -c .)
		if [ "$found_count" -gt 1 ]
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - More than one Volume Group with consistencyGroupName $cgname in workspace $ws: $(printf '%s' "$found_id" | tr '\n' ' '). Aborting failover; nothing was changed." 1
		fi
		found_id=$(printf '%s\n' "$found_id" | head -n1)

		if [[ -n "$found_id" && "$found_id" != "null" ]]
		then
			# (1.20.1) Keep scanning: a second workspace with the same consistencyGroupName
			# is ambiguous and must not be resolved by workspace order.
			tg_ws_list="$tg_ws_list $ws"
			if [[ -z "$target_vg_id" ]]
			then
				target_ws_key="$ws"
				target_ws_name=$(jq -r --arg k "$ws" '.workspaces[$k].name' "$bluexscrt")
				target_ws_crn="$ws_crn"
				target_cloud_instance_id="$CLOUD_INSTANCE_ID"
				target_base_url="$base_url"
				target_vg_id="$found_id"
			fi
		fi
	done
	if [ "$(echo $tg_ws_list | wc -w)" -gt 1 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Volume Groups with consistencyGroupName $cgname exist in more than one other workspace:$tg_ws_list. Aborting; nothing was changed." 1
	fi

	if [[ -z "$target_vg_id" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Could not find target Volume Group with consistencyGroupName $cgname in any other configured workspace. Aborting failover." 1
	fi
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Target workspace found: $target_ws_name (id=$target_cloud_instance_id) - Target VG ID=$target_vg_id" "1"

	##############################################
	# 3) Activate target (stop access) on TARGET VG
	##############################################
	base_url="$target_base_url"
	CRN="$target_ws_crn"
	CLOUD_INSTANCE_ID="$target_cloud_instance_id"
	VOLUME_GROUP_ID="$target_vg_id"

	ACTIONS='"stop":{"access":true}'
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Performing failover: VG action stop.access=true on target VG $target_vg_id..." "1"
	resp_act=$(vg_act_status 2>>"$log_file")
	grs_check_write "$resp_act" "activating target VG $target_vg_id (stop access)"

	# Wait until VG becomes idling (or a stable state)
	local max_wait=60
	local i=0
	while true
	do
		local t_state
		t_state=$(vg_sd 2>>"$log_file" | jq -r '.state // empty' 2>>"$log_file")
		if [[ "$t_state" == "idling" ]]
		then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Target VG state is now 'idling'." "1"
			break
		fi
		# If API returns empty, treat as error
		if [[ -z "$t_state" ]]
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Could not read target VG storage-details/state while waiting for failover." 1
		fi
		i=$((i + 1))
		if (( i >= max_wait ))
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Target VG did not reach state 'idling' after $max_wait minutes (last state=$t_state)." 1
		fi
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Target VG state is '$t_state'. Waiting 60 seconds..." "1"
		sleep 60
	done

	##############################################
	# 4) Optional: Attach volumes to TARGET_VSI
	##############################################
	if [[ "$attach_mode" == "NO_ATTACH" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - === GRS failover completed (NO_ATTACH). Target is activated in workspace $target_ws_name. ==="
	fi

	# ATTACH mode requires TARGET_VSI
	if [[ -z "$target_vsi" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - TARGET_VSI is required when using ATTACH mode. Syntax: bluexport_api.sh -grsfailover SOURCE_VSI VG_NAME ATTACH TARGET_VSI" 1
	fi

	# Resolve TARGET_VSI context (must be in the same workspace we just found)
	vsi="$target_vsi"
	vsi_id_bluexscrt
	check_locally_VSI_exists
	local target_pvm_id_local="$PVM_ID"

	if [[ "$shortnamecrn" != "$target_ws_crn" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - TARGET_VSI $target_vsi is not in the target workspace where the VG was activated ($target_ws_name). Aborting attach to avoid cross-workspace mistakes." 1
	fi

	# Map aux volume NAMES -> volumeIDs in TARGET workspace
	local target_vols_json
	target_vols_json=$(vol_ls 2>>"$log_file")
	if [[ -z "$target_vols_json" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Could not list volumes in target workspace $target_ws_name." 1
	fi

	local boot_vol_id boot_vol_count
	boot_vol_id=$(echo "$target_vols_json" | jq -r --arg n "$boot_aux_name" '.volumes[]? | select(.name == $n) | .volumeID' 2>>"$log_file")
	# (1.20.0) head -n1 used to silently pick the first of several matches. Count them:
	# the target VG was already activated (stop.access=true) above, so this aborts before
	# the next write (attaching the wrong volume).
	boot_vol_count=$(printf '%s\n' "$boot_vol_id" | grep -c .)
	if [ "$boot_vol_count" -gt 1 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - More than one volume named $boot_aux_name in target workspace $target_ws_name: $(printf '%s' "$boot_vol_id" | tr '\n' ' '). Aborting before attaching; the target VG was already activated (stop.access=true)." 1
	fi
	boot_vol_id=$(printf '%s\n' "$boot_vol_id" | head -n1)
	if [[ -z "$boot_vol_id" || "$boot_vol_id" == "null" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Could not resolve boot auxiliary volume name $boot_aux_name to a volumeID in target workspace $target_ws_name." 1
	fi

	# Attach boot volume first
	ACTIONS="\"volumeIDs\":[\"$boot_vol_id\"]"
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Attaching BOOT volume to TARGET_VSI $target_vsi (volumeID=$boot_vol_id, name=$boot_aux_name)..." "1"
	resp_att_boot=$(vol_att_multi_status 2>>"$log_file")
	grs_check_write "$resp_att_boot" "attaching boot volume to $target_vsi" "the target VG was already activated (stop.access=true)"

	# IMPORTANT: Wait until the BOOT volume is effectively attached before attaching other volumes.
	# PowerVS will reject additional attaches until the primary boot volume is attached/recognized.
	local max_boot_wait=60   # attempts (60 * 10s = 10 minutes)
	local boot_try=0
	while true
	do
		local boot_seen boot_status
		boot_seen=$(ins_vol_ls 2>>"$log_file" | jq -r --arg vid "$boot_vol_id" '.volumes[]? | select((.volumeID // .id) == $vid) | (.volumeID // .id) // empty' 2>>"$log_file" | head -n1)
		boot_status=$(ins_vol_ls 2>>"$log_file" | jq -r --arg vid "$boot_vol_id" '.volumes[]? | select((.volumeID // .id) == $vid) | (.state // .status // .attachmentStatus // empty)' 2>>"$log_file" | head -n1)
		if [[ -n "$boot_seen" ]]
		then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Boot volume is now attached/visible on $target_vsi (state/status=${boot_status:-unknown}). Proceeding with remaining volumes..." "1"
			break
		fi
		boot_try=$((boot_try + 1))
		if (( boot_try >= max_boot_wait ))
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Boot volume ($boot_aux_name / $boot_vol_id) did not become attached/visible on $target_vsi after ~10 minutes. Aborting." 1
		fi
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Boot volume still attaching on $target_vsi... waiting 10 seconds (attempt $boot_try/$max_boot_wait)" "1"
		sleep 10
	done


	# Build JSON list for remaining volumes (excluding boot_aux_name)
	local json_ids=""
	local aux_name
	for aux_name in $aux_names
	do
		# Skip boot (already attached)
		if [[ "$aux_name" == "$boot_aux_name" ]]
		then
			continue
		fi
		local vid vid_count
		vid=$(echo "$target_vols_json" | jq -r --arg n "$aux_name" '.volumes[]? | select(.name == $n) | .volumeID' 2>>"$log_file")
		# (1.20.0) head -n1 used to silently pick the first of several matches. Count them:
		# the boot volume attach above was already sent, so this aborts before the next
		# write (attaching the wrong volume).
		vid_count=$(printf '%s\n' "$vid" | grep -c .)
		if [ "$vid_count" -gt 1 ]
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - More than one volume named $aux_name in target workspace $target_ws_name: $(printf '%s' "$vid" | tr '\n' ' '). Aborting before attaching; the boot volume was already attached." 1
		fi
		vid=$(printf '%s\n' "$vid" | head -n1)
		if [[ -z "$vid" || "$vid" == "null" ]]
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Could not resolve auxiliary volume name $aux_name to a volumeID in target workspace $target_ws_name." 1
		fi
		json_ids="$json_ids\"$vid\","
	done
	json_ids="${json_ids%,}"

	if [[ -n "$json_ids" ]]
	then
		ACTIONS="\"volumeIDs\":[${json_ids}]"
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Attaching remaining auxiliary volumes to TARGET_VSI $target_vsi..." "1"
		resp_att=$(vol_att_multi_status 2>>"$log_file")
		grs_check_write "$resp_att" "attaching auxiliary volumes to $target_vsi" "the boot volume was already attached"
	else
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - No additional auxiliary volumes to attach (only boot)." "1"
	fi

	# IMPORTANT: Volume attach requests are async. Wait until we see all expected volumes attached.
	# Expected count is the number of aux volumes in the VG (includes boot).
	local expected_attached
	expected_attached="$aux_count"
	if [[ -z "$expected_attached" || "$expected_attached" == "0" ]]
	then
		expected_attached=1
	fi

	local max_attach_wait=60   # attempts (60 * 10s = 10 minutes)
	local att_try=0
	local tgt_count
	while true
	do
		# Ensure we are still in TARGET context
		base_url="$target_base_url"
		CRN="$target_ws_crn"
		CLOUD_INSTANCE_ID="$target_cloud_instance_id"
			PVM_ID="$target_pvm_id_local"

		# Count attached volumes on TARGET VSI (robust count via JSON length)
		tgt_count=$(ins_vol_ls 2>>"$log_file" | jq -r '.volumes | length' 2>>"$log_file")
		if [[ -z "$tgt_count" || "$tgt_count" == "null" ]]
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Could not read attached volumes count on TARGET_VSI $target_vsi while waiting for volume attaches." 1
		fi

		if (( tgt_count >= expected_attached ))
		then
			break
		fi
		att_try=$((att_try + 1))
		if (( att_try >= max_attach_wait ))
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - TARGET_VSI $target_vsi did not reach $expected_attached attached volumes after ~10 minutes (last count=$tgt_count)." 1
		fi
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Volumes still attaching on $target_vsi... currently $tgt_count/$expected_attached attached. Waiting 10 seconds (attempt $att_try/$max_attach_wait)" "1"
		sleep 10
	done

	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - TARGET_VSI $target_vsi now has $tgt_count attached volumes." "1"

	abort "$(date +%Y-%m-%d_%H:%M:%S) - === GRS failover completed (ATTACH). Target activated and volumes attached to $target_vsi in workspace $target_ws_name. ==="
}
#### END:FUNCTION - GRS Failover (Activate Target) ####

#### START:FUNCTION - GRS Cancel Failover (Start from Master) ####
do_grs_cancel_failover() {
	# Syntax: bluexport_api.sh -grscancelfailover SOURCE_VSI VG_NAME NO_DETACH|DETACH TARGET_VSI
	# Expected globals:
	#   source_vsi, vg_name, detach_mode, target_vsi
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - === Starting GRS cancel failover (start from master) for SOURCE_VSI=$source_vsi, VG_NAME=$vg_name, MODE=$detach_mode, TARGET_VSI=$target_vsi ===" "1"

	############################
	# 1) Resolve SOURCE context #
	############################
	vsi="$source_vsi"
	vsi_id_bluexscrt
	check_locally_VSI_exists

	local source_ws_key="$vsiwsshort"
	local source_ws_name
	source_ws_name=$(jq -r --arg ws "$source_ws_key" '.workspaces[$ws].name' "$bluexscrt")
	local source_ws_crn_local="$shortnamecrn"
	local source_cloud_instance_id_local="$CLOUD_INSTANCE_ID"
	local source_base_url_local="$base_url"
	local source_pvm_id_local="$PVM_ID"

	# Force SOURCE workspace context
	base_url="$source_base_url_local"
	CRN="$source_ws_crn_local"
	CLOUD_INSTANCE_ID="$source_cloud_instance_id_local"
	PVM_ID="$source_pvm_id_local"

	# Find SOURCE VG and consistencyGroupName
	local vg_json
	vg_json=$(vg_ls 2>>"$log_file")
	local source_vg_id
	source_vg_id=$(echo "$vg_json" | jq -r --arg vg "$vg_name" '.volumeGroups[]? | select(.name == $vg) | .id' 2>>"$log_file")
	if [[ -z "$source_vg_id" || "$source_vg_id" == "null" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Source Volume Group $vg_name not found in source workspace $source_ws_name. Aborting cancel failover." 1
	fi
	local cgname
	cgname=$(echo "$vg_json" | jq -r --arg vg "$vg_name" '.volumeGroups[]? | select(.name == $vg) | .consistencyGroupName' 2>>"$log_file")
	if [[ -z "$cgname" || "$cgname" == "null" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Could not retrieve consistencyGroupName for source VG $vg_name (workspace $source_ws_name)." 1
	fi
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Source workspace: $source_ws_name (id=$source_cloud_instance_id_local) - Source VG ID=$source_vg_id - consistencyGroupName=$cgname" "1"

	##############################################
	# 2) Find TARGET workspace and TARGET VG (by cgname)
	##############################################
	local allws_keys
	allws_keys=$(jq -r '.workspaces | keys | join(" ")' "$bluexscrt")
	local target_ws_key=""
	local target_ws_name=""
	local target_ws_crn=""
	local target_cloud_instance_id=""
	local target_base_url=""
	local target_vg_id=""

	local tg_ws_list=""
	for ws in $allws_keys
	do
		local ws_crn
		ws_crn=$(jq -r --arg k "$ws" '.workspaces[$k].crn' "$bluexscrt")
		# Skip SOURCE workspace
		if [[ "$ws_crn" == "$source_ws_crn_local" ]]
		then
			continue
		fi

		CRN="$ws_crn"
		CLOUD_INSTANCE_ID=$(jq -r --arg k "$ws" '.workspaces[$k].id' "$bluexscrt")
		region_api=$(jq -r --arg k "$ws" '.workspaces[$k].crn | capture("power-iaas:(?<region>[^:]+)") | .region | gsub("-"; "_")' "$bluexscrt")
		base_url_var="base_${region_api}"
		base_url="${!base_url_var}"

		# List VGs here and look for the same consistencyGroupName
		local vg_tmp
		vg_tmp=$(vg_ls 2>>"$log_file")
		local found_id found_count
		found_id=$(echo "$vg_tmp" | jq -r --arg cg "$cgname" '.volumeGroups[]? | select(.consistencyGroupName == $cg) | .id' 2>>"$log_file")
		# (1.20.0) head -n1 used to silently pick the first of several matches. Count them:
		# no write has happened yet in this function, so an ambiguous match aborts here.
		found_count=$(printf '%s\n' "$found_id" | grep -c .)
		if [ "$found_count" -gt 1 ]
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - More than one Volume Group with consistencyGroupName $cgname in workspace $ws: $(printf '%s' "$found_id" | tr '\n' ' '). Aborting cancel failover; nothing was changed." 1
		fi
		found_id=$(printf '%s\n' "$found_id" | head -n1)

		if [[ -n "$found_id" && "$found_id" != "null" ]]
		then
			# (1.20.1) Keep scanning: a second workspace with the same consistencyGroupName
			# is ambiguous and must not be resolved by workspace order.
			tg_ws_list="$tg_ws_list $ws"
			if [[ -z "$target_vg_id" ]]
			then
				target_ws_key="$ws"
				target_ws_name=$(jq -r --arg k "$ws" '.workspaces[$k].name' "$bluexscrt")
				target_ws_crn="$ws_crn"
				target_cloud_instance_id="$CLOUD_INSTANCE_ID"
				target_base_url="$base_url"
				target_vg_id="$found_id"
			fi
		fi
	done
	if [ "$(echo $tg_ws_list | wc -w)" -gt 1 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Volume Groups with consistencyGroupName $cgname exist in more than one other workspace:$tg_ws_list. Aborting; nothing was changed." 1
	fi

	if [[ -z "$target_vg_id" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Could not find target Volume Group with consistencyGroupName $cgname in any other configured workspace. Aborting cancel failover." 1
	fi
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Target workspace found: $target_ws_name (id=$target_cloud_instance_id) - Target VG ID=$target_vg_id" "1"

	##############################################
	# 3) DETACH handling (optional / safety)
	##############################################
	# Resolve TARGET_VSI context (must be in TARGET workspace)
	vsi="$target_vsi"
	vsi_id_bluexscrt
	check_locally_VSI_exists

	if [[ "$shortnamecrn" != "$target_ws_crn" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - TARGET_VSI $target_vsi is not in the target workspace ($target_ws_name) where the VG exists. Aborting to avoid cross-workspace mistakes." 1
	fi

	# Switch API context to TARGET workspace for volume checks/detach
	base_url="$target_base_url"
	CRN="$target_ws_crn"
	CLOUD_INSTANCE_ID="$target_cloud_instance_id"

	##############################################
	# 2.5) Safety: refuse while TARGET runs on the group's own volumes
	##############################################
	# (1.20.0) Before any write in this flow: "start.source=master" below overwrites
	# whatever the group's volumes hold. If TARGET_VSI is not SHUTOFF and is attached to
	# one of the target VG's own member volumes, it is running on the data that step is
	# about to clobber.
	VOLUME_GROUP_ID="$target_vg_id"
	local tg_vg_json_safety
	tg_vg_json_safety=$(vg_get 2>>"$log_file")
	if ! echo "$tg_vg_json_safety" | jq -e '.volumeIDs | type == "array"' >/dev/null 2>&1
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Could not read the member volumes of target VG $target_vg_id while checking TARGET_VSI safety. Aborting; nothing was changed." 1
	fi
	local tg_vg_volids
	tg_vg_volids=$(echo "$tg_vg_json_safety" | jq -r '.volumeIDs[]' 2>>"$log_file")

	local tgt_vsi_status
	tgt_vsi_status=$(ins_get 2>>"$log_file" | jq -r '.status // "UNKNOWN"' 2>>"$log_file")

	if [[ "$tgt_vsi_status" != "SHUTOFF" ]]
	then
		local tgt_vol_json_safety
		tgt_vol_json_safety=$(ins_vol_ls 2>>"$log_file")
		if ! echo "$tgt_vol_json_safety" | jq -e '.volumes | type == "array"' >/dev/null 2>&1
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - TARGET_VSI $target_vsi is not SHUTOFF (status=$tgt_vsi_status) and its attached volumes could not be read. Stop it first; nothing was changed." 1
		fi
		local tgt_attached_ids overlap vid_check
		tgt_attached_ids=$(echo "$tgt_vol_json_safety" | jq -r '.volumes[]? | (.volumeID // .id)' 2>>"$log_file")
		overlap=""
		for vid_check in $tgt_attached_ids
		do
			if printf '%s\n' "$tg_vg_volids" | grep -qx "$vid_check"
			then
				overlap="$overlap $vid_check"
			fi
		done
		if [[ -n "$overlap" ]]
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - stop TARGET_VSI $target_vsi first (status=$tgt_vsi_status): the master start overwrites the volumes it is running on (member of target VG $target_vg_id:$overlap)." 1
		fi
	fi

	##############################################
	# 3) DETACH handling (optional / safety)
	##############################################
	# PVM_ID already set by vsi_id_bluexscrt for TARGET_VSI
	local tgt_attached_names
	tgt_attached_names=$(ins_vol_ls 2>>"$log_file" | jq -r '.volumes[]? | .name' 2>>"$log_file")

	if [[ "$detach_mode" == "DETACH" ]]
	then
		if [[ -z "$tgt_attached_names" ]]
		then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - No volumes currently attached to TARGET_VSI $target_vsi. Skipping detach." "1"
		else
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Detaching all volumes (including boot) from TARGET_VSI $target_vsi before cancel failover..." "1"
			ACTIONS='"detachAllVolumes": true, "detachPrimaryBootVolume": true'
			resp_det=$(ins_vol_bdet_status 2>>"$log_file")
			grs_check_write "$resp_det" "detaching volumes from TARGET_VSI $target_vsi"

			# Wait until no volumes are attached
			# (1.20.0) Bounded: 60 checks at 30s = 30 minutes.
			local detach_wait=0
			while true
			do
				local attached_now
				attached_now=$(ins_vol_ls 2>>"$log_file" | jq -r '.volumes[]? | .name' 2>>"$log_file")
				if [[ -z "$attached_now" ]]
				then
					echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - All volumes detached from TARGET_VSI $target_vsi." "1"
					break
				fi
				detach_wait=$((detach_wait + 1))
				if [ "$detach_wait" -ge 60 ]
				then
					abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - TARGET_VSI $target_vsi still has attached volumes ($attached_now) after 30 minutes. Aborting cancel failover before starting SOURCE VG as master." 1
				fi
				echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - TARGET_VSI $target_vsi still has attached volumes. Waiting 30 seconds..." "1"
				sleep 30
			done
		fi
	fi

	##############################################
	# 4) Cancel failover (start from Master): STOP+START on SOURCE VG (master)
	##############################################
	# Back to SOURCE workspace
	base_url="$source_base_url_local"
	CRN="$source_ws_crn_local"
	CLOUD_INSTANCE_ID="$source_cloud_instance_id_local"
	PVM_ID="$source_pvm_id_local"
	VOLUME_GROUP_ID="$source_vg_id"

	# Step A: stop with access=true (per IBM docs for fallback to primary / master)
	# NOTE: -grscancelfailover is commonly used right after a failover, where the SOURCE VG may
	# already be stopped/idling. If it's already idling, don't try to stop it again.
	local s_state_pre
	s_state_pre=$(vg_sd 2>>"$log_file" | jq -r '.state // empty' 2>>"$log_file")
	if [[ -z "$s_state_pre" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Could not read SOURCE VG storage-details/state before stop." 1
	fi
	if [[ "$s_state_pre" == "idling" ]]
	then
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - SOURCE VG is already in state 'idling' (stopped). Skipping stop.access=true." "1"
	else
		ACTIONS='"stop":{"access":true}'
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Cancel Failover step: VG action stop.access=true on SOURCE VG $source_vg_id..." "1"
		resp_stop=$(vg_act_status 2>>"$log_file")
		grs_check_write "$resp_stop" "stopping SOURCE VG $source_vg_id (stop access)" "the target may already have been detached"
	fi

	# Wait until SOURCE VG becomes idling (or stable) before start master
	local max_wait=60
	local i=0
	while true
	do
		local s_state
		s_state=$(vg_sd 2>>"$log_file" | jq -r '.state // empty' 2>>"$log_file")
		if [[ "$s_state" == "idling" ]]
		then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - SOURCE VG state is now 'idling'." "1"
			break
		fi
		if [[ -z "$s_state" ]]
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Could not read SOURCE VG storage-details/state while waiting for stop." 1
		fi
		i=$((i + 1))
		if (( i >= max_wait ))
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - SOURCE VG did not reach state 'idling' after $max_wait minutes (last state=$s_state)." 1
		fi
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - SOURCE VG state is '$s_state'. Waiting 60 seconds..." "1"
		sleep 60
	done

	# Step B: start with source=master (per IBM docs)
	ACTIONS='"start":{"source":"master"}'
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Cancel Failover step: VG action start.source=master on SOURCE VG $source_vg_id..." "1"
	resp_start=$(vg_act_status 2>>"$log_file")
	grs_check_write "$resp_start" "starting SOURCE VG $source_vg_id as master" "the source VG stop was already sent"

	# Wait until replication is active again (consistent_copying expected)
	i=0
	while true
	do
		local state_now
		state_now=$(vg_sd 2>>"$log_file" | jq -r '.state // empty' 2>>"$log_file")
		if [[ "$state_now" == "consistent_copying" ]]
		then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - SOURCE VG state is now 'consistent_copying' (replication active)." "1"
			break
		fi
		if [[ -z "$state_now" ]]
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Could not read SOURCE VG storage-details/state while waiting for consistent_copying." 1
		fi
		i=$((i + 1))
		if (( i >= max_wait ))
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - SOURCE VG did not reach state 'consistent_copying' after $max_wait minutes (last state=$state_now)." 1
		fi
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - SOURCE VG state is '$state_now'. Waiting 60 seconds..." "1"
		sleep 60
	done

	##############################################
	# 4B) Monitor TARGET VG replication status (enabled)
	##############################################
	# After SOURCE VG is back to consistent_copying, the TARGET VG should move to replicationStatus=enabled.
	# Log this progression explicitly (requested for -grscancelfailover visibility).
	base_url="$target_base_url"
	CRN="$target_ws_crn"
	CLOUD_INSTANCE_ID="$target_cloud_instance_id"
	VOLUME_GROUP_ID="$target_vg_id"

	local t_rep
	local t_state
	local t_try=0
	local t_max_wait=60   # minutes
	while true
	do
		t_state=$(vg_sd 2>>"$log_file" | jq -r '.state // empty' 2>>"$log_file")
		t_rep=$(vg_get 2>>"$log_file" | jq -r '.replicationStatus // .replication_status // .replicationState // .replication_state // empty' 2>>"$log_file")

		# Keep logs explicit even if some fields are missing
		if [[ -z "$t_state" ]]; then t_state="UNKNOWN"; fi
		if [[ -z "$t_rep" ]]; then t_rep="UNKNOWN"; fi

		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - TARGET VG replicationStatus is '$t_rep' (state='$t_state')." "1"

		# Desired condition: replicationStatus=enabled (case-insensitive)
		if echo "$t_rep" | tr '[:upper:]' '[:lower:]' | grep -qx "enabled"
		then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - TARGET VG replicationStatus is now 'enabled'." "1"
			break
		fi

		t_try=$((t_try + 1))
		if (( t_try >= t_max_wait ))
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - TARGET VG did not reach replicationStatus=enabled after $t_max_wait minutes (last replicationStatus=$t_rep, state=$t_state)." 1
		fi
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Waiting 60 seconds for TARGET VG replicationStatus to become enabled (attempt $t_try/$t_max_wait)..." "1"
		sleep 60
	done

	# Restore SOURCE context (for final messages / any follow-up)
	base_url="$source_base_url_local"
	CRN="$source_ws_crn_local"
	CLOUD_INSTANCE_ID="$source_cloud_instance_id_local"
	PVM_ID="$source_pvm_id_local"
	VOLUME_GROUP_ID="$source_vg_id"

	##############################################
	# 5) NO_DETACH post-check: warn if still attached
	##############################################
	if [[ "$detach_mode" == "NO_DETACH" ]]
	then
		# Switch to TARGET context again and check volumes attached
		base_url="$target_base_url"
		CRN="$target_ws_crn"
		CLOUD_INSTANCE_ID="$target_cloud_instance_id"
		# Re-resolve PVM_ID for target vsi (cheap and safe)
		vsi="$target_vsi"
		vsi_id_bluexscrt
		check_locally_VSI_exists

		local still_attached
		still_attached=$(ins_vol_ls 2>>"$log_file" | jq -r '.volumes[]? | .name' 2>>"$log_file")
		if [[ -n "$still_attached" ]]
		then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - WARNING - Cancel failover completed, but TARGET_VSI $target_vsi still has volumes attached: $(echo "$still_attached" | tr '\n' ' ')" "1"
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - WARNING - You selected NO_DETACH. Detach volumes manually if required." "1"
		fi
	fi

	abort "$(date +%Y-%m-%d_%H:%M:%S) - === GRS cancel failover completed. SOURCE VG $vg_name is back to MASTER in workspace $source_ws_name. ==="
}
#### END:FUNCTION - GRS Cancel Failover (Start from Master) ####

#### START:FUNCTION - GRS Failback (Aux -> Master) ####
do_grs_failback() {
	# Syntax: bluexport_api.sh -grsfailback SOURCE_VSI TARGET_VSI VG_NAME
	# Expected globals:
	#   source_vsi, target_vsi, vg_name
	# (1.19.3) The three polls below compare against max_wait, which was never set in this
	# function (vg_wait_sync_aux_to_master keeps its own copy local). Empty counts as 0 in
	# (( )), so each poll gave up on its first check; they now wait up to 60 minutes.
	local max_wait=60   # minutes
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - === Starting GRS failback (sync aux->master, re-enable replication) for SOURCE_VSI=$source_vsi, TARGET_VSI=$target_vsi, VG_NAME=$vg_name ===" "1"

	############################
	# 0) Resolve SOURCE context #
	############################
	vsi="$source_vsi"
	vsi_id_bluexscrt
	check_locally_VSI_exists

	local source_ws_key="$vsiwsshort"
	local source_ws_name
	source_ws_name=$(jq -r --arg ws "$source_ws_key" '.workspaces[$ws].name' "$bluexscrt")
	local source_ws_crn_local="$shortnamecrn"
	local source_cloud_instance_id_local="$CLOUD_INSTANCE_ID"
	local source_base_url_local="$base_url"
	local source_pvm_id_local="$PVM_ID"

	############################
	# 0b) Resolve TARGET context #
	############################
	vsi="$target_vsi"
	vsi_id_bluexscrt
	check_locally_VSI_exists

	local target_ws_key="$vsiwsshort"
	local target_ws_name
	target_ws_name=$(jq -r --arg ws "$target_ws_key" '.workspaces[$ws].name' "$bluexscrt")
	local target_ws_crn_local="$shortnamecrn"
	local target_cloud_instance_id_local="$CLOUD_INSTANCE_ID"
	local target_base_url_local="$base_url"
	local target_pvm_id_local="$PVM_ID"

	# Basic safety: SOURCE and TARGET must not be the same workspace
	if [[ "$source_ws_crn_local" == "$target_ws_crn_local" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - SOURCE_VSI $source_vsi and TARGET_VSI $target_vsi are in the same workspace ($source_ws_name). Failback requires two different workspaces." 1
	fi

	##############################################
	# 0c) Both VSIs must be SHUTOFF (runbook rule)
	##############################################
	# Check SOURCE VSI status
	base_url="$source_base_url_local"
	CRN="$source_ws_crn_local"
	CLOUD_INSTANCE_ID="$source_cloud_instance_id_local"
	PVM_ID="$source_pvm_id_local"
	local s_status
	s_status=$(ins_get 2>>"$log_file" | jq -r '.status // "UNKNOWN"' 2>>"$log_file")
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - SOURCE_VSI $source_vsi status: $s_status" "1"
	if [[ "$s_status" != "SHUTOFF" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - SOURCE_VSI $source_vsi is not SHUTOFF (current: $s_status). Stop it before running -grsfailback." 1
	fi

	# Check TARGET VSI status
	base_url="$target_base_url_local"
	CRN="$target_ws_crn_local"
	CLOUD_INSTANCE_ID="$target_cloud_instance_id_local"
	PVM_ID="$target_pvm_id_local"
	local t_status
	t_status=$(ins_get 2>>"$log_file" | jq -r '.status // "UNKNOWN"' 2>>"$log_file")
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - TARGET_VSI $target_vsi status: $t_status" "1"
	if [[ "$t_status" != "SHUTOFF" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - TARGET_VSI $target_vsi is not SHUTOFF (current: $t_status). Stop it before running -grsfailback." 1
	fi

	##############################################
	# 1) Identify SOURCE VG and consistencyGroupName
	##############################################
	base_url="$source_base_url_local"
	CRN="$source_ws_crn_local"
	CLOUD_INSTANCE_ID="$source_cloud_instance_id_local"
	PVM_ID="$source_pvm_id_local"

	local vg_json
	vg_json=$(vg_ls 2>>"$log_file")
	if [[ -z "$vg_json" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Could not list volume groups in source workspace $source_ws_name." 1
	fi

	local source_vg_id
	source_vg_id=$(echo "$vg_json" | jq -r --arg vg "$vg_name" '.volumeGroups[]? | select(.name == $vg) | .id' 2>>"$log_file")
	if [[ -z "$source_vg_id" || "$source_vg_id" == "null" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Source Volume Group $vg_name not found in source workspace $source_ws_name. Aborting failback." 1
	fi

	local cgname
	cgname=$(echo "$vg_json" | jq -r --arg vg "$vg_name" '.volumeGroups[]? | select(.name == $vg) | .consistencyGroupName' 2>>"$log_file")
	if [[ -z "$cgname" || "$cgname" == "null" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Could not retrieve consistencyGroupName for source VG $vg_name (workspace $source_ws_name)." 1
	fi
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Source workspace: $source_ws_name (id=$source_cloud_instance_id_local) - Source VG ID=$source_vg_id - consistencyGroupName=$cgname" "1"

	##############################################
	# 2) Identify TARGET VG by consistencyGroupName
	##############################################
	base_url="$target_base_url_local"
	CRN="$target_ws_crn_local"
	CLOUD_INSTANCE_ID="$target_cloud_instance_id_local"
	PVM_ID="$target_pvm_id_local"

	local t_vg_json
	t_vg_json=$(vg_ls 2>>"$log_file")
	if [[ -z "$t_vg_json" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Could not list volume groups in target workspace $target_ws_name." 1
	fi

	local target_vg_id target_vg_count
	target_vg_id=$(echo "$t_vg_json" | jq -r --arg cg "$cgname" '.volumeGroups[]? | select(.consistencyGroupName == $cg) | .id' 2>>"$log_file")
	# (1.20.0) head -n1 used to silently pick the first of several matches. Count them:
	# no write has happened yet in this function, so an ambiguous match aborts here.
	target_vg_count=$(printf '%s\n' "$target_vg_id" | grep -c .)
	if [ "$target_vg_count" -gt 1 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - More than one target Volume Group with consistencyGroupName $cgname in workspace $target_ws_name: $(printf '%s' "$target_vg_id" | tr '\n' ' '). Aborting failback; nothing was changed." 1
	fi
	target_vg_id=$(printf '%s\n' "$target_vg_id" | head -n1)
	if [[ -z "$target_vg_id" || "$target_vg_id" == "null" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Target Volume Group with consistencyGroupName $cgname not found in target workspace $target_ws_name. Aborting failback." 1
	fi
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Target workspace: $target_ws_name (id=$target_cloud_instance_id_local) - Target VG ID=$target_vg_id" "1"

	##############################################
	# 3) TARGET: start.source=aux (sync aux -> master)
	##############################################
	VOLUME_GROUP_ID="$target_vg_id"

	# If already syncing aux->master, skip start + monitoring
	vg_is_sync_aux_to_master
	ret=$?
	if [ $ret -eq 2 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Could not read TARGET VG status before starting aux->master sync." 1
	fi
	if [ $ret -eq 0 ]
	then
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - TARGET VG is already syncing aux->master (enabled + consistent_copying + primaryRole=aux). Skipping start.source=aux and monitoring." "1"
	else
		ACTIONS='"start":{"source":"aux"}'
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Step 4.1: Synchronizing primary volumes from AUX to MASTER (target VG action start.source=aux)..." "1"
		resp_act=$(vg_act_status 2>>"$log_file")
		grs_check_write "$resp_act" "Step 4.1: starting aux->master sync on target VG $target_vg_id"

		# Monitor TARGET until aux->master steady state is reached
		vg_wait_sync_aux_to_master "TARGET" 60 "GRS failback aux->master sync"
	fi

	##############################################
	# 4) SOURCE: stop.access=true (disable replication)
	##############################################
	base_url="$source_base_url_local"
	CRN="$source_ws_crn_local"
	CLOUD_INSTANCE_ID="$source_cloud_instance_id_local"
	PVM_ID="$source_pvm_id_local"
	VOLUME_GROUP_ID="$source_vg_id"

	# If already idling, skip stop (same logic as cancel failover)
	local s_state
	s_state=$(vg_sd 2>>"$log_file" | jq -r '.state // empty' 2>>"$log_file")
	if [[ "$s_state" == "idling" ]]
	then
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - SOURCE VG is already in state 'idling' (stopped). Skipping stop.access=true." "1"
	else
		ACTIONS='"stop":{"access":true}'
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Step 4.2: Stopping SOURCE VG to disable replication (VG action stop.access=true)..." "1"
		resp_act=$(vg_act_status 2>>"$log_file")
		grs_check_write "$resp_act" "Step 4.2: stopping SOURCE VG $source_vg_id" "the target aux->master sync was already started"
	fi

	# Wait for replicationStatus=disabled on SOURCE VG
	i=0
	while true
	do
		local rep_status
		rep_status=$(vg_get 2>>"$log_file" | jq -r '.replicationStatus // empty' 2>>"$log_file")
		s_state=$(vg_sd 2>>"$log_file" | jq -r '.state // empty' 2>>"$log_file")

		if [[ -z "$rep_status" ]]
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Could not read source VG replicationStatus while monitoring Step 4.2." 1
		fi

		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Source VG status: state=${s_state:-UNKNOWN}, replicationStatus=$rep_status" "1"

		if [[ "$rep_status" == "disabled" ]]
		then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Source VG replicationStatus is now 'disabled'." "1"
			break
		fi

		i=$((i + 1))
		if (( i >= max_wait ))
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Source VG replicationStatus did not reach 'disabled' after $max_wait minutes (last: $rep_status)." 1
		fi
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Waiting 60 seconds..." "1"
		sleep 60
	done

	##############################################
	# 5) SOURCE: start.source=master (re-enable replication)
	##############################################
	ACTIONS='"start":{"source":"master"}'
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Step 4.3: Re-enabling replication on SOURCE VG (VG action start.source=master)..." "1"
	resp_act=$(vg_act_status 2>>"$log_file")
	grs_check_write "$resp_act" "Step 4.3: re-enabling replication on SOURCE VG $source_vg_id as master" "the SOURCE VG stop was already sent"

	# Wait for replicationStatus=enabled and state=consistent_copying on SOURCE VG
	i=0
	while true
	do
		local rep_status
		rep_status=$(vg_get 2>>"$log_file" | jq -r '.replicationStatus // empty' 2>>"$log_file")
		s_state=$(vg_sd 2>>"$log_file" | jq -r '.state // empty' 2>>"$log_file")

		if [[ -z "$rep_status" || -z "$s_state" ]]
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Could not read source VG status while monitoring Step 4.3." 1
		fi

		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Source VG status: state=$s_state, replicationStatus=$rep_status" "1"

		if [[ "$rep_status" == "enabled" && "$s_state" == "consistent_copying" ]]
		then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Source VG is now replication-enabled and in 'consistent_copying'." "1"
			break
		fi

		i=$((i + 1))
		if (( i >= max_wait ))
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Source VG did not reach replicationStatus=enabled and state=consistent_copying after $max_wait minutes (last: state=$s_state, replicationStatus=$rep_status)." 1
		fi
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Waiting 60 seconds..." "1"
		sleep 60
	done

	##############################################
	# 6) Visibility: monitor TARGET replicationStatus enabled (log it)
	##############################################
	base_url="$target_base_url_local"
	CRN="$target_ws_crn_local"
	CLOUD_INSTANCE_ID="$target_cloud_instance_id_local"
	PVM_ID="$target_pvm_id_local"
	VOLUME_GROUP_ID="$target_vg_id"

	i=0
	while true
	do
		local t_rep
		t_rep=$(vg_get 2>>"$log_file" | jq -r '.replicationStatus // empty' 2>>"$log_file")
		local t_state2
		t_state2=$(vg_sd 2>>"$log_file" | jq -r '.state // empty' 2>>"$log_file")

		if [[ -z "$t_rep" || -z "$t_state2" ]]
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Could not read target VG status while monitoring replication re-enable." 1
		fi

		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Target VG status: state=$t_state2, replicationStatus=$t_rep" "1"

		if [[ "$t_rep" == "enabled" ]]
		then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Target VG replicationStatus is now 'enabled'." "1"
			break
		fi

		i=$((i + 1))
		if (( i >= max_wait ))
		then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - WARNING - Target VG replicationStatus did not report 'enabled' after $max_wait minutes (last: $t_rep). Continuing anyway." "1"
			break
		fi
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Waiting 60 seconds..." "1"
		sleep 60
	done

	abort "$(date +%Y-%m-%d_%H:%M:%S) - === GRS failback completed. You can now start SOURCE_VSI $source_vsi (MASTER) in workspace $source_ws_name. ==="
}
#### END:FUNCTION - GRS Failback (Aux -> Master) ####

#### START:FUNCTION - GRS Reverse Replica (Stay on TARGET as master) ####
# Purpose:
#	After a -grsfailover (activate target) when you decide to KEEP working on TARGET,
#	this reverses replication direction so TARGET becomes the replication master.
#	Safety rules:
#	- SOURCE_VSI must be SHUTOFF (abort otherwise)
#	- TARGET_VSI can be ACTIVE (or SHUTOFF)
do_grs_reverse_replica() {
	# Syntax: bluexport_api.sh -grsreversereplica SOURCE_VSI TARGET_VSI VG_NAME
	# We will:
	#  1) Validate both VSIs in config
	#  2) Ensure SOURCE_VSI is SHUTOFF
	#  3) Resolve SOURCE VG + consistencyGroupName (CG)
	#  4) Resolve TARGET VG by same CG
	#  5) Start aux->master sync on TARGET (VG action start.source=aux)
	#  6) Monitor both sides for replicationStatus/state visibility

	##############################################
	# 0) Validate VSIs in config + capture context
	##############################################
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - === Starting GRS reverse replica (keep working on TARGET) ===" "1"
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Source VSI: $source_vsi | Target VSI: $target_vsi | VG: $vg_name" "1"

	# SOURCE context
	vsi="$source_vsi"
	vsi_id_bluexscrt
	check_locally_VSI_exists
	local source_ws_name
	source_ws_name="$workspace"
	local source_ws_crn_local
	source_ws_crn_local="$shortnamecrn"
	local source_cloud_instance_id_local
	source_cloud_instance_id_local="$CLOUD_INSTANCE_ID"
	local source_base_url_local
	source_base_url_local="$base_url"
	local source_pvm_id_local
	source_pvm_id_local="$PVM_ID"
	local source_vsi_id_local
	source_vsi_id_local="$vsi_id"

	# TARGET context
	vsi="$target_vsi"
	vsi_id_bluexscrt
	check_locally_VSI_exists
	local target_ws_name
	target_ws_name="$workspace"
	local target_ws_crn_local
	target_ws_crn_local="$shortnamecrn"
	local target_cloud_instance_id_local
	target_cloud_instance_id_local="$CLOUD_INSTANCE_ID"
	local target_base_url_local
	target_base_url_local="$base_url"
	local target_pvm_id_local
	target_pvm_id_local="$PVM_ID"
	local target_vsi_id_local
	target_vsi_id_local="$vsi_id"

	##############################################
	# 0.1) Safety: SOURCE VSI must be SHUTOFF
	##############################################
	base_url="$source_base_url_local"
	CRN="$source_ws_crn_local"
	CLOUD_INSTANCE_ID="$source_cloud_instance_id_local"
	PVM_ID="$source_pvm_id_local"
	local s_status
	s_status=$(ins_get 2>>"$log_file" | jq -r '.status // "UNKNOWN"' 2>>"$log_file")
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - SOURCE_VSI $source_vsi status: $s_status" "1"
	if [[ "$s_status" != "SHUTOFF" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - SOURCE_VSI $source_vsi is not SHUTOFF (current: $s_status). Stop it before running -grsreversereplica." 1
	fi

	##############################################
	# 1) Resolve SOURCE VG and consistencyGroupName
	##############################################
	local vg_json
	vg_json=$(vg_ls 2>>"$log_file")
	if [[ -z "$vg_json" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Could not list volume groups in source workspace $source_ws_name." 1
	fi

	local source_vg_id
	source_vg_id=$(echo "$vg_json" | jq -r --arg vg "$vg_name" '.volumeGroups[]? | select(.name == $vg) | .id' 2>>"$log_file")
	if [[ -z "$source_vg_id" || "$source_vg_id" == "null" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Source Volume Group $vg_name not found in source workspace $source_ws_name. Aborting reverse replica." 1
	fi

	local cgname
	cgname=$(echo "$vg_json" | jq -r --arg vg "$vg_name" '.volumeGroups[]? | select(.name == $vg) | .consistencyGroupName' 2>>"$log_file")
	if [[ -z "$cgname" || "$cgname" == "null" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Could not retrieve consistencyGroupName for source VG $vg_name (workspace $source_ws_name)." 1
	fi
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Source workspace: $source_ws_name (id=$source_cloud_instance_id_local) - Source VG ID=$source_vg_id - consistencyGroupName=$cgname" "1"

	##############################################
	# 2) Resolve TARGET VG by consistencyGroupName
	##############################################
	base_url="$target_base_url_local"
	CRN="$target_ws_crn_local"
	CLOUD_INSTANCE_ID="$target_cloud_instance_id_local"
	PVM_ID="$target_pvm_id_local"

	local t_vg_json
	t_vg_json=$(vg_ls 2>>"$log_file")
	if [[ -z "$t_vg_json" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Could not list volume groups in target workspace $target_ws_name." 1
	fi

	local target_vg_id target_vg_count
	target_vg_id=$(echo "$t_vg_json" | jq -r --arg cg "$cgname" '.volumeGroups[]? | select(.consistencyGroupName == $cg) | .id' 2>>"$log_file")
	# (1.20.0) head -n1 used to silently pick the first of several matches. Count them:
	# no write has happened yet in this function, so an ambiguous match aborts here.
	target_vg_count=$(printf '%s\n' "$target_vg_id" | grep -c .)
	if [ "$target_vg_count" -gt 1 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - More than one target Volume Group with consistencyGroupName $cgname in workspace $target_ws_name: $(printf '%s' "$target_vg_id" | tr '\n' ' '). Aborting reverse replica; nothing was changed." 1
	fi
	target_vg_id=$(printf '%s\n' "$target_vg_id" | head -n1)
	if [[ -z "$target_vg_id" || "$target_vg_id" == "null" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Target Volume Group for consistencyGroupName $cgname not found in target workspace $target_ws_name. Aborting reverse replica." 1
	fi
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Target workspace: $target_ws_name (id=$target_cloud_instance_id_local) - Target VG ID=$target_vg_id" "1"

	##############################################
	# 3) TARGET: start.source=aux (sync aux -> master)
	##############################################
	VOLUME_GROUP_ID="$target_vg_id"

	# If already syncing aux->master, skip start + monitoring
	vg_is_sync_aux_to_master
	ret=$?
	if [ $ret -eq 2 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Could not read TARGET VG status before starting aux->master sync." 1
	fi
	if [ $ret -eq 0 ]
	then
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - TARGET VG is already syncing aux->master (enabled + consistent_copying + primaryRole=aux). Skipping start.source=aux and monitoring." "1"
	else
		ACTIONS='"start":{"source":"aux"}'
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Step 3: Starting aux->master sync on TARGET VG (VG action start.source=aux)..." "1"
		resp_act=$(vg_act_status 2>>"$log_file")
		grs_check_write "$resp_act" "Step 3: starting aux->master sync on TARGET VG $target_vg_id"

		# Monitor TARGET until aux->master steady state is reached
		vg_wait_sync_aux_to_master "TARGET" 60 "GRS reverse replica aux->master sync"
	fi

	##############################################
	# 4) SOURCE: monitor replication visibility
	##############################################
	base_url="$source_base_url_local"
	CRN="$source_ws_crn_local"
	CLOUD_INSTANCE_ID="$source_cloud_instance_id_local"
	PVM_ID="$source_pvm_id_local"
	VOLUME_GROUP_ID="$source_vg_id"

	local s_rep s_state s_primary
	s_rep=$(vg_get 2>>"$log_file" | jq -r '.replicationStatus // "UNKNOWN"' 2>>"$log_file")
	s_state=$(vg_sd 2>>"$log_file" | jq -r '.state // "UNKNOWN"' 2>>"$log_file")
	s_primary=$(vg_get 2>>"$log_file" | jq -r '.primaryRole // "UNKNOWN"' 2>>"$log_file")
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - SOURCE VG after reverse: state=$s_state, replicationStatus=$s_rep, primaryRole=$s_primary" "1"

	abort "$(date +%Y-%m-%d_%H:%M:%S) - === GRS reverse replica completed. TARGET is now MASTER for CG $cgname. ==="
}
#### END:FUNCTION - GRS Reverse Replica (Stay on TARGET as master) ####

#### START:FUNCTION - Start VSI (do_start_vsi) ####
do_start_vsi() {
	local vsi="$1"
	if [[ -z "$vsi" ]]; then
		abort "`date +%Y-%m-%d_%H:%M:%S` - VSI_NAME is missing. Syntax: bluexport_api.sh -vsistart VSI_NAME" 1
	fi

	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - === Starting VSI $vsi ===" "1"

	# Resolve VSI and workspace (no iASP work)
	flagj=1
	vsi="$vsi"
	vsi_id_bluexscrt
	check_locally_VSI_exists

	# Get current VSI status (must be SHUTOFF before starting)
	local vsi_status
	vsi_status=$(ins_get 2>>"$log_file" | jq -r '.status // "UNKNOWN"' 2>>"$log_file")
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - VSI $vsi is in status: $vsi_status." "1"

	if [[ "$vsi_status" != "SHUTOFF" ]]; then
		abort "`date +%Y-%m-%d_%H:%M:%S` - VSI $vsi is not in SHUTOFF status (current: $vsi_status). Aborting start." 1
	fi

	# Start action
	ACTIONS="\"action\": \"start\""
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Calling Instance Action API (start) for VSI $vsi (PVM_ID $PVM_ID)..." "1"
	ins_act 2>>"$log_file" | tee -a "$log_file"

	# Monitor like -vsisrcmon START (no false failures while still SHUTOFF, no early exit on first ACTIVE)
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Start action requested for VSI $vsi. Monitoring START sequence until status=ACTIVE and SRC=00000000 (every 30 seconds)..." "1"
	do_vsi_srcmon "$vsi" "START"
}
#### END:FUNCTION - Start VSI (do_start_vsi) ####

#### START:FUNCTION - VSI Operation (do_vsi_oper) ####
# Usage:
#   -vsioper VSI_NAME BOOT_MODE OPERATING_MODE
#   BOOT_MODE: a|b|c|d
#   OPERATING_MODE: normal|manual
do_vsi_oper() {
	local vsi="$1"
	local boot_mode="$2"
	local operating_mode="$3"

	if [[ -z "$vsi" || -z "$boot_mode" || -z "$operating_mode" ]]; then
		abort "`date +%Y-%m-%d_%H:%M:%S` - VSI_NAME, BOOT_MODE and OPERATING_MODE are mandatory. Syntax: bluexport_api.sh -vsioper VSI_NAME BOOT_MODE OPERATING_MODE" 1
	fi
	# Validate BOOT_MODE
	case "$boot_mode" in
		a|b|c|d) ;;
		*) abort "`date +%Y-%m-%d_%H:%M:%S` - Invalid BOOT_MODE '$boot_mode'. Valid values: a, b, c, d." 1 ;;
	esac
	# Validate OPERATING_MODE
	case "$operating_mode" in
		manual|normal) ;;
		*) abort "`date +%Y-%m-%d_%H:%M:%S` - Invalid OPERATING_MODE '$operating_mode'. Valid values: normal, manual." 1 ;;
	esac
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - === Setting VSI operation for $vsi ===" "1"
	# Resolver VSI e workspace
	flagj=1
	vsi="$vsi"
	vsi_id_bluexscrt
	check_locally_VSI_exists
	# Construir JSON da operação
	local op_fields="\"bootMode\": \"$boot_mode\", \"operatingMode\": \"$operating_mode\""
	ACTIONS="\"operationType\": \"boot\", \"operation\": { $op_fields }"
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Calling Instance Operation API (operationType=boot) for VSI $vsi (PVM_ID $PVM_ID) with: $op_fields" "1"
	ins_oper 2>>"$log_file" | tee -a "$log_file"
	abort "`date +%Y-%m-%d_%H:%M:%S` - === Instance operation requested for VSI $vsi."
}
#### END:FUNCTION - VSI Operation (do_vsi_oper) ####

#### START:FUNCTION - VSI Task Operation (do_vsi_task) ####
# TASK valid values:
#   dston, retrydump, consoleservice, iopreset, remotedstoff,w
#   remotedston, iopdump, dumprestart
do_vsi_task() {
	local vsi="$1"
	local task="$2"
	if [[ -z "$vsi" || -z "$task" ]]; then
		abort "`date +%Y-%m-%d_%H:%M:%S` - VSI_NAME and TASK are mandatory. Syntax: bluexport_api.sh -vsitask VSI_NAME TASK" 1
	fi
	case "$task" in
		dston|retrydump|consoleservice|iopreset|remotedstoff|remotedston|iopdump|dumprestart)
			;;
		*)
			abort "`date +%Y-%m-%d_%H:%M:%S` - Invalid TASK '$task'. Valid values: dston, retrydump, consoleservice, iopreset, remotedstoff, remotedston, iopdump, dumprestart." 1
			;;
	esac
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - === Running VSI task '$task' on $vsi ===" "1"
	# Resolve VSI and workspace (no iASP work)
	flagj=1
	vsi="$vsi"
	vsi_id_bluexscrt
	check_locally_VSI_exists
	ACTIONS="\"operationType\": \"job\", \"operation\": { \"task\": \"$task\" }"
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Calling Instance Operation API (operationType=job, task=$task) for VSI $vsi (PVM_ID $PVM_ID)..." "1"
	ins_oper 2>>"$log_file" | tee -a "$log_file"
	abort "`date +%Y-%m-%d_%H:%M:%S` - === Task '$task' requested for VSI $vsi."
}
#### END:FUNCTION - VSI Task Operation (do_vsi_task) ####

#### START:FUNCTION - VSI SRC Monitor (do_vsi_srcmon) ####
# Usage:
#   -vsisrcmon VSI_NAME START|SHUTOFF
# Notes:
#   START   -> waits for VSI to be truly started:
#              - status must reach ACTIVE
#              - SRC may briefly show 00000000 before it starts rolling
#              - we wait up to 3 minutes to detect rolling; if rolling is detected, we wait until SRC returns to 00000000 (stable)
#   SHUTOFF -> waits for status=SHUTOFF (SRC ignored, because SRC may reach 00000000 before SHUTOFF)
do_vsi_srcmon() {
	local vsi_name="$1"
	local mode="$2"
	local mode_u=""

	if [[ -z "$vsi_name" || -z "$mode" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - VSI_NAME or MODE is missing. Syntax: bluexport_api.sh -vsisrcmon VSI_NAME START|SHUTOFF" 1
	fi

	mode_u=$(echo "$mode" | tr '[:lower:]' '[:upper:]')
	if [[ "$mode_u" != "START" && "$mode_u" != "SHUTOFF" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Invalid MODE '$mode'. Use START or SHUTOFF. Syntax: bluexport_api.sh -vsisrcmon VSI_NAME START|SHUTOFF" 1
	fi

	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - === Monitoring SRC/Status for VSI $vsi_name (mode: $mode_u) ===" "1"

	# Resolve VSI and workspace (keeps script behavior consistent with other flags)
	flagj=1
	vsi="$vsi_name"
	vsi_id_bluexscrt
	check_locally_VSI_exists

	# START mode anti-false-positive logic (same principle as do_start_vsi)
	local grace_seconds=180
	local first_active_ts=0
	local saw_nonzero=0
	local stable_zero=0

	# Bounds and token upkeep, lifted from job_monitor()/wait_for_job(), which
	# have had all three of these since captures started outliving their token.
	# This loop had none of them, and it is reached by -vsistart too, since
	# do_start_vsi() delegates its entire monitoring phase here.
	#
	#  - IAM tokens expire in ~3600s. A large IBM i IPL after an abnormal end
	#    running past the hour is routine, not exotic.
	#  - An IPL that never reaches SRC 00000000 (hung IPL, wrong boot mode, a
	#    B-side problem) previously polled until somebody killed the process.
	#  - A run of unreadable responses previously retried forever, 15s apart,
	#    with no counter and nothing said about why.
	#
	# BLUEXPORT_SRCMON_TIMEOUT overrides the overall bound (seconds) without
	# editing this script; the 4h default is deliberately generous, since
	# stopping a monitor early on a slow-but-healthy IPL is its own failure.
	local srcmon_start_ts
	srcmon_start_ts=$(date +%s)
	local srcmon_timeout_secs="${BLUEXPORT_SRCMON_TIMEOUT:-14400}"
	local srcmon_fail_count=0
	local srcmon_max_fail=10
	local token_refresh_secs="${iam_refresh_secs:-2700}"
	local srcmon_now_ts srcmon_elapsed vsi_raw http_code

	while true
	do
		# Overall bound. Reported as a timeout, and explicitly NOT as a
		# failed IPL - the VSI is very likely still doing something.
		srcmon_now_ts=$(date +%s)
		srcmon_elapsed=$((srcmon_now_ts - srcmon_start_ts))
		if [ "$srcmon_elapsed" -ge "$srcmon_timeout_secs" ]
		then
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - === Monitoring of VSI $vsi_name TIMED OUT after ${srcmon_elapsed}s (limit ${srcmon_timeout_secs}s). ===" "1"
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - The VSI has NOT been declared failed - it may still be running. Last seen Status: ${vsi_status:-n/a}, SRC: ${vsi_src:-n/a}." "1"
			abort "`date +%Y-%m-%d_%H:%M:%S` - Re-run 'bluexport_api.sh -vsisrcmon $vsi_name $mode_u' to resume monitoring, or raise BLUEXPORT_SRCMON_TIMEOUT." 1
		fi

		# Refresh the IAM token before it expires, so a long IPL never hits an
		# auth failure mid-poll.
		if [[ -n "$iam_token_epoch" ]] && (( $(date +%s) - iam_token_epoch >= token_refresh_secs ))
		then
			get_iam_token refresh
		fi

		# Read status via ins_get_code() so an unanswerable request is told
		# apart from a real LPAR state. vsi_status is left EMPTY unless the
		# API returned 2xx with an actual .status - never defaulted to
		# "UNKNOWN", which used to make an expired token look like a dead LPAR.
		vsi_raw=$(ins_get_code)
		http_code="${vsi_raw##*$'\n'}"
		vsi_json="${vsi_raw%$'\n'*}"
		vsi_status=""
		if [[ "$http_code" == 2* ]]
		then
			vsi_status=$(printf '%s' "$vsi_json" | jq -r '.status // empty' 2>>"$log_file")
		fi

		if [[ -z "$vsi_status" ]]
		then
			srcmon_fail_count=$((srcmon_fail_count + 1))
			echo "`date +%Y-%m-%d_%H:%M:%S` - WARNING - Could not read status for VSI $vsi_name (HTTP ${http_code:-?}, attempt $srcmon_fail_count/$srcmon_max_fail). Response: $vsi_json" >> "$log_file"
			if [[ "$http_code" == "401" ]]
			then
				echoscreen "`date +%Y-%m-%d_%H:%M:%S` - IAM token was rejected (HTTP 401). Refreshing token..." "1"
				get_iam_token refresh
			fi
			if [ "$srcmon_fail_count" -ge "$srcmon_max_fail" ]
			then
				echoscreen "`date +%Y-%m-%d_%H:%M:%S` - FAILED to read status for VSI $vsi_name after $srcmon_max_fail consecutive attempts (last HTTP ${http_code:-?})." "1"
				abort "`date +%Y-%m-%d_%H:%M:%S` - Monitoring stopped. This is an API/connectivity failure, NOT a statement about the VSI. Check $log_file." 1
			fi
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - WARNING - Transient error reading status for VSI $vsi_name (HTTP ${http_code:-?}). Retrying in 30s ($srcmon_fail_count/$srcmon_max_fail)..." "1"
			spin_wait 30 "Retrying VSI status check"
			continue
		fi
		srcmon_fail_count=0

		# srcs is an array-of-array, like: "srcs": [[{ "src": "00000000", ... }]]
		vsi_src=$(printf '%s' "$vsi_json" | jq -r '.srcs[0][0].src // "UNKNOWN"' 2>>"$log_file")

		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - VSI $vsi_name - Status: $vsi_status, SRC: $vsi_src" "1"

		# Check for UNKNOWN status (abnormal state).
		# Reached ONLY when the API answered 2xx and the status it reported is
		# literally "UNKNOWN". It is no longer the catch-all it used to be:
		# an unreadable response is handled by the transient branch above,
		# so this abort now means what it says.
		if [[ "$vsi_status" == "UNKNOWN" ]]
		then
			if [[ "$mode_u" == "START" ]]
			then
				abort "`date +%Y-%m-%d_%H:%M:%S` - === VSI $vsi_name entered UNKNOWN status. The LPAR/VSI is not starting. SRC monitoring terminated. ===" 1
			else
				abort "`date +%Y-%m-%d_%H:%M:%S` - === VSI $vsi_name entered UNKNOWN status. The LPAR/VSI is not shutting down properly. SRC monitoring terminated. ===" 1
			fi
		fi

		if [[ "$mode_u" == "SHUTOFF" ]]
		then
			# SHUTOFF mode: ignore SRC as a completion condition
			if [[ "$vsi_status" == "SHUTOFF" ]]
			then
				abort "`date +%Y-%m-%d_%H:%M:%S` - === VSI $vsi_name reached status SHUTOFF. SRC monitoring completed. ==="
			fi

			sleep 15
			continue
		fi

		##############################################
		# START mode
		##############################################
		# If not ACTIVE yet, just keep waiting (SHUTOFF here is normal while starting)
		if [[ "$vsi_status" != "ACTIVE" ]]
		then
			sleep 15
			continue
		fi

		# VSI is ACTIVE at this point
		if [[ "$vsi_src" != "00000000" ]]
		then
			# SRC is rolling
			saw_nonzero=1
			stable_zero=0
			sleep 15
			continue
		fi

		# ACTIVE + SRC=00000000
		if [[ "$saw_nonzero" == "1" ]]
		then
			# We already observed SRC rolling; require a tiny bit of stability at 00000000
			stable_zero=$((stable_zero + 1))
			if [ "$stable_zero" -ge 2 ]
			then
				abort "`date +%Y-%m-%d_%H:%M:%S` - === VSI $vsi_name reached status ACTIVE with SRC 00000000 (stable). SRC monitoring completed. ==="
			fi
			sleep 15
			continue
		fi

		# We have NOT observed any non-zero SRC yet (avoid false-positive: ACTIVE + 00000000 too early)
		if [ "$first_active_ts" -eq 0 ]
		then
			first_active_ts=$(date +%s)
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - VSI $vsi_name reached ACTIVE with SRC=00000000. Waiting up to ${grace_seconds}s to detect SRC rolling before declaring START completed..." "1"
			sleep $grace_seconds
			continue
		fi

		now_ts=$(date +%s)
		elapsed=$((now_ts - first_active_ts))
		if [ "$elapsed" -lt "$grace_seconds" ]
		then
			# Still inside grace window, keep monitoring
			sleep 30
			continue
		fi

		# Grace window elapsed and we never saw SRC rolling
		abort "`date +%Y-%m-%d_%H:%M:%S` - === VSI $vsi_name reached status ACTIVE with SRC 00000000 and no SRC rolling was detected after ${grace_seconds}s. SRC monitoring completed. ==="
	done
}
#### END:FUNCTION - VSI SRC Monitor (do_vsi_srcmon) ####

#### START:FUNCTION - Attach volumes to a VSI by common name (do_vsi_attach_volumes) ####
# Usage:
# 	-attachvolumes VOLUMES_COMMON_NAME VSI_NAME
# Notes:
# 	- VSI must be SHUTOFF (safe operation)
# 	- Attaches all volumes in the workspace whose name contains VOLUMES_COMMON_NAME
# 	- Skips volumes already attached to the VSI
# 	- If VSI has no volumes attached yet, boot volume MUST be attached first (PowerVS requirement)
do_vsi_attach_volumes() {
	local vol_common_name="$1"
	local vsi_name="$2"

	if [[ -z "$vol_common_name" || -z "$vsi_name" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Arguments missing!! Syntax: bluexport_api.sh -attachvolumes VOLUMES_COMMON_NAME VSI_NAME" 1
	fi

	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - === Attaching volumes matching '$vol_common_name' to VSI $vsi_name ===" "1"

	# Resolve VSI and workspace
	flagj=1
	vsi="$vsi_name"
	vsi_id_bluexscrt
	check_locally_VSI_exists

	# VSI must be SHUTOFF
	local vsi_status
	vsi_status=$(ins_get 2>>"$log_file" | jq -r '.status // "UNKNOWN"' 2>>"$log_file")
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - VSI $vsi_name is in status: $vsi_status." "1"
	if [[ "$vsi_status" != "SHUTOFF" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - VSI $vsi_name is not SHUTOFF (current: $vsi_status). Stop it before running -attachvolumes." 1
	fi

	# Current volumes already attached to this VSI
	local attached_ids
	attached_ids=$(ins_vol_ls 2>>"$log_file" | jq -r '.volumes[]? | .volumeID' 2>>"$log_file" | tr '\n' ' ')

	local cur_count
	cur_count=$(ins_vol_ls 2>>"$log_file" | jq -r '.volumes | length' 2>>"$log_file")
	[[ -z "$cur_count" || "$cur_count" == "null" ]] && cur_count=0

	# Get all volumes in workspace matching common name (contains)
	local vols_json
	vols_json=$(vol_ls 2>>"$log_file")
	if [[ -z "$vols_json" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Could not list volumes via API (vol_ls)." 1
	fi

	local match_lines
	match_lines=$(echo "$vols_json" | jq -r --arg p "$vol_common_name" '.volumes[]? | select(.name | contains($p)) | "\(.volumeID) \(.name)"' 2>>"$log_file")
	if [[ -z "$match_lines" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - No volumes found in workspace $shortnamecrn with name containing '$vol_common_name'. Nothing to attach." 1
	fi

	# Identify boot volume among matches
	# We try metadata first (best), then fallback to name pattern (boot / BOOT / -boot- / _boot_)
	local boot_line
	boot_line=$(echo "$vols_json" | jq -r --arg p "$vol_common_name" '
		.volumes[]?
		| select(.name | contains($p))
		| select(
			(.bootable? == true) or
			(.isBootVolume? == true) or
			(.bootVolume? == true) or
			(.volumeType? == "boot") or
			(.type? == "boot") or
			(.name | test("(^|[-_])boot($|[-_])"; "i"))
		)
		| "\(.volumeID) \(.name)"' 2>>"$log_file" | head -n 1)

	local boot_vol_id=""
	local boot_vol_name=""
	if [[ -n "$boot_line" ]]
	then
		boot_vol_id=$(echo "$boot_line" | awk '{print $1}')
		boot_vol_name=$(echo "$boot_line" | awk '{print $2}')
	fi

	# Build list to attach (exclude already attached)
	# Also build "remaining" excluding boot (boot will be attached first if needed)
	local ids_json=""
	local attach_count=0
	local names_to_attach=""
	local ids_json_rest=""
	local attach_count_rest=0
	local names_to_attach_rest=""

	while IFS= read -r line
	do
		[[ -z "$line" ]] && continue
		local vid vname
		vid=$(echo "$line" | awk '{print $1}')
		vname=$(echo "$line" | awk '{print $2}')

		# Skip if already attached
		if echo " $attached_ids " | grep -q " $vid "
		then
			continue
		fi

		# Overall list (for reporting)
		if [[ -n "$ids_json" ]]
		then
			ids_json="$ids_json,\"$vid\""
		else
			ids_json="\"$vid\""
		fi
		attach_count=$((attach_count + 1))
		names_to_attach="$names_to_attach $vname"

		# Remaining list (exclude boot)
		if [[ -n "$boot_vol_id" && "$vid" == "$boot_vol_id" ]]
		then
			continue
		fi
		if [[ -n "$ids_json_rest" ]]
		then
			ids_json_rest="$ids_json_rest,\"$vid\""
		else
			ids_json_rest="\"$vid\""
		fi
		attach_count_rest=$((attach_count_rest + 1))
		names_to_attach_rest="$names_to_attach_rest $vname"
	done <<< "$match_lines"

	if [[ $attach_count -eq 0 ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - All volumes matching '$vol_common_name' are already attached to VSI $vsi_name. Nothing to do."
	fi

	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Volumes to attach ($attach_count):$names_to_attach" "1"

	#########################################################
	# If VSI currently has 0 volumes, attach BOOT first      #
	#########################################################
	if [[ "$cur_count" -eq 0 ]]
	then
		if [[ -z "$boot_vol_id" ]]
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - VSI $vsi_name has no volumes attached, and I could not identify a boot volume among matches for '$vol_common_name'. Ensure the boot volume name includes the common string, or contains 'boot' in the name." 1
		fi

		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - VSI has no volumes attached. Attaching BOOT volume first: $boot_vol_name ($boot_vol_id)" "1"
		ACTIONS="\"volumeIDs\":[\"$boot_vol_id\"]"
		local resp_boot
		resp_boot=$(vol_att_multi 2>>"$log_file")
		echo "$resp_boot" >>"$log_file"
		if echo "$resp_boot" | jq -e '.code? != null or .error? != null or .description? != null' >/dev/null 2>&1
		then
			errmsg=$(echo "$resp_boot" | jq -r '.message // .error // .description // "Unknown error"' 2>/dev/null)
			abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Error attaching boot volume to $vsi_name: $errmsg" 1
		fi

		# Wait until boot volume is visible on VSI
		local max_boot_wait=60
		local boot_try=0
		while true
		do
			local seen_boot
			seen_boot=$(ins_vol_ls 2>>"$log_file" | jq -r --arg vid "$boot_vol_id" '.volumes[]? | select(.volumeID==$vid) | .volumeID' 2>>"$log_file")
			if [[ "$seen_boot" == "$boot_vol_id" ]]
			then
				echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Boot volume is now attached to $vsi_name. Proceeding with remaining volumes..." "1"
				break
			fi
			boot_try=$((boot_try + 1))
			if (( boot_try >= max_boot_wait ))
			then
				abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Boot volume ($boot_vol_name / $boot_vol_id) did not become attached/visible on $vsi_name after ~10 minutes. Aborting." 1
			fi
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Boot volume still attaching on $vsi_name... waiting 10 seconds (attempt $boot_try/$max_boot_wait)" "1"
			sleep 10
		done
	fi

	###########################################
	# Attach remaining volumes (excluding boot)
	###########################################
	if [[ -n "$boot_vol_id" ]]
	then
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Boot volume detected: $boot_vol_name ($boot_vol_id)" "1"
	fi

	if [[ -z "$ids_json_rest" || "$attach_count_rest" -eq 0 ]]
	then
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - No additional volumes to attach (only boot or all already attached)." "1"
	else
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Attaching remaining volumes ($attach_count_rest):$names_to_attach_rest" "1"
		ACTIONS="\"volumeIDs\":[${ids_json_rest}]"
		local resp_att
		resp_att=$(vol_att_multi 2>>"$log_file")
		echo "$resp_att" >>"$log_file"
		if echo "$resp_att" | jq -e '.code? != null or .error? != null or .description? != null' >/dev/null 2>&1
		then
			errmsg=$(echo "$resp_att" | jq -r '.message // .error // .description // "Unknown error"' 2>/dev/null)
			abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Error attaching volumes to $vsi_name: $errmsg" 1
		fi
	fi

	# Wait for attach completion (async)
	local expected_min
	local base_count
	base_count=$(echo "$attached_ids" | wc -w | awk '{print $1}')
	[[ -z "$base_count" ]] && base_count=0

	# If VSI had 0 before and we attached boot, total expected increases by 1 + attach_count_rest
	# Otherwise, expected increases by attach_count (excluding already attached)
	if [[ "$cur_count" -eq 0 ]]
	then
		expected_min=$(( 1 + attach_count_rest ))
	else
		expected_min=$(( base_count + attach_count ))
	fi
	if [[ -z "$expected_min" || "$expected_min" -le 0 ]]
	then
		expected_min=$attach_count
	fi

	local max_wait=60
	local i=0
	while true
	do
		local cur
		cur=$(ins_vol_ls 2>>"$log_file" | jq -r '.volumes | length' 2>>"$log_file")
		if [[ -z "$cur" || "$cur" == "null" ]]
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Could not read attached volumes count while waiting for attaches." 1
		fi
		if (( cur >= expected_min ))
		then
			break
		fi
		i=$((i + 1))
		if (( i >= max_wait ))
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - VSI $vsi_name did not reach $expected_min attached volumes after ~10 minutes (last count=$cur)." 1
		fi
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Volumes still attaching on $vsi_name... currently $cur/$expected_min attached. Waiting 10 seconds (attempt $i/$max_wait)" "1"
		sleep 10
	done

	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - === Successfully requested attach of volumes to VSI $vsi_name. ===" "1"
	abort "`date +%Y-%m-%d_%H:%M:%S` - VSI $vsi_name now has $(ins_vol_ls 2>>"$log_file" | jq -r '.volumes | length' 2>>"$log_file") attached volumes."
}
#### END:FUNCTION - Attach volumes to a VSI by common name (do_vsi_attach_volumes) ####


#### START:FUNCTION - Detach ALL volumes from a VSI (do_vsi_detach_volumes) ####
# Usage:
# 	-detachvolumes VSI_NAME
# Notes:
# 	- VSI must be SHUTOFF (safe operation)
# 	- Detaches all volumes currently attached to the VSI
do_vsi_detach_volumes() {
	local vsi_name="$1"
	if [[ -z "$vsi_name" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - VSI_NAME is missing. Syntax: bluexport_api.sh -detachvolumes VSI_NAME" 1
	fi

	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - === Detaching ALL volumes from VSI $vsi_name ===" "1"

	# Resolve VSI and workspace
	flagj=1
	vsi="$vsi_name"
	vsi_id_bluexscrt
	check_locally_VSI_exists

	# VSI must be SHUTOFF
	local vsi_status
	vsi_status=$(ins_get 2>>"$log_file" | jq -r '.status // "UNKNOWN"' 2>>"$log_file")
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - VSI $vsi_name is in status: $vsi_status." "1"
	if [[ "$vsi_status" != "SHUTOFF" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - VSI $vsi_name is not SHUTOFF (current: $vsi_status). Stop it before running -detachvolumes." 1
	fi

	# Get attached volume IDs
	local vol_ids
	vol_ids=$(ins_vol_ls 2>>"$log_file" | jq -r '.volumes[]? | .volumeID' 2>>"$log_file")
	if [[ -z "$vol_ids" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - VSI $vsi_name has no attached volumes. Nothing to detach."
	fi

	local count
	count=$(echo "$vol_ids" | wc -l | tr -d ' ')
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - VSI $vsi_name has $count attached volumes. Proceeding with bulk detach..." "1"

	local ids_json
	ids_json=$(echo "$vol_ids" | awk '{print "\""$1"\""}' | paste -sd, -)
	ACTIONS="\"volumeIDs\":[${ids_json}]"

	local resp_det
	resp_det=$(ins_vol_bdet 2>>"$log_file")
	echo "$resp_det" >>"$log_file"
	if echo "$resp_det" | jq -e '.code? != null or .error? != null' >/dev/null 2>&1
	then
		errmsg=$(echo "$resp_det" | jq -r '.message // .error // .description // "Unknown error"' 2>/dev/null)
		abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Error detaching volumes from $vsi_name: $errmsg" 1
	fi

	# Wait until no volumes are attached (async)
	local max_wait=60
	local i=0
	while true
	do
		local cur_count
		cur_count=$(ins_vol_ls 2>>"$log_file" | jq -r '.volumes | length' 2>>"$log_file")
		if [[ -z "$cur_count" || "$cur_count" == "null" ]]
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Could not read attached volumes count while waiting for detaches." 1
		fi
		if (( cur_count == 0 ))
		then
			break
		fi
		i=$((i + 1))
		if (( i >= max_wait ))
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - VSI $vsi_name still has $cur_count attached volumes after ~10 minutes." 1
		fi
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Volumes still detaching from $vsi_name... currently $cur_count attached. Waiting 10 seconds (attempt $i/$max_wait)" "1"
		sleep 10
	done

	abort "`date +%Y-%m-%d_%H:%M:%S` - === Successfully detached all volumes from VSI $vsi_name. ==="
}
#### END:FUNCTION - Detach ALL volumes from a VSI (do_vsi_detach_volumes) ####

#### START:FUNCTION - Delete Image (do_img_delete) ####
do_img_delete() {
	local img_name="$1"
	if [[ -z "$img_name" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - IMG_NAME is missing. Syntax: bluexport_api.sh -imgdel IMG_NAME" 1
	fi
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - === Starting Image Delete for $img_name in all Workspaces ===" "1"
	# Workspaces: use keys list, and ALWAYS resolve display name from JSON (no fragile wsname/allws ordering tricks)
	# Root cause of the "wrong workspace in output" bug: $allws comes from jq keys (sorted),
	# while $wsnames comes from jq to_entries (object iteration order). They don't reliably line up.
	read -r -a allws_array <<< "$allws" 
	local IMAGE_ID=""
	local found_ws=""
	local found_ws_name=""
	local found_crn="" found_cloud_instance_id="" found_base_url="" match_count=0 match_list=""
	# Percorrer todas as workspaces definidas
	for ws in "${allws_array[@]}"
	do
		CRN=$(jq -r --arg ws "$ws" '.workspaces[$ws].crn' "$bluexscrt")
		CLOUD_INSTANCE_ID=$(jq -r --arg ws "$ws" '.workspaces[$ws].id' "$bluexscrt")
        full_ws_name=$(jq -r --arg ws "$ws" '.workspaces[$ws].name' "$bluexscrt" 2>>"$log_file")
		if [[ -z "$full_ws_name" || "$full_ws_name" == "null" ]]; then full_ws_name="$ws"; fi
		if [[ -z "$CRN" || "$CRN" == "null" || -z "$CLOUD_INSTANCE_ID" || "$CLOUD_INSTANCE_ID" == "null" ]]
		then
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Workspace $ws ($full_ws_name) missing CRN or ID in $bluexscrt, skipping." "1"
			continue
		fi
		# Extrair a região do CRN (ex: mad02, eu-de-1, etc.) e mapear para base_url
		region_api=$(echo "$CRN" | sed -n 's/.*power-iaas:\([^:]*\):.*/\1/p' | tr '-' '_')
		if [[ -z "$region_api" ]]
		then
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Could not parse region from CRN $CRN for workspace $full_ws_name, skipping." "1"
			continue
		fi
		base_url_var="base_${region_api}"
		base_url="${!base_url_var}"
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Checking for Image $img_name in Workspace $full_ws_name..." "1"
		local imgs_json
		imgs_json=$(img_ls 2>>"$log_file")
		if [[ -z "$imgs_json" ]]
		then
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Could not retrieve image list via API in workspace $full_ws_name, skipping." "1"
			continue
		fi
		# (1.18.6) Every workspace is searched and every match counted. Before, the first
		# match in the first workspace won (head -n1, then break) and was deleted with no
		# confirmation - so two images sharing a name, in one workspace or in two, lost
		# whichever the API happened to list first.
		local ws_ids
		ws_ids=$(echo "$imgs_json" | jq -r --arg name "$img_name" '.images[]? | select(.name == $name) | .imageID' 2>>"$log_file")
		local one_id
		for one_id in $ws_ids
		do
			[ -z "$one_id" ] && continue
			[ "$one_id" = "null" ] && continue
			match_count=$((match_count + 1))
			match_list="$match_list
  - $full_ws_name: $one_id"
			IMAGE_ID="$one_id"
			found_ws="$ws"
			found_ws_name="$full_ws_name"
			found_crn="$CRN"
			found_cloud_instance_id="$CLOUD_INSTANCE_ID"
			found_base_url="$base_url"
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Image $img_name found in Workspace $found_ws_name with ID: $IMAGE_ID" "1"
		done
	done
	if [ "$match_count" -eq 0 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Image with name $img_name not found in any Workspace." 1
	fi
	if [ "$match_count" -gt 1 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Image name $img_name is ambiguous: $match_count images carry it and this command deletes by name. Nothing deleted. Matches:$match_list" 1
	fi
	CRN="$found_crn"
	CLOUD_INSTANCE_ID="$found_cloud_instance_id"
	base_url="$found_base_url"
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Calling Image Delete API for $img_name (ID $IMAGE_ID) in Workspace $found_ws_name..." "1"
	# Chamar API de delete na workspace onde foi encontrada
	del_output=$(img_del 2>>"$log_file")
	ret=$?
	printf '%s\n' "$del_output" >> "$log_file"
	# (1.18.6) The HTTP status is read, not inferred from the body's shape: a 4xx with an empty
	# or non-JSON body used to be reported as a successful delete.
	if [ $ret -ne 0 ] || ! delete_check "$del_output" "image $img_name"
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Image $img_name (ID $IMAGE_ID) was NOT deleted from Workspace $found_ws_name." 1
	fi
	abort "`date +%Y-%m-%d_%H:%M:%S` - === Image $img_name (ID $IMAGE_ID) deleted successfully from Workspace $found_ws_name. ==="
}
#### END:FUNCTION - Delete Image (do_img_delete) ####

####  START:FUNCTION - Load HMAC keys from a COS Service Credentials JSON file (OTHERACCOUNT)  ####
# load_hmac_keys HMAC_JSON_FILE
#   Reads .cos_hmac_keys.access_key_id / .cos_hmac_keys.secret_access_key from the given
#   JSON file (exact format IBM Cloud COS "Service credentials" gives you) and sets the
#   globals hmac_access_key / hmac_secret_key. Aborts (exit 1) on any parse failure or
#   missing field, instead of leaving the caller with silently empty keys.
load_hmac_keys() {
	local hmac_file="$1"
	hmac_access_key=""
	hmac_secret_key=""
	if ! jq -e . "$hmac_file" >/dev/null 2>&1
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - HMAC keys JSON file $hmac_file is not valid JSON. Aborting..." 1
	fi
	hmac_access_key=$(jq -r '.cos_hmac_keys.access_key_id // empty' "$hmac_file")
	hmac_secret_key=$(jq -r '.cos_hmac_keys.secret_access_key // empty' "$hmac_file")
	if [[ -z "$hmac_access_key" || -z "$hmac_secret_key" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - HMAC keys JSON file $hmac_file is missing .cos_hmac_keys.access_key_id or .cos_hmac_keys.secret_access_key. Aborting..." 1
	fi
}
####  END:FUNCTION - Load HMAC keys from a COS Service Credentials JSON file (OTHERACCOUNT)  ####

#### START:FUNCTION - Import Image from COS (img_import) ####
img_import() {
	local img_name="$1"
	local import_bucket="$2"
	local import_bucket_region="$3"
	local workspace_to_import="$4"
	local img_name_ws="$5"
	local storage_type="$6"
	local account_type="$7"
	local hmac_file="$8"

	if [[ -z "$img_name" || -z "$import_bucket" || -z "$import_bucket_region" || -z "$workspace_to_import" || -z "$img_name_ws" || -z "$storage_type" || -z "$account_type" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many or too few arguments!! Syntax: bluexport_api.sh -imgimport IMGNAME BUCKET BUCKET_REGION WORKSPACE_TO_IMPORT IMGNAME_WS STORAGE_TYPE CURRACCOUNT|OTHERACCOUNT [HMACKEYS-JSON-FILE-PATH-NAME]" 1
	fi

	import_bucket_region=${import_bucket_region,,}
	if ! echo "$import_bucket_region" | grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*$'
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Invalid BUCKET_REGION: $import_bucket_region. Use the IBM COS S3 endpoint region, for example eu-es, eu-de, us-east or us-south." 1
	fi

	storage_type=${storage_type,,}
	if [[ "$storage_type" != "tier0" && "$storage_type" != "tier1" && "$storage_type" != "tier3" && "$storage_type" != "tier5k" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Invalid storage type: $storage_type. Valid values are tier0, tier1, tier3 or tier5k." 1
	fi

	account_type=${account_type^^}
	if [[ "$account_type" != "CURRACCOUNT" && "$account_type" != "OTHERACCOUNT" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Invalid account type: $account_type. Valid values are CURRACCOUNT or OTHERACCOUNT." 1
	fi
	if [[ "$account_type" == "CURRACCOUNT" && -n "$hmac_file" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! HMACKEYS-JSON-FILE-PATH-NAME is only valid with OTHERACCOUNT." 1
	fi
	if [[ "$account_type" == "OTHERACCOUNT" && -z "$hmac_file" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - HMACKEYS-JSON-FILE-PATH-NAME is mandatory when using OTHERACCOUNT." 1
	fi
	if [[ "$account_type" == "OTHERACCOUNT" && ! -f "$hmac_file" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - HMAC keys JSON file $hmac_file not found. Aborting..." 1
	fi

	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - === Starting Image Import from COS ===" "1"
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - COS image/object filename: $img_name" "1"
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Target image catalog name: $img_name_ws" "1"
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Storage Type: $storage_type" "1"
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Bucket: $import_bucket" "1"
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Bucket Region: $import_bucket_region" "1"
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Target Workspace: $workspace_to_import" "1"
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Account Type: $account_type" "1"

	local ws_key=""
	ws_key=$(jq -r --arg ws "$workspace_to_import" '
		.workspaces
		| to_entries[]?
		| select((.key | ascii_downcase) == ($ws | ascii_downcase) or (.value.name | ascii_downcase) == ($ws | ascii_downcase))
		| .key
	' "$bluexscrt" 2>>"$log_file" | head -n1)
	if [[ -z "$ws_key" || "$ws_key" == "null" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Workspace $workspace_to_import not found in $bluexscrt. Use the workspace short name or full workspace name from your JSON." 1
	fi

	CRN=$(jq -r --arg ws "$ws_key" '.workspaces[$ws].crn' "$bluexscrt")
	CLOUD_INSTANCE_ID=$(jq -r --arg ws "$ws_key" '.workspaces[$ws].id' "$bluexscrt")
	full_ws_name=$(jq -r --arg ws "$ws_key" '.workspaces[$ws].name // $ws' "$bluexscrt")
	if [[ -z "$CRN" || "$CRN" == "null" || -z "$CLOUD_INSTANCE_ID" || "$CLOUD_INSTANCE_ID" == "null" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Workspace $ws_key ($full_ws_name) missing CRN or ID in $bluexscrt. Aborting..." 1
	fi

	region_api=$(echo "$CRN" | sed -n 's/.*power-iaas:\([^:]*\):.*/\1/p' | tr '-' '_')
	base_url_var="base_${region_api}"
	base_url="${!base_url_var}"
	if [[ -z "$base_url" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Could not resolve PowerVS API endpoint for workspace $full_ws_name region $region_api." 1
	fi

	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Workspace resolved: $workspace_to_import -> $ws_key ($full_ws_name)." "1"
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Checking if image $img_name_ws already exists in Workspace $full_ws_name..." "1"
	local imgs_json existing_img_id
	imgs_json=$(img_ls 2>>"$log_file")
	existing_img_id=$(echo "$imgs_json" | jq -r --arg name "$img_name_ws" '.images[]? | select(.name == $name) | .imageID' 2>>"$log_file" | head -n1)
	if [[ -n "$existing_img_id" && "$existing_img_id" != "null" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Image $img_name_ws already exists in Workspace $full_ws_name with ID $existing_img_id. Aborting to avoid duplicate import." 1
	fi

	local cos_accesskey cos_secretkey cos_region
	cos_region="$import_bucket_region"
	if [[ "$account_type" == "CURRACCOUNT" ]]
	then
		cos_accesskey="$accesskey"
		cos_secretkey="$secretkey"
	else
		load_hmac_keys "$hmac_file"
		cos_accesskey="$hmac_access_key"
		cos_secretkey="$hmac_secret_key"
	fi
	if [[ -z "$cos_accesskey" || -z "$cos_secretkey" || "$cos_accesskey" == "null" || "$cos_secretkey" == "null" ]]
	then
		if [[ "$account_type" == "OTHERACCOUNT" ]]
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` - Missing COS HMAC accessKey/secretKey. Check $hmac_file." 1
		else
			abort "`date +%Y-%m-%d_%H:%M:%S` - Missing COS HMAC accessKey/secretKey. Check $bluexscrt." 1
		fi
	fi
	local cos_endpoint head_http head_body
	cos_endpoint="https://s3.${cos_region}.cloud-object-storage.appdomain.cloud/${import_bucket}/${img_name}"
	head_body="/tmp/bluexport_imgimport_head_$$.out"
	# (1.19.0) Always --aws-sigv4 with the same cos_accesskey:cos_secretkey that go into
	# the import payload - never an IAM bearer token, even for CURRACCOUNT - so this
	# pre-check validates the exact credentials the import itself will use, same as
	# the export pre-check already does (see its own comment above).
	curl --help all 2>/dev/null | grep -q -- '--aws-sigv4' || abort "$(date +%Y-%m-%d_%H:%M:%S) - This system's curl does not support --aws-sigv4 (requires curl 7.75+, used for the COS bucket/object pre-check). On IBM i PASE, install a newer curl via yum/dnf from /QOpenSys/pkgs." 1
	head_http=$(curl -sS -o "$head_body" -w "%{http_code}" --connect-timeout 30 --max-time 120 --aws-sigv4 "aws:amz:${cos_region}:s3" --user "${cos_accesskey}:${cos_secretkey}" -I "$cos_endpoint" 2>>"$log_file")
	cat "$head_body" >> "$log_file" 2>/dev/null
	rm -f "$head_body"
	case "$head_http" in
		200|204)
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - COS bucket/object check OK: $import_bucket/$img_name in region $cos_region." "1"
			;;
		301|302|307|308)
			abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - COS bucket/object validation was redirected. This usually means BUCKET_REGION is wrong. Bucket: $import_bucket, object: $img_name, region used: $cos_region." 1
			;;
		403)
			abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - COS access denied for bucket/object $import_bucket/$img_name in region $cos_region. For OTHERACCOUNT this normally means invalid HMAC keys, wrong bucket region, or missing COS permissions." 1
			;;
		404)
			abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - COS bucket or object not found: $import_bucket/$img_name in region $cos_region." 1
			;;
		*)
			abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Unable to validate COS bucket/object $import_bucket/$img_name. HTTP status: $head_http." 1
			;;
	esac

	# Optional image import storage pool can be placed in the secrets JSON under .imageImport.
	# Example: { "imageImport": { "storagePool": "StoragePool-3" } }
	local storage_pool
	storage_pool=$(jq -r '.imageImport.storagePool // empty' "$bluexscrt" 2>>"$log_file")

	ACTIONS=$(jq -n \
		--arg imageName "$img_name_ws" \
		--arg imageFilename "$img_name" \
		--arg bucketName "$import_bucket" \
		--arg region "$cos_region" \
		--arg accessKey "$cos_accesskey" \
		--arg secretKey "$cos_secretkey" \
		--arg storageType "$storage_type" \
		--arg storagePool "$storage_pool" \
		'{imageName:$imageName,region:$region,imageFilename:$imageFilename,bucketName:$bucketName,accessKey:$accessKey,secretKey:$secretKey}
		+ (if $storageType != "" then {storageType:$storageType} else {} end)
		+ (if $storagePool != "" then {storagePool:$storagePool} else {} end)' \
		| sed 's/^{//; s/}$//')

	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Calling PowerVS COS Image Import API for object $img_name as image $img_name_ws into Workspace $full_ws_name..." "1"
	local import_raw import_http_code import_resp import_rc import_job_id import_error
	import_raw=$(img_import_api 2>>"$log_file")
	import_rc=$?
	import_http_code="${import_raw##*$'\n'}"
	import_resp="${import_raw%$'\n'*}"
	echo "$import_resp" >> "$log_file"
	if [ "$import_rc" -ne 0 ] || [[ ! "$import_http_code" =~ ^2[0-9][0-9]$ ]] || echo "$import_resp" | jq -e '.code? != null or .error? != null or .errors? != null' >/dev/null 2>&1
	then
		import_error=$(echo "$import_resp" | jq -r '.message // .error // (.errors[0].message?) // .description // "Unknown error"' 2>/dev/null)
		if [[ "$import_http_code" == "409" ]] || echo "$import_error $import_resp" | grep -Eiq 'already running|in progress|conflict'
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Another import/export operation is already running in this workspace. Wait for it to complete before starting a new one." 1
		fi
		if echo "$import_error $import_resp" | grep -Eiq 'hmac|access.?key|secret.?key|signature|credential|forbidden|not authorized|access denied'
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - PowerVS image import rejected the COS credentials/HMAC keys: $import_error" 1
		fi
		abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Error calling PowerVS image import API for $img_name_ws from COS object $img_name: $import_error" 1
	fi

	import_job_id=$(echo "$import_resp" | jq -r '.jobID // .id // .job.id // .jobReference.id // empty' 2>>"$log_file" | head -n1)
	if [[ -n "$import_job_id" ]]
	then
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Image import submitted successfully. Job ID: $import_job_id" "1"
		wait_for_job "$import_job_id" "Image import of $img_name_ws"
	else
		abort "`date +%Y-%m-%d_%H:%M:%S` - Image import submitted, but no Job ID was returned by the API. Response saved in $log_file. Check the Boot images page or -imglsall to confirm it completed." 1
	fi
}
#### END:FUNCTION - Import Image from COS (img_import) ####

####  START:FUNCTION - Monitor Existing Image Import Job (img_import_monitor) ####
# img_import_monitor WORKSPACE
#   Re-attaches monitoring to the last import job PowerVS has on record for the given
#   workspace, without resubmitting anything. Uses PowerVS's "get last cos-image import
#   job" endpoint (workspace-scoped - no image name involved, since the confirmed Job
#   resource has no name field and the endpoint only ever tracks one, the most recent,
#   import job per workspace).
img_import_monitor() {
	local workspace_to_import="$1"

	if [[ -z "$workspace_to_import" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many or too few arguments!! Syntax: bluexport_api.sh -ji WORKSPACE" 1
	fi

	local ws_key=""
	ws_key=$(jq -r --arg ws "$workspace_to_import" '
		.workspaces
		| to_entries[]?
		| select((.key | ascii_downcase) == ($ws | ascii_downcase) or (.value.name | ascii_downcase) == ($ws | ascii_downcase))
		| .key
	' "$bluexscrt" 2>>"$log_file" | head -n1)
	if [[ -z "$ws_key" || "$ws_key" == "null" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Workspace $workspace_to_import not found in $bluexscrt. Use the workspace short name or full workspace name from your JSON." 1
	fi

	CRN=$(jq -r --arg ws "$ws_key" '.workspaces[$ws].crn' "$bluexscrt")
	CLOUD_INSTANCE_ID=$(jq -r --arg ws "$ws_key" '.workspaces[$ws].id' "$bluexscrt")
	full_ws_name=$(jq -r --arg ws "$ws_key" '.workspaces[$ws].name // $ws' "$bluexscrt")
	if [[ -z "$CRN" || "$CRN" == "null" || -z "$CLOUD_INSTANCE_ID" || "$CLOUD_INSTANCE_ID" == "null" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Workspace $ws_key ($full_ws_name) missing CRN or ID in $bluexscrt. Aborting..." 1
	fi

	region_api=$(echo "$CRN" | sed -n 's/.*power-iaas:\([^:]*\):.*/\1/p' | tr '-' '_')
	base_url_var="base_${region_api}"
	base_url="${!base_url_var}"
	if [[ -z "$base_url" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Could not resolve PowerVS API endpoint for workspace $full_ws_name region $region_api." 1
	fi

	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Workspace resolved: $workspace_to_import -> $ws_key ($full_ws_name)." "1"
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Retrieving last image import job for Workspace $full_ws_name..." "1"

	local status_raw status_http_code status_resp job_id job_state
	status_raw=$(img_import_status_api 2>>"$log_file")
	status_http_code="${status_raw##*$'\n'}"
	status_resp="${status_raw%$'\n'*}"
	echo "$status_resp" >> "$log_file"

	case "$status_http_code" in
		2*)
			if [[ -z "$status_resp" ]]
			then
				abort "`date +%Y-%m-%d_%H:%M:%S` - No import job history found for workspace $full_ws_name." 1
			fi
			if ! printf '%s' "$status_resp" | jq -e . >/dev/null 2>&1
			then
				abort "`date +%Y-%m-%d_%H:%M:%S` - Invalid response received while retrieving the last import job for workspace $full_ws_name. Check $log_file." 1
			fi
			job_id=$(printf '%s' "$status_resp" | jq -r '.id // .jobID // .job.id // .jobReference.id // empty' 2>/dev/null)
			job_state=$(printf '%s' "$status_resp" | jq -r '.status.state // empty' 2>/dev/null)
			if [[ -z "$job_id" && -z "$job_state" ]]
			then
				abort "`date +%Y-%m-%d_%H:%M:%S` - No import job history found for workspace $full_ws_name." 1
			elif [[ -z "$job_id" ]]
			then
				abort "`date +%Y-%m-%d_%H:%M:%S` - Import job history was returned, but the response did not include a Job ID. Check $log_file." 1
			fi
			;;
		404)
			abort "`date +%Y-%m-%d_%H:%M:%S` - No import job history found for workspace $full_ws_name." 1
			;;
		400)
			abort "`date +%Y-%m-%d_%H:%M:%S` - Invalid request while retrieving the last import job for workspace $full_ws_name." 1
			;;
		401)
			abort "`date +%Y-%m-%d_%H:%M:%S` - Authentication failed while retrieving the last import job for workspace $full_ws_name." 1
			;;
		403)
			abort "`date +%Y-%m-%d_%H:%M:%S` - Not authorized to retrieve the last import job for workspace $full_ws_name." 1
			;;
		500)
			abort "`date +%Y-%m-%d_%H:%M:%S` - PowerVS service error while retrieving the last import job for workspace $full_ws_name." 1
			;;
		*)
			abort "`date +%Y-%m-%d_%H:%M:%S` - Failed to retrieve the last import job for workspace $full_ws_name, HTTP status $status_http_code." 1
			;;
	esac

	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Last image import job found: $job_id" "1"
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Status: $job_state" "1"
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Attaching monitor..." "1"
	wait_for_job "$job_id" "Image import job for workspace $full_ws_name"
}
####  END:FUNCTION - Monitor Existing Image Import Job ####

####  START:FUNCTION - Export Image to COS (img_export) ####
img_export() {
	local img_name="$1"
	local export_bucket="$2"
	local export_bucket_region="$3"
	local account_type="$4"
	local hmac_file="$5"

	if [[ -z "$img_name" || -z "$export_bucket" || -z "$export_bucket_region" || -z "$account_type" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many or too few arguments!! Syntax: bluexport_api.sh -imgexport IMGNAME BUCKET BUCKET_REGION CURRACCOUNT|OTHERACCOUNT [HMACKEYS-JSON-FILE-PATH-NAME]" 1
	fi

	export_bucket_region=${export_bucket_region,,}
	if ! echo "$export_bucket_region" | grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*$'
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Invalid BUCKET_REGION: $export_bucket_region. Use the IBM COS S3 endpoint region, for example eu-es, eu-de, us-east or us-south." 1
	fi

	account_type=${account_type^^}
	if [[ "$account_type" != "CURRACCOUNT" && "$account_type" != "OTHERACCOUNT" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Invalid account type: $account_type. Valid values are CURRACCOUNT or OTHERACCOUNT." 1
	fi
	if [[ "$account_type" == "CURRACCOUNT" && -n "$hmac_file" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! HMACKEYS-JSON-FILE-PATH-NAME is only valid with OTHERACCOUNT." 1
	fi
	if [[ "$account_type" == "OTHERACCOUNT" && -z "$hmac_file" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - HMACKEYS-JSON-FILE-PATH-NAME is mandatory when using OTHERACCOUNT." 1
	fi
	if [[ "$account_type" == "OTHERACCOUNT" && ! -f "$hmac_file" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - HMAC keys JSON file $hmac_file not found. Aborting..." 1
	fi

	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - === Starting Image Export to COS ===" "1"
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Image to export: $img_name" "1"
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Target Bucket: $export_bucket" "1"
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Target Bucket Region: $export_bucket_region" "1"
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Account Type: $account_type" "1"

	# (1.19.0) Every workspace is searched and every match counted, same as do_img_delete
	# since 1.18.6 - before, the first match in the first workspace won (head -n1, then
	# break), so an ambiguous name silently exported whichever image the API listed first.
	read -r -a allws_array <<< "$allws"
	local IMAGE_ID="" found_ws="" found_ws_name="" match_count=0 match_list=""
	for ws in "${allws_array[@]}"
	do
		CRN=$(jq -r --arg ws "$ws" '.workspaces[$ws].crn' "$bluexscrt")
		CLOUD_INSTANCE_ID=$(jq -r --arg ws "$ws" '.workspaces[$ws].id' "$bluexscrt")
		full_ws_name=$(jq -r --arg ws "$ws" '.workspaces[$ws].name' "$bluexscrt" 2>>"$log_file")
		if [[ -z "$full_ws_name" || "$full_ws_name" == "null" ]]; then full_ws_name="$ws"; fi
		if [[ -z "$CRN" || "$CRN" == "null" || -z "$CLOUD_INSTANCE_ID" || "$CLOUD_INSTANCE_ID" == "null" ]]
		then
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Workspace $ws ($full_ws_name) missing CRN or ID in $bluexscrt, skipping." "1"
			continue
		fi
		region_api=$(echo "$CRN" | sed -n 's/.*power-iaas:\([^:]*\):.*/\1/p' | tr '-' '_')
		if [[ -z "$region_api" ]]
		then
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Could not parse region from CRN $CRN for workspace $full_ws_name, skipping." "1"
			continue
		fi
		base_url_var="base_${region_api}"
		base_url="${!base_url_var}"
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Checking for Image $img_name in Workspace $full_ws_name..." "1"
		local imgs_json
		imgs_json=$(img_ls 2>>"$log_file")
		if [[ -z "$imgs_json" ]]
		then
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Could not retrieve image list via API in workspace $full_ws_name, skipping." "1"
			continue
		fi
		local ws_ids one_id
		ws_ids=$(echo "$imgs_json" | jq -r --arg name "$img_name" '.images[]? | select(.name == $name) | .imageID' 2>>"$log_file")
		for one_id in $ws_ids
		do
			[ -z "$one_id" ] && continue
			[ "$one_id" = "null" ] && continue
			match_count=$((match_count + 1))
			match_list="$match_list
  - $full_ws_name: $one_id"
			IMAGE_ID="$one_id"
			found_ws="$ws"
			found_ws_name="$full_ws_name"
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Image $img_name found in Workspace $found_ws_name with ID: $IMAGE_ID" "1"
		done
	done
	if [ "$match_count" -eq 0 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Image with name $img_name not found in any Workspace." 1
	fi
	if [ "$match_count" -gt 1 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Image name $img_name is ambiguous: $match_count images carry it. Nothing exported. Matches:$match_list" 1
	fi

	local cos_accesskey cos_secretkey cos_region
	cos_region="$export_bucket_region"
	if [[ "$account_type" == "CURRACCOUNT" ]]
	then
		cos_accesskey="$accesskey"
		cos_secretkey="$secretkey"
	else
		load_hmac_keys "$hmac_file"
		cos_accesskey="$hmac_access_key"
		cos_secretkey="$hmac_secret_key"
	fi
	if [[ -z "$cos_accesskey" || -z "$cos_secretkey" || "$cos_accesskey" == "null" || "$cos_secretkey" == "null" ]]
	then
		if [[ "$account_type" == "OTHERACCOUNT" ]]
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` - Missing COS HMAC accessKey/secretKey. Check $hmac_file." 1
		else
			abort "`date +%Y-%m-%d_%H:%M:%S` - Missing COS HMAC accessKey/secretKey. Check $bluexscrt." 1
		fi
	fi

	# Pré-validar a bucket de destino (só a bucket em si - o objecto ainda não existe,
	# o nome final é decidido pela API). Ignora qualquer prefixo/pasta em BUCKET.
	# Usa SEMPRE --aws-sigv4 com as mesmas credenciais que vão para o payload do PowerVS
	# (nunca IAM bearer, mesmo em CURRACCOUNT), para que este pré-check valide mesmo as
	# HMAC keys que importam - ver spec 2026-08-06, correcção D.4.
	local bucket_root="${export_bucket%%/*}"
	local cos_endpoint head_http head_body
	cos_endpoint="https://s3.${cos_region}.cloud-object-storage.appdomain.cloud/${bucket_root}"
	head_body="/tmp/bluexport_imgexport_head_$$.out"
	curl --help all 2>/dev/null | grep -q -- '--aws-sigv4' || abort "$(date +%Y-%m-%d_%H:%M:%S) - This system's curl does not support --aws-sigv4 (requires curl 7.75+, used for the COS bucket pre-check). On IBM i PASE, install a newer curl via yum/dnf from /QOpenSys/pkgs." 1
	head_http=$(curl -sS -o "$head_body" -w "%{http_code}" --connect-timeout 30 --max-time 120 --aws-sigv4 "aws:amz:${cos_region}:s3" --user "${cos_accesskey}:${cos_secretkey}" -I "$cos_endpoint" 2>>"$log_file")
	cat "$head_body" >> "$log_file" 2>/dev/null
	rm -f "$head_body"
	case "$head_http" in
		200|204)
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - COS bucket check OK: $bucket_root in region $cos_region." "1"
			;;
		301|302|307|308)
			abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - COS bucket validation was redirected. This usually means BUCKET_REGION is wrong. Bucket: $bucket_root, region used: $cos_region." 1
			;;
		403)
			abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - COS access denied for bucket $bucket_root in region $cos_region. This normally means invalid HMAC keys, wrong bucket region, or missing COS permissions. Note: this pre-check requires bucket-level read (HeadBucket); a COS credential scoped only to object write will 403 here even though the export itself would succeed." 1
			;;
		404)
			abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - COS bucket not found: $bucket_root in region $cos_region." 1
			;;
		*)
			abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Unable to validate COS bucket $bucket_root. HTTP status: $head_http." 1
			;;
	esac

	ACTIONS=$(jq -n \
		--arg bucketName "$export_bucket" \
		--arg region "$cos_region" \
		--arg accessKey "$cos_accesskey" \
		--arg secretKey "$cos_secretkey" \
		'{bucketName:$bucketName,region:$region,accessKey:$accessKey,secretKey:$secretKey}' \
		| sed 's/^{//; s/}$//')

	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Calling PowerVS Image Export API for $img_name (ID $IMAGE_ID) from Workspace $found_ws_name to bucket $export_bucket..." "1"
	local export_raw export_http_code export_resp export_rc export_error export_job_id
	export_raw=$(img_export_api 2>>"$log_file")
	export_rc=$?
	export_http_code="${export_raw##*$'\n'}"
	export_resp="${export_raw%$'\n'*}"
	printf '%s\n' "$export_resp" >> "$log_file"
	if [ "$export_rc" -ne 0 ] || [[ ! "$export_http_code" =~ ^2[0-9][0-9]$ ]] || printf '%s' "$export_resp" | jq -e '.code? != null or .error? != null or .errors? != null' >/dev/null 2>&1
	then
		export_error=$(printf '%s' "$export_resp" | jq -r '.message // .error // (.errors[0].message?) // .description // "Unknown error"' 2>/dev/null)
		if [[ "$export_http_code" == "409" ]] || echo "$export_error $export_resp" | grep -Eiq 'already running|in progress|conflict'
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Another import/export operation is already running in this workspace. Wait for it to complete before starting a new one." 1
		fi
		if echo "$export_error $export_resp" | grep -Eiq 'hmac|access.?key|secret.?key|signature|credential|forbidden|not authorized|access denied'
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - PowerVS image export rejected the COS credentials/HMAC keys: $export_error" 1
		fi
		abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Error calling PowerVS image export API for $img_name: $export_error" 1
	fi

	export_job_id=$(printf '%s' "$export_resp" | jq -r '.jobID // .id // .job.id // .jobReference.id // empty' 2>>"$log_file" | head -n1)
	if [[ -n "$export_job_id" ]]
	then
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Image export submitted successfully. Job ID: $export_job_id" "1"
		wait_for_job "$export_job_id" "Image export of $img_name to bucket $export_bucket"
	else
		abort "`date +%Y-%m-%d_%H:%M:%S` - Image export submitted, but no Job ID was returned by the API. Response saved in $log_file. Check the Boot images page or -imglsall to confirm it completed." 1
	fi
}
####  END:FUNCTION - Export Image to COS (img_export) ####

####  START:FUNCTION - Monitor Existing Image Export Job (img_export_monitor) ####
# img_export_monitor IMAGE_NAME
#   Re-attaches monitoring to the last export job PowerVS has on record for the given
#   image, without resubmitting anything. Uses PowerVS's "get last image export job"
#   endpoint (image-scoped, unlike import's workspace-scoped equivalent) - resolves
#   IMAGE_NAME to an IMAGE_ID by searching every workspace, same pattern as img_export().
img_export_monitor() {
	local img_name="$1"

	if [[ -z "$img_name" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many or too few arguments!! Syntax: bluexport_api.sh -je IMAGE_NAME" 1
	fi

	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - === Looking up last export job for image $img_name ===" "1"

	# (1.19.0) Every workspace is searched and every match counted, same as do_img_delete
	# since 1.18.6 - before, the first match in the first workspace won (head -n1, then
	# break), so an ambiguous name silently reattached to whichever image the API listed first.
	read -r -a allws_array <<< "$allws"
	local IMAGE_ID="" found_ws="" found_ws_name="" match_count=0 match_list=""
	for ws in "${allws_array[@]}"
	do
		CRN=$(jq -r --arg ws "$ws" '.workspaces[$ws].crn' "$bluexscrt")
		CLOUD_INSTANCE_ID=$(jq -r --arg ws "$ws" '.workspaces[$ws].id' "$bluexscrt")
		full_ws_name=$(jq -r --arg ws "$ws" '.workspaces[$ws].name' "$bluexscrt" 2>>"$log_file")
		if [[ -z "$full_ws_name" || "$full_ws_name" == "null" ]]; then full_ws_name="$ws"; fi
		if [[ -z "$CRN" || "$CRN" == "null" || -z "$CLOUD_INSTANCE_ID" || "$CLOUD_INSTANCE_ID" == "null" ]]
		then
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Workspace $ws ($full_ws_name) missing CRN or ID in $bluexscrt, skipping." "1"
			continue
		fi
		region_api=$(echo "$CRN" | sed -n 's/.*power-iaas:\([^:]*\):.*/\1/p' | tr '-' '_')
		if [[ -z "$region_api" ]]
		then
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Could not parse region from CRN $CRN for workspace $full_ws_name, skipping." "1"
			continue
		fi
		base_url_var="base_${region_api}"
		base_url="${!base_url_var}"
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Checking for Image $img_name in Workspace $full_ws_name..." "1"
		local imgs_json
		imgs_json=$(img_ls 2>>"$log_file")
		if [[ -z "$imgs_json" ]]
		then
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Could not retrieve image list via API in workspace $full_ws_name, skipping." "1"
			continue
		fi
		local ws_ids one_id
		ws_ids=$(echo "$imgs_json" | jq -r --arg name "$img_name" '.images[]? | select(.name == $name) | .imageID' 2>>"$log_file")
		for one_id in $ws_ids
		do
			[ -z "$one_id" ] && continue
			[ "$one_id" = "null" ] && continue
			match_count=$((match_count + 1))
			match_list="$match_list
  - $full_ws_name: $one_id"
			IMAGE_ID="$one_id"
			found_ws="$ws"
			found_ws_name="$full_ws_name"
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Image $img_name found in Workspace $found_ws_name with ID: $IMAGE_ID" "1"
		done
	done
	if [ "$match_count" -eq 0 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Image with name $img_name not found in any Workspace." 1
	fi
	if [ "$match_count" -gt 1 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Image name $img_name is ambiguous: $match_count images carry it. Nothing done. Matches:$match_list" 1
	fi

	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Retrieving last image export job for image $img_name..." "1"

	local status_raw status_http_code status_resp job_id job_state
	status_raw=$(img_export_status_api 2>>"$log_file")
	status_http_code="${status_raw##*$'\n'}"
	status_resp="${status_raw%$'\n'*}"
	echo "$status_resp" >> "$log_file"

	case "$status_http_code" in
		2*)
			if [[ -z "$status_resp" ]]
			then
				abort "`date +%Y-%m-%d_%H:%M:%S` - No export job history found for image $img_name." 1
			fi
			if ! printf '%s' "$status_resp" | jq -e . >/dev/null 2>&1
			then
				abort "`date +%Y-%m-%d_%H:%M:%S` - Invalid response received while retrieving the last export job for image $img_name. Check $log_file." 1
			fi
			job_id=$(printf '%s' "$status_resp" | jq -r '.id // .jobID // .job.id // .jobReference.id // empty' 2>/dev/null)
			job_state=$(printf '%s' "$status_resp" | jq -r '.status.state // empty' 2>/dev/null)
			if [[ -z "$job_id" && -z "$job_state" ]]
			then
				abort "`date +%Y-%m-%d_%H:%M:%S` - No export job history found for image $img_name." 1
			elif [[ -z "$job_id" ]]
			then
				abort "`date +%Y-%m-%d_%H:%M:%S` - Export job history was returned, but the response did not include a Job ID. Check $log_file." 1
			fi
			;;
		404)
			abort "`date +%Y-%m-%d_%H:%M:%S` - No export job history found for image $img_name." 1
			;;
		400)
			abort "`date +%Y-%m-%d_%H:%M:%S` - Invalid request while retrieving the last export job for image $img_name." 1
			;;
		401)
			abort "`date +%Y-%m-%d_%H:%M:%S` - Authentication failed while retrieving the last export job for image $img_name." 1
			;;
		403)
			abort "`date +%Y-%m-%d_%H:%M:%S` - Not authorized to retrieve the last export job for image $img_name." 1
			;;
		500)
			abort "`date +%Y-%m-%d_%H:%M:%S` - PowerVS service error while retrieving the last export job for image $img_name." 1
			;;
		*)
			abort "`date +%Y-%m-%d_%H:%M:%S` - Failed to retrieve the last export job for image $img_name, HTTP status $status_http_code." 1
			;;
	esac

	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Last image export job found: $job_id" "1"
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Status: $job_state" "1"
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Attaching monitor..." "1"
	wait_for_job "$job_id" "Image export job for image $img_name"
}
####  END:FUNCTION - Monitor Existing Image Export Job ####

#### START:FUNCTIONS - Inventory report (-invreport) ####
# One read-only pass across every configured workspace (and COS instance),
# reusing the same GET helpers and workspace-loop skeleton as
# -snaplsall/-vsidetails/-vclonelsall/-imglsall/-bucketslsall. Never calls a
# write endpoint. A workspace, volume group or bucket this cannot read is
# named in the report's own "Could not be read" section and skipped - it
# never aborts the whole report, and a failure is never rendered as an
# empty/zero result (see invreport_get/invreport_unreadable below).
#
# Section order, headers and the exact "None found."/"Could not be read"
# wording match the equivalent report this project's own desktop
# application produces, so a CLI-generated report and an
# application-generated one for the same account read the same way side
# by side.

# invreport_get FN KEY
# Calls the zero-arg API helper FN (ins_ls/vol_ls/vg_ls/vg_sd/snap_ls/
# img_ls/vol_cl_ls - each already reads the CRN/CLOUD_INSTANCE_ID/base_url
# the caller set beforehand) and tells a real failure (curl error, a
# non-JSON body, or a JSON error body with no KEY) apart from a genuinely
# empty list - an ambiguity most *lsall flags in this script leave
# unresolved (a failed call and an empty workspace both print "No X
# Found"). On success: prints the raw JSON body, returns 0. On failure:
# prints one short reason (no trailing newline), returns 1.
invreport_get() {
	local fn="$1" key="$2" json rc msg
	json=$("$fn" 2>>"$log_file")
	rc=$?
	if [ $rc -ne 0 ]
	then
		printf 'request failed (curl rc=%s)' "$rc"
		return 1
	fi
	if [ -z "$json" ]
	then
		printf 'empty response from the API'
		return 1
	fi
	if ! printf '%s' "$json" | jq -e . >/dev/null 2>&1
	then
		printf 'response was not valid JSON'
		return 1
	fi
	if printf '%s' "$json" | jq -e --arg k "$key" 'has($k)' >/dev/null 2>&1
	then
		printf '%s' "$json"
		return 0
	fi
	msg=$(printf '%s' "$json" | jq -r '.message // .error // .errors[0].message // empty' 2>>"$log_file")
	printf 'API error%s' "${msg:+: $msg}"
	return 1
}

# invreport_unreadable CONTEXT REASON
# Records one line in the report's "Could not be read" section (never a
# silent gap) and echoes it to screen/log immediately, so an operator
# watching a long run sees a failure the moment it happens.
invreport_unreadable() {
	local line
	line="$1: $2"
	line=$(printf '%s' "$line" | tr '\t\n\r' '   ')
	printf '%s\n' "$line" >> "$invreport_unreadable_tsv"
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Could not read $line" "1"
}

# invreport_is_old ISO_DATE DAYS NOW_EPOCH
# Prints 1 if ISO_DATE is older than DAYS days, 0 otherwise - including
# when the date is empty/null or cannot be parsed, matching the report's
# own rule that a missing date is never counted as "old".
invreport_is_old() {
	local iso="$1" days="$2" now_epoch="$3" then_epoch
	if [ -z "$iso" ] || [ "$iso" = "null" ]
	then
		printf '0'
		return
	fi
	then_epoch=$(date -d "$iso" +%s 2>/dev/null)
	if [ -z "$then_epoch" ]
	then
		printf '0'
		return
	fi
	if [ $(( (now_epoch - then_epoch) / 86400 )) -gt "$days" ]
	then
		printf '1'
	else
		printf '0'
	fi
}

# invreport_fmt_num N - trims a "%.2f" formatting down to at most 2
# decimals, no trailing zeros (the same "0.##" shape the application's own
# report uses for GB/core totals).
invreport_fmt_num() {
	awk -v n="$1" 'BEGIN{printf "%.2f", n+0}' | sed -e 's/\.00$//' -e 's/\(\.[0-9]\)0$/\1/'
}

# invreport_md_escape / invreport_html_escape / invreport_csv_field
# Match the equivalent report's own escaping rules exactly (pipe/CR/LF for
# Markdown, the four HTML metacharacters, RFC 4180 minimal quoting for
# CSV) so free-text values (an LPAR/bucket name is operator-chosen and
# could contain any of them) never break the rendered table.
invreport_md_escape() {
	printf '%s' "$1" | tr '\r\n' '  ' | sed 's/|/\\|/g'
}

invreport_html_escape() {
	printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'
}

invreport_csv_field() {
	local v="$1"
	if [[ "$v" == *,* || "$v" == *'"'* || "$v" == *$'\n'* || "$v" == *$'\r'* ]]
	then
		v=$(printf '%s' "$v" | sed 's/"/""/g')
		printf '"%s"' "$v"
	else
		printf '%s' "$v"
	fi
}

# invreport_bucket_objects - bounded pagination over list_object_page()'s S3
# XML, following <NextContinuationToken> while <IsTruncated>true</
# IsTruncated>. Reads $BUCKET (set by the caller). Capped at
# INVREPORT_MAX_COS_PAGES pages (default 100000, override via env) as a
# backstop against a server that never stops reporting truncated - every
# polling/paginating loop in this script must be bounded, and this one is
# new, so it does not get to copy the unbounded pattern some older loops
# in this file still have. On a page failure, a missing continuation token
# on a truncated page, or hitting the page cap, the whole count/size is
# discarded (never reported as a partial-but-silent undercount) and a
# reason is returned instead - the same all-or-nothing posture the rest of
# this report's failure handling uses.
# Prints "COUNT<TAB>SIZE<TAB>REASON" - COUNT/SIZE are empty when REASON is
# set.
invreport_bucket_objects() {
	local max_pages="${INVREPORT_MAX_COS_PAGES:-100000}"
	local page=0 count=0 size=0 truncated="true" reason=""
	CONTINUATION_TOKEN=""
	while [[ "$truncated" == "true" ]]
	do
		page=$((page + 1))
		if [ "$page" -gt "$max_pages" ]
		then
			reason="did not finish after $max_pages page(s) (INVREPORT_MAX_COS_PAGES) - S3 kept reporting more to follow"
			count=""
			size=""
			break
		fi
		local xml rc
		xml=$(list_object_page 2>>"$log_file")
		rc=$?
		if [ $rc -ne 0 ] || [ -z "$xml" ]
		then
			reason="request failed listing objects (page $page, curl rc=$rc)"
			count=""
			size=""
			break
		fi
		local data="$xml"
		while [[ "$data" == *"<Contents>"*"</Contents>"* ]]
		do
			local chunk sz
			chunk="${data#*<Contents>}"
			chunk="${chunk%%</Contents>*}"
			data="${data#*</Contents>}"
			sz=""
			if [[ "$chunk" == *"<Size>"*"</Size>"* ]]
			then
				sz="${chunk#*<Size>}"
				sz="${sz%%</Size>*}"
			fi
			[[ "$sz" =~ ^[0-9]+$ ]] || sz=0
			count=$((count + 1))
			size=$((size + sz))
		done
		truncated="false"
		if [[ "$xml" == *"<IsTruncated>"*"</IsTruncated>"* ]]
		then
			truncated="${xml#*<IsTruncated>}"
			truncated="${truncated%%</IsTruncated>*}"
		fi
		local token=""
		if [[ "$xml" == *"<NextContinuationToken>"*"</NextContinuationToken>"* ]]
		then
			token="${xml#*<NextContinuationToken>}"
			token="${token%%</NextContinuationToken>*}"
		fi
		if [[ "$truncated" == "true" && -z "$token" ]]
		then
			reason="S3 reported more objects (IsTruncated=true) but no continuation token - refusing to report a partial listing as complete"
			count=""
			size=""
			break
		fi
		CONTINUATION_TOKEN="$token"
		# Redirected to /dev/null: this function's stdout is captured via
		# command substitution by the caller (invreport_bucket_objects's
		# own COUNT/SIZE/REASON line), so a progress line printed here
		# would otherwise leak into that captured value. Still logged
		# (flag "1"), just not echoed to the terminal from inside here.
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) -     page $page: $count object(s) so far in bucket '$BUCKET'" "1" >/dev/null
	done
	printf '%s\037%s\037%s\n' "$count" "$size" "$reason"
}

# invreport_totals_lines WD - prints the Totals section's lines, one per
# line, no leading bullet/markup - the md/html writers wrap each in their
# own list syntax.
invreport_totals_lines() {
	local wd="$1"
	local workspaces lpars memknown coresknown mem cores vol volattach snap snapold img imgold days
	workspaces=$(awk -F'\037' '$1=="WorkspaceCount"{print $2}' "$wd/totals.tsv")
	lpars=$(awk -F'\037' '$1=="LparCount"{print $2}' "$wd/totals.tsv")
	memknown=$(awk -F'\037' '$1=="LparsWithMemoryKnown"{print $2}' "$wd/totals.tsv")
	coresknown=$(awk -F'\037' '$1=="LparsWithCoresKnown"{print $2}' "$wd/totals.tsv")
	mem=$(awk -F'\037' '$1=="TotalMemoryGb"{print $2}' "$wd/totals.tsv")
	cores=$(awk -F'\037' '$1=="TotalCores"{print $2}' "$wd/totals.tsv")
	vol=$(awk -F'\037' '$1=="VolumeCount"{print $2}' "$wd/totals.tsv")
	volattach=$(awk -F'\037' '$1=="UnattachedVolumeCount"{print $2}' "$wd/totals.tsv")
	snap=$(awk -F'\037' '$1=="SnapshotCount"{print $2}' "$wd/totals.tsv")
	snapold=$(awk -F'\037' '$1=="OldSnapshotCount"{print $2}' "$wd/totals.tsv")
	img=$(awk -F'\037' '$1=="ImageCount"{print $2}' "$wd/totals.tsv")
	imgold=$(awk -F'\037' '$1=="OldImageCount"{print $2}' "$wd/totals.tsv")
	days=$(awk -F'\037' '$1=="OldThresholdDays"{print $2}' "$wd/totals.tsv")
	printf 'Workspaces: %s\n' "$workspaces"
	printf 'LPARs: %s (memory known for %s, cores known for %s)\n' "$lpars" "$memknown" "$coresknown"
	printf 'Total memory: %s GB\n' "$mem"
	printf 'Total cores: %s\n' "$cores"
	awk -F'\037' '$1 ~ /^StorageGb\./{ sub(/^StorageGb\./,"",$1); printf "Storage on tier %s: %s GB\n", $1, $2 }' "$wd/totals.tsv" | sort
	printf 'Volumes: %s (%s unattached)\n' "$vol" "$volattach"
	printf 'Snapshots: %s (%s older than %s day(s))\n' "$snap" "$snapold" "$days"
	printf 'Images: %s (%s older than %s day(s))\n' "$img" "$imgold" "$days"
}

# invreport_write_md WD OUTFILE - renders the whole report as one Markdown
# file, the source of truth CSV/HTML match section-for-section.
invreport_write_md() {
	local wd="$1" outfile="$2"
	{
		echo "# Inventory report"
		echo
		echo "Generated $(date -u +"%Y-%m-%d %H:%M UTC")."
		echo
		echo "## Could not be read"
		echo
		if [ -s "$wd/unreadable.tsv" ]
		then
			while IFS=$'\037' read -r reason
			do
				echo "- $(invreport_md_escape "$reason")"
			done < "$wd/unreadable.tsv"
		else
			echo "Every configured workspace, volume group and bucket was read successfully."
		fi
		echo

		echo "## Totals"
		echo
		while IFS= read -r line
		do
			echo "- $line"
		done < <(invreport_totals_lines "$wd")
		echo

		echo "## Workspaces"
		echo
		if [ ! -s "$wd/workspaces.tsv" ]
		then
			echo "None found."
			echo
		else
			echo "| Name | Key | Region | Zone | Id | LPARs |"
			echo "| --- | --- | --- | --- | --- | --- |"
			while IFS=$'\037' read -r key name region zone id lparcount
			do
				printf '| %s | %s | %s | %s | %s | %s |\n' \
					"$(invreport_md_escape "$name")" "$(invreport_md_escape "$key")" \
					"$(invreport_md_escape "$region")" "$(invreport_md_escape "$zone")" \
					"$(invreport_md_escape "$id")" "$lparcount"
			done < "$wd/workspaces.tsv"
			echo
		fi

		echo "## LPARs"
		echo
		if [ ! -s "$wd/lpars.tsv" ]
		then
			echo "None found."
			echo
		else
			echo "| Workspace | Name | Id | Status | OS | OS detail | Cores | Type | Memory (GB) | System type | Licences | IP addresses |"
			echo "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |"
			while IFS=$'\037' read -r wskey wsname name id status os osdetail cores vcores proctype memgb systype lic ips
			do
				printf '| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n' \
					"$(invreport_md_escape "$wsname")" "$(invreport_md_escape "$name")" "$(invreport_md_escape "$id")" \
					"$(invreport_md_escape "$status")" "$(invreport_md_escape "$os")" "$(invreport_md_escape "$osdetail")" \
					"$(invreport_md_escape "${cores:--}")" "$(invreport_md_escape "${proctype:--}")" \
					"$(invreport_md_escape "${memgb:--}")" "$(invreport_md_escape "${systype:--}")" \
					"$(invreport_md_escape "${lic:--}")" "$(invreport_md_escape "${ips:--}")"
			done < "$wd/lpars.tsv"
			echo
		fi

		echo "## Volumes"
		echo
		if [ ! -s "$wd/volumes.tsv" ]
		then
			echo "None found."
			echo
		else
			echo "| Workspace | Name | Id | Tier | Size (GB) | Bootable | Attached to | Replication | Origin |"
			echo "| --- | --- | --- | --- | --- | --- | --- | --- | --- |"
			while IFS=$'\037' read -r wskey wsname id name tier size boot state repl attached origin
			do
				local bootdisp=no repldisp=disabled attacheddisp="not attached"
				[ "$boot" = "true" ] && bootdisp=yes
				[ "$repl" = "true" ] && repldisp=enabled
				[ -n "$attached" ] && attacheddisp="$attached"
				printf '| %s | %s | %s | %s | %s | %s | %s | %s | %s |\n' \
					"$(invreport_md_escape "$wsname")" "$(invreport_md_escape "$name")" "$(invreport_md_escape "$id")" \
					"$(invreport_md_escape "${tier:--}")" "$(invreport_md_escape "${size:--}")" "$bootdisp" \
					"$(invreport_md_escape "$attacheddisp")" "$repldisp" "$(invreport_md_escape "$origin")"
			done < "$wd/volumes.tsv"
			echo
		fi

		echo "## Volume groups"
		echo
		if [ ! -s "$wd/volumegroups.tsv" ]
		then
			echo "None found."
			echo
		else
			echo "| Workspace | Name | Id | Consistency group | State | Primary role | Remote copies |"
			echo "| --- | --- | --- | --- | --- | --- | --- |"
			while IFS=$'\037' read -r wskey wsname id name cg state primary remote reason
			do
				local statedisp="${state:--}"
				[ -z "$state" ] && [ -n "$reason" ] && statedisp="unreadable ($reason)"
				printf '| %s | %s | %s | %s | %s | %s | %s |\n' \
					"$(invreport_md_escape "$wsname")" "$(invreport_md_escape "$name")" "$(invreport_md_escape "$id")" \
					"$(invreport_md_escape "${cg:--}")" "$(invreport_md_escape "$statedisp")" \
					"$(invreport_md_escape "${primary:--}")" "${remote:-0}"
			done < "$wd/volumegroups.tsv"
			echo
		fi

		echo "## Snapshots"
		echo
		if [ ! -s "$wd/snapshots.tsv" ]
		then
			echo "None found."
			echo
		else
			echo "| Workspace | Name | LPAR | Status | Created | Volumes |"
			echo "| --- | --- | --- | --- | --- | --- |"
			while IFS=$'\037' read -r wskey wsname name lpar status created volcount isold
			do
				printf '| %s | %s | %s | %s | %s | %s |\n' \
					"$(invreport_md_escape "$wsname")" "$(invreport_md_escape "$name")" \
					"$(invreport_md_escape "${lpar:--}")" "$(invreport_md_escape "$status")" \
					"$(invreport_md_escape "${created:--}")" "${volcount:-0}"
			done < "$wd/snapshots.tsv"
			echo
		fi

		echo "## Images"
		echo
		if [ ! -s "$wd/images.tsv" ]
		then
			echo "None found."
			echo
		else
			echo "| Workspace | Name | Status | Operating system | Created |"
			echo "| --- | --- | --- | --- | --- |"
			while IFS=$'\037' read -r wskey wsname name status os created isold
			do
				printf '| %s | %s | %s | %s | %s |\n' \
					"$(invreport_md_escape "$wsname")" "$(invreport_md_escape "$name")" \
					"$(invreport_md_escape "$status")" "$(invreport_md_escape "${os:--}")" \
					"$(invreport_md_escape "${created:--}")"
			done < "$wd/images.tsv"
			echo
		fi

		echo "## Volume clones"
		echo
		if [ ! -s "$wd/volumeclones.tsv" ]
		then
			echo "None found."
			echo
		else
			echo "| Workspace | Name | Status | Percent complete | Created |"
			echo "| --- | --- | --- | --- | --- |"
			while IFS=$'\037' read -r wskey wsname name status pct created
			do
				printf '| %s | %s | %s | %s | %s |\n' \
					"$(invreport_md_escape "$wsname")" "$(invreport_md_escape "$name")" \
					"$(invreport_md_escape "$status")" "${pct:-0}" "$(invreport_md_escape "${created:--}")"
			done < "$wd/volumeclones.tsv"
			echo
		fi

		echo "## COS buckets"
		echo
		if [ ! -s "$wd/buckets.tsv" ]
		then
			echo "None found."
			echo
		else
			echo "| COS instance | Bucket | Created | Objects | Total size (bytes) |"
			echo "| --- | --- | --- | --- | --- |"
			while IFS=$'\037' read -r cosinst bucket created count size reason
			do
				local countdisp="$count" sizedisp="${size:--}"
				if [ -n "$reason" ]
				then
					countdisp="unreadable ($reason)"
					sizedisp="-"
				fi
				printf '| %s | %s | %s | %s | %s |\n' \
					"$(invreport_md_escape "$cosinst")" "$(invreport_md_escape "$bucket")" \
					"$(invreport_md_escape "${created:--}")" "$(invreport_md_escape "$countdisp")" "$sizedisp"
			done < "$wd/buckets.tsv"
			echo
		fi
	} > "$outfile"
}

# invreport_write_csv WD OUTDIR - one CSV file per section, RFC 4180
# minimal quoting (invreport_csv_field), matching the equivalent report's
# own CSV headers.
invreport_write_csv() {
	local wd="$1" outdir="$2"
	mkdir -p "$outdir" 2>>"$log_file"

	{
		echo "Metric,Value"
		while IFS=$'\037' read -r metric value
		do
			printf '%s,%s\n' "$(invreport_csv_field "$metric")" "$(invreport_csv_field "$value")"
		done < "$wd/totals.tsv"
	} > "$outdir/totals.csv"

	{
		echo "Name,Key,Region,Zone,Id,LPARs"
		while IFS=$'\037' read -r key name region zone id lparcount
		do
			printf '%s,%s,%s,%s,%s,%s\n' \
				"$(invreport_csv_field "$name")" "$(invreport_csv_field "$key")" \
				"$(invreport_csv_field "$region")" "$(invreport_csv_field "$zone")" \
				"$(invreport_csv_field "$id")" "$lparcount"
		done < "$wd/workspaces.tsv"
	} > "$outdir/workspaces.csv"

	{
		echo "Workspace,Name,Id,Status,OS,OS detail,Cores,VirtualCores,ProcessorType,MemoryGb,SystemType,Licences,IpAddresses"
		while IFS=$'\037' read -r wskey wsname name id status os osdetail cores vcores proctype memgb systype lic ips
		do
			printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
				"$(invreport_csv_field "$wsname")" "$(invreport_csv_field "$name")" "$(invreport_csv_field "$id")" \
				"$(invreport_csv_field "$status")" "$(invreport_csv_field "$os")" "$(invreport_csv_field "$osdetail")" \
				"$(invreport_csv_field "$cores")" "$(invreport_csv_field "$vcores")" "$(invreport_csv_field "$proctype")" \
				"$(invreport_csv_field "$memgb")" "$(invreport_csv_field "$systype")" "$(invreport_csv_field "$lic")" \
				"$(invreport_csv_field "$ips")"
		done < "$wd/lpars.tsv"
	} > "$outdir/lpars.csv"

	{
		echo "Workspace,Name,Id,Tier,SizeGb,Bootable,AttachedTo,ReplicationEnabled,Origin"
		while IFS=$'\037' read -r wskey wsname id name tier size boot state repl attached origin
		do
			printf '%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
				"$(invreport_csv_field "$wsname")" "$(invreport_csv_field "$name")" "$(invreport_csv_field "$id")" \
				"$(invreport_csv_field "$tier")" "$(invreport_csv_field "$size")" "$(invreport_csv_field "$boot")" \
				"$(invreport_csv_field "$attached")" "$(invreport_csv_field "$repl")" "$(invreport_csv_field "$origin")"
		done < "$wd/volumes.tsv"
	} > "$outdir/volumes.csv"

	{
		echo "Workspace,Name,Id,ConsistencyGroup,ReplicationState,PrimaryRole,RemoteCopyCount"
		while IFS=$'\037' read -r wskey wsname id name cg state primary remote reason
		do
			printf '%s,%s,%s,%s,%s,%s,%s\n' \
				"$(invreport_csv_field "$wsname")" "$(invreport_csv_field "$name")" "$(invreport_csv_field "$id")" \
				"$(invreport_csv_field "$cg")" "$(invreport_csv_field "$state")" "$(invreport_csv_field "$primary")" \
				"$(invreport_csv_field "${remote:-0}")"
		done < "$wd/volumegroups.tsv"
	} > "$outdir/volume-groups.csv"

	{
		echo "Workspace,Name,Lpar,Status,CreatedAt,VolumeCount"
		while IFS=$'\037' read -r wskey wsname name lpar status created volcount isold
		do
			printf '%s,%s,%s,%s,%s,%s\n' \
				"$(invreport_csv_field "$wsname")" "$(invreport_csv_field "$name")" "$(invreport_csv_field "$lpar")" \
				"$(invreport_csv_field "$status")" "$(invreport_csv_field "$created")" "${volcount:-0}"
		done < "$wd/snapshots.tsv"
	} > "$outdir/snapshots.csv"

	{
		echo "Workspace,Name,Status,OperatingSystem,CreatedAt"
		while IFS=$'\037' read -r wskey wsname name status os created isold
		do
			printf '%s,%s,%s,%s,%s\n' \
				"$(invreport_csv_field "$wsname")" "$(invreport_csv_field "$name")" \
				"$(invreport_csv_field "$status")" "$(invreport_csv_field "$os")" "$(invreport_csv_field "$created")"
		done < "$wd/images.tsv"
	} > "$outdir/images.csv"

	{
		echo "Workspace,Name,Status,PercentComplete,CreatedAt"
		while IFS=$'\037' read -r wskey wsname name status pct created
		do
			printf '%s,%s,%s,%s,%s\n' \
				"$(invreport_csv_field "$wsname")" "$(invreport_csv_field "$name")" \
				"$(invreport_csv_field "$status")" "${pct:-0}" "$(invreport_csv_field "$created")"
		done < "$wd/volumeclones.tsv"
	} > "$outdir/volume-clones.csv"

	{
		echo "CosInstance,Bucket,CreatedAt,ObjectCount,TotalSizeBytes,UnreadableReason"
		while IFS=$'\037' read -r cosinst bucket created count size reason
		do
			printf '%s,%s,%s,%s,%s,%s\n' \
				"$(invreport_csv_field "$cosinst")" "$(invreport_csv_field "$bucket")" \
				"$(invreport_csv_field "$created")" "$(invreport_csv_field "$count")" \
				"$(invreport_csv_field "$size")" "$(invreport_csv_field "$reason")"
		done < "$wd/buckets.tsv"
	} > "$outdir/buckets.csv"

	{
		echo "Reason"
		while IFS=$'\037' read -r reason
		do
			printf '%s\n' "$(invreport_csv_field "$reason")"
		done < "$wd/unreadable.tsv"
	} > "$outdir/unreadable.csv"
}

# invreport_write_html WD OUTFILE - one self-contained HTML file (inline
# <style>, no external references), same section order/columns as
# Markdown, every value HTML-escaped.
invreport_write_html() {
	local wd="$1" outfile="$2"
	{
		printf '<!DOCTYPE html><html><head><meta charset="utf-8">'
		printf '<title>Inventory report</title><style>'
		printf 'body{font-family:Arial,sans-serif;margin:24px;color:#1a1a1a}'
		printf 'h1{font-size:22px}h2{font-size:16px;margin-top:28px;border-bottom:1px solid #ccc;padding-bottom:4px}'
		printf 'table{border-collapse:collapse;width:100%%;margin-bottom:8px}'
		printf 'th,td{border:1px solid #ccc;padding:4px 8px;text-align:left;font-size:13px}'
		printf 'th{background:#f0f0f0}ul{font-size:13px}'
		printf '</style></head><body>'
		printf '<h1>Inventory report</h1>'
		printf '<p>Generated %s.</p>' "$(date -u +"%Y-%m-%d %H:%M UTC")"

		printf '<h2>Could not be read</h2>'
		if [ -s "$wd/unreadable.tsv" ]
		then
			printf '<ul>'
			while IFS=$'\037' read -r reason
			do
				printf '<li>%s</li>' "$(invreport_html_escape "$reason")"
			done < "$wd/unreadable.tsv"
			printf '</ul>'
		else
			printf '<p>Every configured workspace, volume group and bucket was read successfully.</p>'
		fi

		printf '<h2>Totals</h2><ul>'
		while IFS= read -r line
		do
			printf '<li>%s</li>' "$(invreport_html_escape "$line")"
		done < <(invreport_totals_lines "$wd")
		printf '</ul>'

		printf '<h2>Workspaces</h2>'
		if [ ! -s "$wd/workspaces.tsv" ]
		then
			printf '<p>None found.</p>'
		else
			printf '<table><tr><th>Name</th><th>Key</th><th>Region</th><th>Zone</th><th>Id</th><th>LPARs</th></tr>'
			while IFS=$'\037' read -r key name region zone id lparcount
			do
				printf '<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>' \
					"$(invreport_html_escape "$name")" "$(invreport_html_escape "$key")" \
					"$(invreport_html_escape "$region")" "$(invreport_html_escape "$zone")" \
					"$(invreport_html_escape "$id")" "$lparcount"
			done < "$wd/workspaces.tsv"
			printf '</table>'
		fi

		printf '<h2>LPARs</h2>'
		if [ ! -s "$wd/lpars.tsv" ]
		then
			printf '<p>None found.</p>'
		else
			printf '<table><tr><th>Workspace</th><th>Name</th><th>Id</th><th>Status</th><th>OS</th><th>OS detail</th><th>Cores</th><th>Type</th><th>Memory (GB)</th><th>System type</th><th>Licences</th><th>IP addresses</th></tr>'
			while IFS=$'\037' read -r wskey wsname name id status os osdetail cores vcores proctype memgb systype lic ips
			do
				printf '<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>' \
					"$(invreport_html_escape "$wsname")" "$(invreport_html_escape "$name")" "$(invreport_html_escape "$id")" \
					"$(invreport_html_escape "$status")" "$(invreport_html_escape "$os")" "$(invreport_html_escape "$osdetail")" \
					"$(invreport_html_escape "${cores:--}")" "$(invreport_html_escape "${proctype:--}")" \
					"$(invreport_html_escape "${memgb:--}")" "$(invreport_html_escape "${systype:--}")" \
					"$(invreport_html_escape "${lic:--}")" "$(invreport_html_escape "${ips:--}")"
			done < "$wd/lpars.tsv"
			printf '</table>'
		fi

		printf '<h2>Volumes</h2>'
		if [ ! -s "$wd/volumes.tsv" ]
		then
			printf '<p>None found.</p>'
		else
			printf '<table><tr><th>Workspace</th><th>Name</th><th>Id</th><th>Tier</th><th>Size (GB)</th><th>Bootable</th><th>Attached to</th><th>Replication</th><th>Origin</th></tr>'
			while IFS=$'\037' read -r wskey wsname id name tier size boot state repl attached origin
			do
				local bootdisp=no repldisp=disabled attacheddisp="not attached"
				[ "$boot" = "true" ] && bootdisp=yes
				[ "$repl" = "true" ] && repldisp=enabled
				[ -n "$attached" ] && attacheddisp="$attached"
				printf '<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>' \
					"$(invreport_html_escape "$wsname")" "$(invreport_html_escape "$name")" "$(invreport_html_escape "$id")" \
					"$(invreport_html_escape "${tier:--}")" "$(invreport_html_escape "${size:--}")" "$bootdisp" \
					"$(invreport_html_escape "$attacheddisp")" "$repldisp" "$(invreport_html_escape "$origin")"
			done < "$wd/volumes.tsv"
			printf '</table>'
		fi

		printf '<h2>Volume groups</h2>'
		if [ ! -s "$wd/volumegroups.tsv" ]
		then
			printf '<p>None found.</p>'
		else
			printf '<table><tr><th>Workspace</th><th>Name</th><th>Id</th><th>Consistency group</th><th>State</th><th>Primary role</th><th>Remote copies</th></tr>'
			while IFS=$'\037' read -r wskey wsname id name cg state primary remote reason
			do
				local statedisp="${state:--}"
				[ -z "$state" ] && [ -n "$reason" ] && statedisp="unreadable ($reason)"
				printf '<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>' \
					"$(invreport_html_escape "$wsname")" "$(invreport_html_escape "$name")" "$(invreport_html_escape "$id")" \
					"$(invreport_html_escape "${cg:--}")" "$(invreport_html_escape "$statedisp")" \
					"$(invreport_html_escape "${primary:--}")" "${remote:-0}"
			done < "$wd/volumegroups.tsv"
			printf '</table>'
		fi

		printf '<h2>Snapshots</h2>'
		if [ ! -s "$wd/snapshots.tsv" ]
		then
			printf '<p>None found.</p>'
		else
			printf '<table><tr><th>Workspace</th><th>Name</th><th>LPAR</th><th>Status</th><th>Created</th><th>Volumes</th></tr>'
			while IFS=$'\037' read -r wskey wsname name lpar status created volcount isold
			do
				printf '<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>' \
					"$(invreport_html_escape "$wsname")" "$(invreport_html_escape "$name")" \
					"$(invreport_html_escape "${lpar:--}")" "$(invreport_html_escape "$status")" \
					"$(invreport_html_escape "${created:--}")" "${volcount:-0}"
			done < "$wd/snapshots.tsv"
			printf '</table>'
		fi

		printf '<h2>Images</h2>'
		if [ ! -s "$wd/images.tsv" ]
		then
			printf '<p>None found.</p>'
		else
			printf '<table><tr><th>Workspace</th><th>Name</th><th>Status</th><th>Operating system</th><th>Created</th></tr>'
			while IFS=$'\037' read -r wskey wsname name status os created isold
			do
				printf '<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>' \
					"$(invreport_html_escape "$wsname")" "$(invreport_html_escape "$name")" \
					"$(invreport_html_escape "$status")" "$(invreport_html_escape "${os:--}")" \
					"$(invreport_html_escape "${created:--}")"
			done < "$wd/images.tsv"
			printf '</table>'
		fi

		printf '<h2>Volume clones</h2>'
		if [ ! -s "$wd/volumeclones.tsv" ]
		then
			printf '<p>None found.</p>'
		else
			printf '<table><tr><th>Workspace</th><th>Name</th><th>Status</th><th>Percent complete</th><th>Created</th></tr>'
			while IFS=$'\037' read -r wskey wsname name status pct created
			do
				printf '<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>' \
					"$(invreport_html_escape "$wsname")" "$(invreport_html_escape "$name")" \
					"$(invreport_html_escape "$status")" "${pct:-0}" "$(invreport_html_escape "${created:--}")"
			done < "$wd/volumeclones.tsv"
			printf '</table>'
		fi

		printf '<h2>COS buckets</h2>'
		if [ ! -s "$wd/buckets.tsv" ]
		then
			printf '<p>None found.</p>'
		else
			printf '<table><tr><th>COS instance</th><th>Bucket</th><th>Created</th><th>Objects</th><th>Total size (bytes)</th></tr>'
			while IFS=$'\037' read -r cosinst bucket created count size reason
			do
				local countdisp="$count" sizedisp="${size:--}"
				if [ -n "$reason" ]
				then
					countdisp="unreadable ($reason)"
					sizedisp="-"
				fi
				printf '<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>' \
					"$(invreport_html_escape "$cosinst")" "$(invreport_html_escape "$bucket")" \
					"$(invreport_html_escape "${created:--}")" "$(invreport_html_escape "$countdisp")" "$sizedisp"
			done < "$wd/buckets.tsv"
			printf '</table>'
		fi

		printf '</body></html>'
	} > "$outfile"
}

# do_invreport FORMAT PATH OLD_DAYS - the -invreport orchestrator. Builds
# the whole report into a scratch working directory as raw TSV (one file
# per section), then renders it in the requested format(s). Read-only:
# every helper it calls is a GET (see the table this flag's own spec
# cites - ins_ls/vol_ls/vg_ls/vg_sd/snap_ls/img_ls/vol_cl_ls/
# cos_ls_buckets/list_object_page).
do_invreport() {
	local format="$1" outpath="$2" old_days="$3"
	local wd now_epoch
	wd="/tmp/bluexport_invreport_$$"
	mkdir -p "$wd" 2>>"$log_file"
	if [ ! -d "$wd" ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Could not create working directory $wd for -invreport." 1
	fi
	trap 'rm -rf "'"$wd"'"' EXIT

	local workspaces_tsv="$wd/workspaces.tsv"
	local lpars_tsv="$wd/lpars.tsv"
	local volumes_tsv="$wd/volumes.tsv"
	local volumegroups_tsv="$wd/volumegroups.tsv"
	local snapshots_tsv="$wd/snapshots.tsv"
	local images_tsv="$wd/images.tsv"
	local volumeclones_tsv="$wd/volumeclones.tsv"
	local buckets_tsv="$wd/buckets.tsv"
	invreport_unreadable_tsv="$wd/unreadable.tsv"
	: > "$workspaces_tsv"; : > "$lpars_tsv"; : > "$volumes_tsv"
	: > "$volumegroups_tsv"; : > "$snapshots_tsv"; : > "$images_tsv"
	: > "$volumeclones_tsv"; : > "$buckets_tsv"; : > "$invreport_unreadable_tsv"

	now_epoch=$(date +%s)
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - === Starting inventory report (all workspaces) ===" "1"

	read -r -a allws_array <<< "$allws"

	# --- Workspaces (local secrets file only - no API call, matches the
	# equivalent report's own Workspaces section) ---
	for ws in "${allws_array[@]}"
	do
		local ws_id ws_name zone_raw region_api base_url_var base_url_val region_host lpar_count
		ws_id=$(jq -r --arg k "$ws" '.workspaces[$k].id' "$bluexscrt")
		ws_name=$(jq -r --arg k "$ws" '.workspaces[$k].name // $k' "$bluexscrt")
		zone_raw=$(jq -r --arg k "$ws" '.workspaces[$k].crn | capture("power-iaas:(?<region>[^:]+)") | .region' "$bluexscrt" 2>>"$log_file")
		region_api=$(printf '%s' "$zone_raw" | tr '-' '_')
		base_url_var="base_${region_api}"
		base_url_val="${!base_url_var}"
		if [ -n "$base_url_val" ]
		then
			region_host=$(printf '%s' "$base_url_val" | sed -e 's#^https\{0,1\}://##' -e 's/\..*$//')
		else
			region_host="unknown ('$zone_raw' not recognised)"
		fi
		lpar_count=$(jq -r --arg k "$ws" '[(.systems // [])[] | select(.workspace == $k)] | length' "$bluexscrt")
		printf '%s\037%s\037%s\037%s\037%s\037%s\n' "$ws" "$ws_name" "$region_host" "$zone_raw" "$ws_id" "$lpar_count" >> "$workspaces_tsv"
	done

	# --- Per-workspace live sections (LPARs, Volumes, Volume groups,
	# Snapshots, Images, Volume clones) - same workspace-loop skeleton as
	# -snaplsall/-vsidetails/-vclonelsall. One bad workspace never stops
	# the others: invreport_get/invreport_unreadable name it and this
	# continues to the next.
	for ws in "${allws_array[@]}"
	do
		local CRN CLOUD_INSTANCE_ID full_ws_name region_api base_url_var
		CRN=$(jq -r --arg k "$ws" '.workspaces[$k].crn' "$bluexscrt")
		CLOUD_INSTANCE_ID=$(jq -r --arg k "$ws" '.workspaces[$k].id' "$bluexscrt")
		full_ws_name=$(jq -r --arg k "$ws" '.workspaces[$k].name // $k' "$bluexscrt")
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - === Reading workspace $full_ws_name ===" "1"
		if [[ -z "$CRN" || "$CRN" == "null" || -z "$CLOUD_INSTANCE_ID" || "$CLOUD_INSTANCE_ID" == "null" ]]
		then
			invreport_unreadable "Workspace '$full_ws_name'" "missing CRN or ID in $bluexscrt"
			continue
		fi
		region_api=$(jq -r --arg k "$ws" '.workspaces[$k].crn | capture("power-iaas:(?<region>[^:]+)") | .region | gsub("-"; "_")' "$bluexscrt")
		base_url_var="base_${region_api}"
		base_url="${!base_url_var}"
		if [ -z "$base_url" ]
		then
			invreport_unreadable "Workspace '$full_ws_name'" "unrecognised region in CRN, no base URL configured"
			continue
		fi

		# --- LPARs ---
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) -   ... LPARs" "1"
		local ins_json ins_rc
		ins_json=$(invreport_get ins_ls pvmInstances)
		ins_rc=$?
		if [ $ins_rc -ne 0 ]
		then
			invreport_unreadable "LPARs in workspace '$full_ws_name'" "$ins_json"
		else
			while IFS=$'\037' read -r l_name l_id l_status l_ostype l_cores l_vcores l_proctype l_mem l_systype l_lic l_ips
			do
				[ -z "$l_name" ] && continue
				local l_os l_osdetail
				l_os=$(jq -r --arg ws "$ws" --arg id "$l_id" '(.systems // [])[]? | select(.workspace==$ws and .pvmInstanceID==$id) | (.os // empty)' "$bluexscrt" 2>>"$log_file" | head -n1)
				l_osdetail=$(jq -r --arg ws "$ws" --arg id "$l_id" '(.systems // [])[]? | select(.workspace==$ws and .pvmInstanceID==$id) | (.osDetail // empty)' "$bluexscrt" 2>>"$log_file" | head -n1)
				[ -z "$l_os" ] && l_os="unknown"
				[ -z "$l_osdetail" ] && l_osdetail="$l_ostype"
				printf '%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\n' \
					"$ws" "$full_ws_name" "$l_name" "$l_id" "$l_status" "$l_os" "$l_osdetail" \
					"$l_cores" "$l_vcores" "$l_proctype" "$l_mem" "$l_systype" "$l_lic" "$l_ips" >> "$lpars_tsv"
			done < <(printf '%s' "$ins_json" | jq -r '.pvmInstances // [] | .[] |
				[
					.serverName,
					.pvmInstanceID,
					.status,
					(.osType // ""),
					(.processors | if . == null then "" else tostring end),
					(.virtualCores.assigned | if . == null then "" else tostring end),
					(.procType // ""),
					(.memory | if . == null then "" else tostring end),
					(.sysType // ""),
					([ (.softwareLicenses // {}) | to_entries[] | select(.value == true) | .key ] | join("; ")),
					((.networks // []) | map(.ipAddress // "?") | join("; "))
				] | @tsv' 2>>"$log_file" | tr '\t' '\037')
		fi

		# --- Volumes ---
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) -   ... Volumes" "1"
		local vol_json vol_rc
		vol_json=$(invreport_get vol_ls volumes)
		vol_rc=$?
		if [ $vol_rc -ne 0 ]
		then
			invreport_unreadable "Volumes in workspace '$full_ws_name'" "$vol_json"
		else
			while IFS=$'\037' read -r v_id v_name v_tier v_size v_boot v_state v_repl v_aux v_pvms
			do
				[ -z "$v_id" ] && continue
				local v_attached="" pid nm names=""
				if [ -n "$v_pvms" ]
				then
					local v_pvm_array
					IFS=';' read -r -a v_pvm_array <<< "$v_pvms"
					for pid in "${v_pvm_array[@]}"
					do
						[ -z "$pid" ] && continue
						nm=$(jq -r --arg ws "$ws" --arg id "$pid" '(.systems // [])[]? | select(.workspace==$ws and .pvmInstanceID==$id) | .name' "$bluexscrt" 2>>"$log_file" | head -n1)
						if [ -n "$nm" ] && [ "$nm" != "null" ]
						then
							if [ -n "$names" ]; then names="$names; $nm"; else names="$nm"; fi
						fi
					done
					v_attached="$names"
				fi
				local v_origin="Plain"
				[ "$v_aux" = "true" ] && v_origin="GRS auxiliary"
				printf '%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\n' \
					"$ws" "$full_ws_name" "$v_id" "$v_name" "$v_tier" "$v_size" "$v_boot" "$v_state" "$v_repl" "$v_attached" "$v_origin" >> "$volumes_tsv"
			done < <(printf '%s' "$vol_json" | jq -r '.volumes // [] | .[] |
				[
					.volumeID, .name, (.diskType // ""),
					(.size | if . == null then "" else tostring end),
					((.bootable // false) | tostring), (.state // ""),
					((.replicationEnabled // false) | tostring), ((.auxiliary // false) | tostring),
					((.pvmInstanceIDs // []) | join(";"))
				] | @tsv' 2>>"$log_file" | tr '\t' '\037')
		fi

		# --- Volume groups (+ replication state) ---
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) -   ... Volume groups" "1"
		local vg_json vg_rc
		vg_json=$(invreport_get vg_ls volumeGroups)
		vg_rc=$?
		if [ $vg_rc -ne 0 ]
		then
			invreport_unreadable "Volume groups in workspace '$full_ws_name'" "$vg_json"
		else
			while IFS=$'\037' read -r g_id g_name g_cg
			do
				[ -z "$g_id" ] && continue
				# storage-details (vg_sd) carries state, primaryRole AND
				# remoteCopyRelationshipNames together - one call, not the
				# vg_get()+vg_rcr() split some GRS helpers use elsewhere.
				local VOLUME_GROUP_ID="$g_id" sd_json sd_rc g_state="" g_primary="" g_remote=0 g_reason=""
				sd_json=$(invreport_get vg_sd state)
				sd_rc=$?
				if [ $sd_rc -ne 0 ]
				then
					g_reason="$sd_json"
					invreport_unreadable "Replication state of volume group '$g_name' in workspace '$full_ws_name'" "$g_reason"
				else
					g_state=$(printf '%s' "$sd_json" | jq -r '.state // ""' 2>>"$log_file")
					g_primary=$(printf '%s' "$sd_json" | jq -r '.primaryRole // ""' 2>>"$log_file")
					g_remote=$(printf '%s' "$sd_json" | jq -r '(.remoteCopyRelationshipNames // []) | length' 2>>"$log_file")
				fi
				printf '%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\n' \
					"$ws" "$full_ws_name" "$g_id" "$g_name" "$g_cg" "$g_state" "$g_primary" "$g_remote" "$g_reason" >> "$volumegroups_tsv"
			done < <(printf '%s' "$vg_json" | jq -r '.volumeGroups // [] | .[] | [.id, .name, (.consistencyGroupName // "")] | @tsv' 2>>"$log_file" | tr '\t' '\037')
		fi

		# --- Snapshots ---
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) -   ... Snapshots" "1"
		local snap_json snap_rc
		snap_json=$(invreport_get snap_ls snapshots)
		snap_rc=$?
		if [ $snap_rc -ne 0 ]
		then
			invreport_unreadable "Snapshots in workspace '$full_ws_name'" "$snap_json"
		else
			while IFS=$'\037' read -r s_name s_pvmid s_status s_created s_volcount
			do
				[ -z "$s_name" ] && continue
				local s_lpar s_isold
				s_lpar=$(jq -r --arg ws "$ws" --arg id "$s_pvmid" '(.systems // [])[]? | select(.workspace==$ws and .pvmInstanceID==$id) | .name' "$bluexscrt" 2>>"$log_file" | head -n1)
				s_isold=$(invreport_is_old "$s_created" "$old_days" "$now_epoch")
				printf '%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\n' \
					"$ws" "$full_ws_name" "$s_name" "$s_lpar" "$s_status" "$s_created" "$s_volcount" "$s_isold" >> "$snapshots_tsv"
			done < <(printf '%s' "$snap_json" | jq -r '.snapshots // [] | .[] |
				[.name, (.pvmInstanceID // ""), .status, (.creationDate // ""), ((.volumeSnapshots // []) | length)] | @tsv' 2>>"$log_file" | tr '\t' '\037')
		fi

		# --- Images ---
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) -   ... Images" "1"
		local img_json img_rc
		img_json=$(invreport_get img_ls images)
		img_rc=$?
		if [ $img_rc -ne 0 ]
		then
			invreport_unreadable "Images in workspace '$full_ws_name'" "$img_json"
		else
			while IFS=$'\037' read -r i_name i_status i_os i_created
			do
				[ -z "$i_name" ] && continue
				local i_isold
				i_isold=$(invreport_is_old "$i_created" "$old_days" "$now_epoch")
				printf '%s\037%s\037%s\037%s\037%s\037%s\037%s\n' \
					"$ws" "$full_ws_name" "$i_name" "$i_status" "$i_os" "$i_created" "$i_isold" >> "$images_tsv"
			done < <(printf '%s' "$img_json" | jq -r '.images // [] | .[] |
				[.name, .state, (.specifications.operatingSystem // ""), (.creationDate // "")] | @tsv' 2>>"$log_file" | tr '\t' '\037')
		fi

		# --- Volume clones ---
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) -   ... Volume clones" "1"
		local vcl_json vcl_rc
		vcl_json=$(invreport_get vol_cl_ls volumesClone)
		vcl_rc=$?
		if [ $vcl_rc -ne 0 ]
		then
			invreport_unreadable "Volume clones in workspace '$full_ws_name'" "$vcl_json"
		else
			while IFS=$'\037' read -r c_name c_status c_pct c_created
			do
				[ -z "$c_name" ] && continue
				printf '%s\037%s\037%s\037%s\037%s\037%s\n' \
					"$ws" "$full_ws_name" "$c_name" "$c_status" "$c_pct" "$c_created" >> "$volumeclones_tsv"
			done < <(printf '%s' "$vcl_json" | jq -r '.volumesClone // [] | .[] |
				[.name, .status, ((.percentComplete // 0) | tostring), (.creationDate // "")] | @tsv' 2>>"$log_file" | tr '\t' '\037')
		fi
	done

	# --- COS buckets (+ object counts/sizes where credentials allow it) ---
	local cos_keys
	cos_keys=$(jq -r '.cos_instances | keys[]?' "$bluexscrt" 2>>"$log_file")
	if [ -n "$cos_keys" ]
	then
		while IFS= read -r cos
		do
			[ -z "$cos" ] && continue
			local SERVICE_INSTANCE_ID
			SERVICE_INSTANCE_ID=$(jq -r --arg ci "$cos" '.cos_instances[$ci].guid // ""' "$bluexscrt" 2>>"$log_file")
			if [[ -z "$SERVICE_INSTANCE_ID" || "$SERVICE_INSTANCE_ID" == "null" ]]
			then
				invreport_unreadable "COS instance '$cos'" "no GUID in $bluexscrt"
				continue
			fi
			REGION="$region"
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - === Reading COS instance $cos ===" "1"
			local buckets_xml bret
			buckets_xml=$(cos_ls_buckets 2>>"$log_file")
			bret=$?
			if [ $bret -ne 0 ] || [ -z "$buckets_xml" ]
			then
				invreport_unreadable "Buckets in COS instance '$cos'" "request failed or empty response (curl rc=$bret)"
				continue
			fi
			local bxml="$buckets_xml"
			while [[ "$bxml" == *"<Bucket>"*"</Bucket>"* ]]
			do
				local bchunk bname bdate
				bchunk="${bxml#*<Bucket>}"
				bchunk="${bchunk%%</Bucket>*}"
				bxml="${bxml#*</Bucket>}"
				bname=""
				if [[ "$bchunk" == *"<Name>"*"</Name>"* ]]
				then
					bname="${bchunk#*<Name>}"
					bname="${bname%%</Name>*}"
				fi
				[ -z "$bname" ] && continue
				bdate=""
				if [[ "$bchunk" == *"<CreationDate>"*"</CreationDate>"* ]]
				then
					bdate="${bchunk#*<CreationDate>}"
					bdate="${bdate%%</CreationDate>*}"
				fi
				echoscreen "$(date +%Y-%m-%d_%H:%M:%S) -   ... bucket $bname" "1"
				BUCKET="$bname"
				local obj_line obj_count obj_size obj_reason
				obj_line=$(invreport_bucket_objects)
				IFS=$'\037' read -r obj_count obj_size obj_reason <<< "$obj_line"
				if [ -n "$obj_reason" ]
				then
					invreport_unreadable "Objects in bucket '$bname' (COS instance '$cos')" "$obj_reason"
					printf '%s\037%s\037%s\037%s\037%s\037%s\n' "$cos" "$bname" "$bdate" "" "" "$obj_reason" >> "$buckets_tsv"
				else
					printf '%s\037%s\037%s\037%s\037%s\037%s\n' "$cos" "$bname" "$bdate" "$obj_count" "$obj_size" "" >> "$buckets_tsv"
				fi
			done
		done <<< "$cos_keys"
	fi

	# --- Totals (mirrors the equivalent report's own totals: workspace/
	# LPAR/volume/snapshot/image counts, memory/cores known, storage by
	# tier, unattached volumes, and old snapshots/images past OLD_DAYS) ---
	local t_workspaces t_lpars t_lpars_mem t_mem_sum t_lpars_cores t_cores_sum
	local t_vol_count t_vol_unattached t_snap_count t_snap_old t_img_count t_img_old
	t_workspaces=$(wc -l < "$workspaces_tsv" | tr -d ' ')
	t_lpars=$(wc -l < "$lpars_tsv" | tr -d ' ')
	t_lpars_mem=$(awk -F'\037' '$11!=""{c++} END{print c+0}' "$lpars_tsv")
	t_mem_sum=$(awk -F'\037' '$11!=""{s+=$11} END{print s+0}' "$lpars_tsv")
	t_lpars_cores=$(awk -F'\037' '$8!=""{c++} END{print c+0}' "$lpars_tsv")
	t_cores_sum=$(awk -F'\037' '$8!=""{s+=$8} END{print s+0}' "$lpars_tsv")
	t_vol_count=$(wc -l < "$volumes_tsv" | tr -d ' ')
	t_vol_unattached=$(awk -F'\037' '$10==""{c++} END{print c+0}' "$volumes_tsv")
	t_snap_count=$(wc -l < "$snapshots_tsv" | tr -d ' ')
	t_snap_old=$(awk -F'\037' '$8==1{c++} END{print c+0}' "$snapshots_tsv")
	t_img_count=$(wc -l < "$images_tsv" | tr -d ' ')
	t_img_old=$(awk -F'\037' '$7==1{c++} END{print c+0}' "$images_tsv")
	awk -F'\037' '{ t=$5; if (t=="") t="unknown"; s[t]+=($6==""?0:$6) } END { for (k in s) printf "%s\037%s\n", k, s[k] }' "$volumes_tsv" | sort > "$wd/storage_by_tier.tsv"

	{
		printf 'WorkspaceCount\037%s\n' "$t_workspaces"
		printf 'LparCount\037%s\n' "$t_lpars"
		printf 'LparsWithMemoryKnown\037%s\n' "$t_lpars_mem"
		printf 'TotalMemoryGb\037%s\n' "$(invreport_fmt_num "$t_mem_sum")"
		printf 'LparsWithCoresKnown\037%s\n' "$t_lpars_cores"
		printf 'TotalCores\037%s\n' "$(invreport_fmt_num "$t_cores_sum")"
		while IFS=$'\037' read -r tier gb
		do
			printf 'StorageGb.%s\037%s\n' "$tier" "$(invreport_fmt_num "$gb")"
		done < "$wd/storage_by_tier.tsv"
		printf 'VolumeCount\037%s\n' "$t_vol_count"
		printf 'UnattachedVolumeCount\037%s\n' "$t_vol_unattached"
		printf 'SnapshotCount\037%s\n' "$t_snap_count"
		printf 'OldSnapshotCount\037%s\n' "$t_snap_old"
		printf 'ImageCount\037%s\n' "$t_img_count"
		printf 'OldImageCount\037%s\n' "$t_img_old"
		printf 'OldThresholdDays\037%s\n' "$old_days"
	} > "$wd/totals.tsv"

	# Make sure PATH's own directory exists before writing md/html - csv
	# already does this itself (mkdir -p "$outdir" in invreport_write_csv)
	# since PATH-csv/ is a directory either way, but a caller-supplied
	# PATH with a missing parent must not silently drop the md/html files.
	local outdir_parent
	outdir_parent=$(dirname "$outpath")
	if [ -n "$outdir_parent" ] && [ "$outdir_parent" != "." ]
	then
		mkdir -p "$outdir_parent" 2>>"$log_file"
	fi

	case "$format" in
		md)
			invreport_write_md "$wd" "$outpath.md"
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Report written to $outpath.md" "1"
			;;
		csv)
			invreport_write_csv "$wd" "$outpath-csv"
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Report written to $outpath-csv/" "1"
			;;
		html)
			invreport_write_html "$wd" "$outpath.html"
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Report written to $outpath.html" "1"
			;;
		all)
			invreport_write_md "$wd" "$outpath.md"
			invreport_write_html "$wd" "$outpath.html"
			invreport_write_csv "$wd" "$outpath-csv"
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Report written to $outpath.md, $outpath.html and $outpath-csv/" "1"
			;;
	esac

	abort "$(date +%Y-%m-%d_%H:%M:%S) - === Finished inventory report ==="
}
#### END:FUNCTIONS - Inventory report (-invreport) ####


       ####  END - FUNCTIONS  ####

####  START: Iniciate Log and Validate Arguments  ####
timestamp=$(date +%F" "%T" "%Z)
echo "==== START ======= $timestamp =========" | tee -a $log_file
echo "Flags Used: $@" | tee -a $log_file
if [ $# -eq 0 ]
then
	help
	abort "`date +%Y-%m-%d_%H:%M:%S` - No arguments supplied!!" 1
fi

#### START: usage_X() - per-flag parameter detail (shown on argument-count error and via -h -FLAG) ####
usage_j() {
	echoscreen "  VSI_NAME:"
	echoscreen "    Name of the VSI whose capture job to monitor."
	echoscreen "  IMAGE_NAME:"
	echoscreen "    Capture image name (as passed to -a/-x when the capture was started)."
}

usage_a() {
	echoscreen "  VSI_NAME:"
	echoscreen "    Name of the VSI to capture."
	echoscreen "  IMAGE_NAME:"
	echoscreen "    Base name for the capture image; a timestamp suffix is appended."
	echoscreen "  DESTINATION:"
	echoscreen "    both|image-catalog|cloud-storage - where the capture ends up."
	echoscreen "    hourly/daily only allow image-catalog (not cloud-storage or both)."
	echoscreen "  RECURRENCE:"
	echoscreen "    hourly|daily|weekly|monthly|single - controls the retention window"
	echoscreen "    used to identify the previous capture to clean up."
	echoscreen "  Note: -ta runs the same flow in test mode - it validates and logs"
	echoscreen "  everything but does not actually run the capture."
}

usage_x() {
	echoscreen "  EXCLUDE_NAME:"
	echoscreen "    Volume name pattern(s) to exclude from the capture (space separated;"
	echoscreen "    matched case-insensitively as a regex against each volume name -"
	echoscreen "    avoid regex metacharacters in names)."
	echoscreen "  VSI_NAME:"
	echoscreen "    Name of the VSI to capture."
	echoscreen "  IMAGE_NAME:"
	echoscreen "    Base name for the capture image; a timestamp suffix is appended."
	echoscreen "  DESTINATION:"
	echoscreen "    both|image-catalog|cloud-storage - where the capture ends up."
	echoscreen "    hourly/daily only allow image-catalog (not cloud-storage or both)."
	echoscreen "  RECURRENCE:"
	echoscreen "    hourly|daily|weekly|monthly|single - controls the retention window"
	echoscreen "    used to identify the previous capture to clean up."
	echoscreen "  Note: -tx runs the same flow in test mode - it validates and logs"
	echoscreen "  everything but does not actually run the capture."
}

usage_imgdel() {
	echoscreen "  IMG_NAME:"
	echoscreen "    Name of the captured image to delete (searched across all workspaces)."
}

usage_imgimport() {
	echoscreen "  IMGNAME:"
	echoscreen "    COS object filename to import (e.g. myimage.ova.gz)."
	echoscreen "  BUCKET:"
	echoscreen "    COS bucket name where the object is stored."
	echoscreen "  BUCKET_REGION:"
	echoscreen "    IBM COS S3 endpoint region where the source bucket exists."
	echoscreen "    Examples: eu-es, eu-de, us-east, us-south."
	echoscreen "    Do not use the PowerVS datacenter name here (e.g. mad02)."
	echoscreen "  WORKSPACE_TO_IMPORT:"
	echoscreen "    Target PowerVS workspace, short or full name."
	echoscreen "  IMGNAME_WS:"
	echoscreen "    Name to give the imported image in the workspace's image catalog."
	echoscreen "  STORAGE_TYPE:"
	echoscreen "    tier0|tier1|tier3|tier5k."
	echoscreen "  CURRACCOUNT|OTHERACCOUNT:"
	echoscreen "    COS account type. OTHERACCOUNT requires HMAC JSON file from IBM"
	echoscreen "    Cloud COS Service Credentials (.cos_hmac_keys.access_key_id and"
	echoscreen "    .cos_hmac_keys.secret_access_key)."
	echoscreen "  HMAC_JSON_FILE:"
	echoscreen "    Optional; required only for OTHERACCOUNT."
}

usage_imgexport() {
	echoscreen "  IMGNAME:"
	echoscreen "    Name of the captured image (in the workspace catalog) to export."
	echoscreen "  BUCKET:"
	echoscreen "    COS bucket name to export to; may include a folder prefix"
	echoscreen "    (bucketName/optional/folder)."
	echoscreen "  BUCKET_REGION:"
	echoscreen "    IBM COS S3 endpoint region where the destination bucket exists."
	echoscreen "    Examples: eu-es, eu-de, us-east, us-south."
	echoscreen "  CURRACCOUNT|OTHERACCOUNT:"
	echoscreen "    COS account type. OTHERACCOUNT requires the same HMAC JSON file"
	echoscreen "    format as -imgimport - copy hmac_keys_example.json to a file"
	echoscreen "    outside this repository and fill in your keys."
	echoscreen "  HMAC_JSON_FILE:"
	echoscreen "    Optional; required only for OTHERACCOUNT."
}

usage_ji() {
	echoscreen "  WORKSPACE:"
	echoscreen "    PowerVS workspace (short or full name) whose last image import job"
	echoscreen "    to re-attach monitoring to. No image name needed - PowerVS tracks"
	echoscreen "    one import job per workspace."
}

usage_je() {
	echoscreen "  IMAGE_NAME:"
	echoscreen "    Name of the image (searched across every workspace) whose last"
	echoscreen "    export job to re-attach monitoring to."
}

# (1.21.0)
usage_jobsls() {
	echoscreen "  WORKSPACE:"
	echoscreen "    PowerVS workspace (short or full name) whose jobs to list."
}

# (1.21.0)
usage_jobget() {
	echoscreen "  JOB_ID:"
	echoscreen "    Job ID to show full detail for (searched across every configured"
	echoscreen "    workspace, same lookup as -imgdel/-je)."
}

# (1.21.0)
usage_jobcancel() {
	echoscreen "  JOB_ID:"
	echoscreen "    Job ID to cancel/delete (searched across every configured workspace)."
	echoscreen "    Refused unless the job's own status still allows it - an already-finished"
	echoscreen "    job (completed/failed) has nothing to cancel. Asks for confirmation (type"
	echoscreen "    the Job ID back) before sending the request, the same as"
	echoscreen "    -vclone/-vclonedel/-vchtier/-insvchtier."
}

usage_snapcr() {
	echoscreen "  VSI_NAME:"
	echoscreen "    Name of the VSI to snapshot."
	echoscreen "  SNAPSHOT_NAME:"
	echoscreen "    Name for the new snapshot; must not already exist for this VSI."
	echoscreen "  DESCRIPTION:"
	echoscreen "    Optional. Pass 0 to omit, or a quoted description string."
	echoscreen "  VOLUMES:"
	echoscreen "    Optional. Pass 0 for all attached volumes, or a comma-separated"
	echoscreen "    list of volume names or IDs to snapshot only those."
}

usage_snapupd() {
	echoscreen "  SNAPSHOT_NAME:"
	echoscreen "    Name of the existing snapshot to update (searched across all"
	echoscreen "    workspaces)."
	echoscreen "  NEW_SNAPSHOT_NAME:"
	echoscreen "    Optional. Pass 0 to keep the current name, or a new name."
	echoscreen "  DESCRIPTION:"
	echoscreen "    Optional. Pass 0 to keep the current description, or a quoted"
	echoscreen "    new description."
	echoscreen "  At least one of NEW_SNAPSHOT_NAME/DESCRIPTION must differ from 0."
}

usage_snapdel() {
	echoscreen "  SNAPSHOT_NAME:"
	echoscreen "    Name of the snapshot to delete (searched across all workspaces)."
}

usage_snapres() {
	echoscreen "  VSI_NAME:"
	echoscreen "    VSI to restore the snapshot onto."
	echoscreen "  SNAPSHOT_NAME:"
	echoscreen "    Name of the snapshot to restore."
}

usage_vclone() {
	echoscreen "  REQUEST_CLONE_NAME:"
	echoscreen "    Name for the new volume clone request; must not already exist."
	echoscreen "  VOLUME_BASE_NAME:"
	echoscreen "    Common name/prefix used to label the cloned volumes."
	echoscreen "  LPAR_NAME:"
	echoscreen "    VSI that owns the source volumes to clone."
	echoscreen "  REPLICATION:"
	echoscreen "    True|False - whether to enable replication on the clone."
	echoscreen "  ROLLBACK:"
	echoscreen "    True|False - whether to prepare the clone for rollback."
	echoscreen "  TARGET_TIER:"
	echoscreen "    tier0|tier1|tier3|tier5k. (Unlike -vchtier's TIER_TO_CHANGE_TO,"
	echoscreen "    this DOES need the \"tier\" prefix.)"
	echoscreen "  VOLUMES:"
	echoscreen "    ALL for every volume attached to LPAR_NAME, or a comma-separated"
	echoscreen "    list of volume NAMES (not IDs, despite what the nearby \"# Args:\""
	echoscreen "    inline code comment for this flag might suggest) to clone only"
	echoscreen "    those (at least 2 required)."
}

usage_vclonedel() {
	echoscreen "  REQUEST_CLONE_NAME:"
	echoscreen "    Name of the volume clone request to delete (searched across all"
	echoscreen "    workspaces)."
	echoscreen "  MODE:"
	echoscreen "    Optional (defaults to 0). Pass 0 to delete only the clone request,"
	echoscreen "    or delete_volumes to also delete the cloned volumes themselves."
	echoscreen "  NOTE:"
	echoscreen "    IBM Cloud only deletes a clone request once it is completed, failed"
	echoscreen "    or cancelled. If it is still available/running/preparing, you will"
	echoscreen "    be asked (separately from the delete confirmation above) whether to"
	echoscreen "    cancel it first; anything still creating/executing/cancelling must"
	echoscreen "    be waited out and retried."
}

usage_vchtier() {
	echoscreen "  VSI_NAME:"
	echoscreen "    VSI that owns the volumes to change tier."
	echoscreen "  VOLUMES_NAME:"
	echoscreen "    Common name/pattern (space-separated if more than one) matched"
	echoscreen "    against volume names attached to VSI_NAME."
	echoscreen "  TIER_TO_CHANGE_TO:"
	echoscreen "    0|1|3|5k - the script prepends \"tier\" automatically."
	echoscreen "    (Note: unlike -vclone's TARGET_TIER, do NOT include the \"tier\""
	echoscreen "    prefix yourself here.)"
}

usage_insvchtier() {
	echoscreen "  VSI_NAME:"
	echoscreen "    VSI whose ALL attached volumes will change tier."
	echoscreen "  TIER_TO_CHANGE_TO:"
	echoscreen "    0|1|3|5k - the script prepends \"tier\" automatically, same as"
	echoscreen "    -vchtier (see that flag's note about the prefix)."
}

usage_creategrs() {
	echoscreen "  SOURCE_VSI:"
	echoscreen "    VSI whose volumes are the replication source."
	echoscreen "  TARGET_VSI:"
	echoscreen "    VSI that will receive the replicated volumes."
	echoscreen "  VG_NAME:"
	echoscreen "    Name for the new volume group (replication group)."
	echoscreen "  SOURCE_VOLUMES_NAME:"
	echoscreen "    Common name/prefix of the source volumes. NOTE: it does NOT limit"
	echoscreen "    which volumes join the group - EVERY volume attached to SOURCE_VSI"
	echoscreen "    is added and gets replicationEnabled=true. The prefix is used to"
	echoscreen "    match volumes while waiting for consistent_copying and to label the"
	echoscreen "    target onboarding request; pass the same value to -deletegrs."
	echoscreen "  Fails if ANY volume attached to SOURCE_VSI already has a snapshot -"
	echoscreen "  delete those snapshots first."
}

usage_deletegrs() {
	echoscreen "  SOURCE_VSI:"
	echoscreen "    VSI on the source side of the replication group."
	echoscreen "  TARGET_VSI:"
	echoscreen "    VSI on the target side of the replication group."
	echoscreen "  VG_NAME:"
	echoscreen "    Name of the volume group (replication group) to delete."
	echoscreen "  SOURCE_VOLUME_NAMES:"
	echoscreen "    Same value used with -creategrs. Kept for compatibility: since"
	echoscreen "    1.19.2 the volumes touched are the volume groups' own members, on"
	echoscreen "    both sides, never every volume whose name matches this value."
	echoscreen "  NOTE:"
	echoscreen "    All volumes, boot included, are detached from TARGET_VSI. Auxiliary"
	echoscreen "    volumes are deleted only when each reads replicationEnabled=false"
	echoscreen "    and is attached to no LPAR."
}

usage_grsfailover() {
	echoscreen "  SOURCE_VSI:"
	echoscreen "    VSI on the source side of the replication group."
	echoscreen "  VG_NAME:"
	echoscreen "    Name of the volume group to fail over."
	echoscreen "  MODE:"
	echoscreen "    NO_ATTACH|ATTACH - whether to also attach the failed-over volumes"
	echoscreen "    to a VSI immediately."
	echoscreen "  TARGET_VSI:"
	echoscreen "    Required only when MODE=ATTACH; VSI to attach the volumes to."
}

usage_grscancelfailover() {
	echoscreen "  SOURCE_VSI:"
	echoscreen "    VSI on the source side of the replication group."
	echoscreen "  VG_NAME:"
	echoscreen "    Name of the volume group to cancel failover on."
	echoscreen "  MODE:"
	echoscreen "    NO_DETACH|DETACH - whether to also detach the volumes from"
	echoscreen "    TARGET_VSI before cancelling."
	echoscreen "  TARGET_VSI:"
	echoscreen "    VSI the failed-over volumes are currently attached to."
}

usage_grsfailback() {
	echoscreen "  SOURCE_VSI:"
	echoscreen "    VSI on the source side of the replication group."
	echoscreen "  TARGET_VSI:"
	echoscreen "    VSI on the target side of the replication group."
	echoscreen "  VG_NAME:"
	echoscreen "    Name of the volume group to fail back to the source."
}

usage_grsreversereplica() {
	echoscreen "  SOURCE_VSI:"
	echoscreen "    VSI currently on the source side of the replication group."
	echoscreen "  TARGET_VSI:"
	echoscreen "    VSI currently on the target side of the replication group."
	echoscreen "  VG_NAME:"
	echoscreen "    Name of the volume group whose replication direction to reverse."
}

usage_vsistart() {
	echoscreen "  VSI_NAME:"
	echoscreen "    Name of the VSI to start."
}

usage_vsioper() {
	echoscreen "  VSI_NAME:"
	echoscreen "    Name of the VSI to change boot/operating mode for."
	echoscreen "  BOOT_MODE:"
	echoscreen "    a|b|c|d."
	echoscreen "  OPERATING_MODE:"
	echoscreen "    normal|manual."
}

usage_vsitask() {
	echoscreen "  VSI_NAME:"
	echoscreen "    Name of the VSI to run the task on."
	echoscreen "  TASK:"
	echoscreen "    dston|retrydump|consoleservice|iopreset|remotedstoff|remotedston|"
	echoscreen "    iopdump|dumprestart."
}

usage_vsisrcmon() {
	echoscreen "  VSI_NAME:"
	echoscreen "    Name of the VSI whose SRC (reference code) to monitor."
	echoscreen "  MODE:"
	echoscreen "    START|SHUTOFF - which state transition to wait for."
	echoscreen ""
	echoscreen "  Monitoring stops after 4 hours by default. Set the environment"
	echoscreen "  variable BLUEXPORT_SRCMON_TIMEOUT to a number of seconds to change"
	echoscreen "  it. A timeout is reported as a timeout, never as a failed IPL, and"
	echoscreen "  re-running the same command resumes monitoring."
}

usage_attachvolumes() {
	echoscreen "  VOLUMES_COMMON_NAME:"
	echoscreen "    Common name/pattern matched against existing volume names -"
	echoscreen "    every match gets attached."
	echoscreen "  VSI_NAME:"
	echoscreen "    Target VSI to attach the volumes to; must be SHUTOFF."
}

usage_detachvolumes() {
	echoscreen "  VSI_NAME:"
	echoscreen "    VSI to detach ALL currently attached volumes from."
}

usage_restorefromarchive() {
	echoscreen "  BUCKET:"
	echoscreen "    COS bucket name containing the archived object."
	echoscreen "  OBJECT:"
	echoscreen "    Key/path of the archived object to restore."
	echoscreen "  DAYS:"
	echoscreen "    Optional; number of days the restored copy stays available."
	echoscreen "    Defaults to 3 if omitted."
	echoscreen "  ARCHIVE_TYPE:"
	echoscreen "    Optional; Bulk|Accelerated. Defaults to Accelerated"
	echoscreen "    if omitted."
}

usage_chscrt() {
	echoscreen "  SECRETS_FILE:"
	echoscreen "    Optional; full path to a bluexscrt_*.json file to switch to."
	echoscreen "    If omitted, lists available bluexscrt*.json files and prompts"
	echoscreen "    interactively (also then prompts for a new log file path)."
}

usage_invreport() {
	echoscreen "  FORMAT:"
	echoscreen "    Optional; md|csv|html|all (case-insensitive). Default: md."
	echoscreen "    md   - one Markdown file, PATH.md (source of truth)."
	echoscreen "    csv  - one CSV file per section, under PATH-csv/."
	echoscreen "    html - one self-contained HTML file, PATH.html."
	echoscreen "    all  - writes md, html and the csv folder in one run."
	echoscreen "  PATH:"
	echoscreen "    Optional; base output path, no extension. Default:"
	echoscreen "    ./bluexport-inventory-YYYYMMDD-HHMM"
	echoscreen "  OLD_DAYS:"
	echoscreen "    Optional; age in days used for the old snapshot/image"
	echoscreen "    counts in Totals. Default: 90."
	echoscreen "  Read-only: never writes to the account, only to the"
	echoscreen "  report file(s). A workspace, volume group or bucket that"
	echoscreen "  cannot be read is named in the report's own \"Could not"
	echoscreen "  be read\" section; it never aborts the whole report."
}

#### END: usage_X() functions ####

case $1 in
   -h | --help | -help)
	if [ $# -gt 2 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport_api.sh -h [-FLAG]" 1
	fi
	if [ $# -eq 2 ]
	then
		case "$2" in
			-j) usage_j ;;
			-a|-ta) usage_a ;;
			-x|-tx) usage_x ;;
			-imgdel) usage_imgdel ;;
			-imgimport) usage_imgimport ;;
			-imgexport) usage_imgexport ;;
			-ji) usage_ji ;;
			-je) usage_je ;;
			-jobsls) usage_jobsls ;;
			-jobget) usage_jobget ;;
			-jobcancel) usage_jobcancel ;;
			-snapcr) usage_snapcr ;;
			-snapupd) usage_snapupd ;;
			-snapdel) usage_snapdel ;;
			-snapres) usage_snapres ;;
			-vclone) usage_vclone ;;
			-vclonedel) usage_vclonedel ;;
			-vchtier) usage_vchtier ;;
			-insvchtier) usage_insvchtier ;;
			-creategrs) usage_creategrs ;;
			-deletegrs) usage_deletegrs ;;
			-grsfailover) usage_grsfailover ;;
			-grscancelfailover) usage_grscancelfailover ;;
			-grsfailback) usage_grsfailback ;;
			-grsreversereplica) usage_grsreversereplica ;;
			-vsistart) usage_vsistart ;;
			-vsioper) usage_vsioper ;;
			-vsitask) usage_vsitask ;;
			-vsisrcmon) usage_vsisrcmon ;;
			-attachvolumes) usage_attachvolumes ;;
			-detachvolumes) usage_detachvolumes ;;
			-restorefromarchive) usage_restorefromarchive ;;
			-chscrt) usage_chscrt ;;
			-invreport) usage_invreport ;;
			*)
				abort "`date +%Y-%m-%d_%H:%M:%S` - Unknown flag for detailed help: $2. Run bluexport_api.sh -h for the full command list." 1
				;;
		esac
		abort "`date +%Y-%m-%d_%H:%M:%S` - Detailed help for $2 shown above."
	fi
	help
	abort "`date +%Y-%m-%d_%H:%M:%S` - Help requested!!"
    ;;

   -j)
	if [ $# -lt 3 ]
	then
		echoscreen "Flag -j selected, but Arguments Missing!! Syntax: bluexport_api.sh -j VSI_NAME IMAGE_NAME"
		usage_j
		abort "`date +%Y-%m-%d_%H:%M:%S` - Flag -j selected, but Arguments Missing!! Syntax: bluexport_api.sh -j VSI_NAME IMAGE_NAME" 1
	fi
	if [ $# -gt 3 ]
	then
		echoscreen "Flag -j selected, but too many arguments!! Syntax: bluexport_api.sh -j VSI_NAME IMAGE_NAME"
		usage_j
		abort "`date +%Y-%m-%d_%H:%M:%S` - Flag -j selected, but too many arguments!! Syntax: bluexport_api.sh -j VSI_NAME IMAGE_NAME" 1
	fi
	vsi=$2
	capture_name=${3^^}
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Flag -j selected, watching only the Job Status for Capture Image $capture_name! Logging at $HOME/bluexport_j_$capture_name.log" "1"
	timestamp=$(date +%F" "%T" "%Z)
	echo "==== END ========= $timestamp =========" >> $log_file
	flagj=1
	log_file="$HOME/bluexport_j_"$capture_name".log"
	echoscreen "" "1"
	timestamp=$(date +%F" "%T" "%Z)
	echo "==== START ======= $timestamp =========" >> $log_file
	echo "Flags Used: $@" >> $log_file
	vsi_id_bluexscrt
	check_locally_VSI_exists
	job_monitor
    ;;

   -a | -ta)
	if [ $# -lt 5 ]
	then
		usage_a
		abort "`date +%Y-%m-%d_%H:%M:%S` - Arguments Missing!! Syntax: bluexport_api.sh $1 VSI_NAME IMAGE_NAME both|image-catalog|cloud-storage hourly|daily|weekly|monthly|single" 1
	fi
	if [ $# -gt 5 ]
	then
		usage_a
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport_api.sh $1 VSI_NAME IMAGE_NAME both|image-catalog|cloud-storage hourly|daily|weekly|monthly|single" 1
	fi
	destination=$4
	capture_img_name=${3^^}
	capture_name=$capture_img_name"_"$capture_time
	if [[ $5 == "hourly" ]] || [[ $5 == "daily" ]]
	then
		if [[ $destination == "both" ]] || [[ $destination == "cloud-storage" ]]
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` - Destination $destination is not valid with hourly and daily parameter!! Only image-catalog is possible." 1
		fi
		if [[ $5 == "hourly" ]]
		then
			old_img=$(date --date '1 hour ago' "+_%H")
			old_is_hour=1
			capture_name=$capture_img_name"_"$capture_hour
		fi
		if [[ $5 == "daily" ]]
		then
			old_img=$(date --date '1 day ago' "+%Y-%m-%d")
		fi
	elif [[ $5 == "weekly" ]]
	then
		old_img=$(date --date '1 week ago' "+%Y-%m-%d")
	elif [[ $5 == "monthly" ]]
	then
		old_img=$(date --date '1 month ago' "+%Y-%m-%d")
	elif [[ $5 == "single" ]]
	then
		single=1
	else
		abort "`date +%Y-%m-%d_%H:%M:%S` - Reocurrence must be weekly or monthly or single!" 1
	fi
	if [[ $1 == "-ta" ]]
	then
		test=1
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Flag -t selected. Logging at $job_test_log" "1"
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Testing only!! No Capture will be done!" "1"
		timestamp=$(date +%F" "%T" "%Z)
		echo "==== END ========= $timestamp =========" >> $log_file
		log_file=$job_test_log
		timestamp=$(date +%F" "%T" "%Z)
		echo "==== START ======= $timestamp =========" >> $log_file
		echo "Flags Used: $@" >> $log_file
	else
		test=0
	fi
	vsi=$2
	vsi_id_bluexscrt
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Starting Capture&Export for VSI Name: $vsi ..." "1"
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Capture Name: $capture_name" "1"
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Export Destination: $destination" "1"
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Export Bucket: $bucket" "1"
	if [[ $destination == "both" ]] || [[ $destination == "image-catalog" ]] || [[ $destination == "cloud-storage" ]]
	then
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Export Destination $destination is valid." "1"
	else
		abort "`date +%Y-%m-%d_%H:%M:%S` - Export Destination $destination is NOT valid!" 1
	fi
	volumes_cmd="ins_vol_ls | jq -r '.volumes[] | \"\(.volumeID) \(.name)\"'"
    ;;

   -x | -tx)
	if [ $# -lt 6 ]
	then
		usage_x
		abort "`date +%Y-%m-%d_%H:%M:%S` - Arguments Missing!! Syntax: bluexport_api.sh $1 EXCLUDE_NAME VSI_NAME IMAGE_NAME both|image-catalog|cloud-storage hourly|daily|weekly|monthly|single" 1
	fi
	if [ $# -gt 6 ]
	then
		usage_x
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport_api.sh $1 EXCLUDE_NAME VSI_NAME IMAGE_NAME both|image-catalog|cloud-storage hourly|daily|weekly|monthly|single" 1
	fi
	# Fix (1.18.4): destination is assigned HERE, before the recurrence check reads it.
	# It used to be assigned 46 lines further down, so the check below compared an empty
	# string, never fired, and -x accepted hourly/daily with both or cloud-storage - the
	# combination -a has always refused.
	destination=$5
	capture_img_name=${4^^}
	capture_name=$capture_img_name"_"$capture_time
	if [[ $6 == "hourly" ]] || [[ $6 == "daily" ]]
	then
		if [[ $destination == "both" ]] || [[ $destination == "cloud-storage" ]]
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` - Destination $destination is not valid with hourly and daily parameter!! Only image-catalog is possible." 1
		fi
		if [[ $6 == "hourly" ]]
		then
			# Fix (1.18.2): "+_%H", not "+%H", matching -a at the same point. A bare
			# two-digit hour matched the ISO DATE in a capture name as readily as the time,
			# so at 14:00 on the 13th "13" selected the capture just taken for deletion.
			#
			# Fix (1.18.3): the underscore alone is not enough, because a capture name's
			# date ALSO begins right after one - _20 matches NAME_2026-09-13_1400. That hit
			# -a as well. old_is_hour tells delete_previous_img to anchor the comparison.
			old_img=$(date --date '1 hour ago' "+_%H")
			old_is_hour=1
			capture_name=$capture_img_name"_"$capture_hour
		fi
		if [[ $6 == "daily" ]]
		then
			old_img=$(date --date '1 day ago' "+%Y-%m-%d")
		fi
	elif [[ $6 == "weekly" ]]
	then
		old_img=$(date --date '1 week ago' "+%Y-%m-%d")
	elif [[ $6 == "monthly" ]]
	then
		old_img=$(date --date '1 month ago' "+%Y-%m-%d")
	elif [[ $6 == "single" ]]
	then
		single=1
	else
		abort "`date +%Y-%m-%d_%H:%M:%S` - Reocurrence must be weekly or monthly or single!" 1
	fi
	if [[ $1 == "-tx" ]]
	then
		test=1
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Flag -t selected. Logging at $job_test_log" "1"
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Testing only!! No Capture will be done!" "1"
		timestamp=$(date +%F" "%T" "%Z)
		echo "==== END ========= $timestamp =========" >> $log_file
		log_file=$job_test_log
		timestamp=$(date +%F" "%T" "%Z)
		echo "==== START ======= $timestamp =========" >> $log_file
		echo "Flags Used: $@" >> $log_file
	else
		test=0
	fi
	exclude_names=$2
	exclude_names_regex=$(printf "%s" "$exclude_names" | sed 's/ /|/g')
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Volumes Name to exclude: ${exclude_names[*]}" "1"
	vsi=$3
	vsi_id_bluexscrt
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Starting Capture&Export for VSI Name: $vsi ..." "1"
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Capture Name: $capture_name" "1"
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Export Destination: $destination" "1"
	if [[ $destination == "both" ]] || [[ $destination == "image-catalog" ]] || [[ $destination == "cloud-storage" ]]
	then
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Export Destination $destination is valid!" "1"
	else
		abort "`date +%Y-%m-%d_%H:%M:%S` - Export Destination $destination is NOT valid!" 1
	fi
	volumes_cmd="ins_vol_ls | jq -r --arg re \"$exclude_names_regex\" '.volumes[] | select(.name | test(\$re; \"i\") | not) | \"\(.volumeID) \(.name)\"'"
    ;;

  -vchtier)
	tier="tier$4"
	test=0
	flagj=1
	if [ $# -lt 4 ]
	then
		usage_vchtier
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments missing! Syntax: bluexport_api.sh $1 VSI_NAME VOLUMES_NAME TIER_TO_CHANGE_TO" 1
	fi
	if [ $# -gt 4 ]
	then
		usage_vchtier
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments! Syntax: bluexport_api.sh $1 VSI_NAME VOLUMES_NAME TIER_TO_CHANGE_TO" 1
	fi
	# Validate STORAGE TIER (vchtier)
	if [[ "$tier" != "tier0" && "$tier" != "tier1" && "$tier" != "tier3" && "$tier" != "tier5k" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Invalid STORAGE TIER '$tier'. Valid values: 0 | 1 | 3 | 5k" 1
	fi
	IFS=' ' read -r -a volchtier_names <<< "$3"
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Common name of volumes to change to tier $tier: ${volchtier_names[*]}" "1"
	vsi=$2
	vsi_id_bluexscrt
	check_locally_VSI_exists
	vol_patterns_json=$(printf '%s\n' "${volchtier_names[@]}" | jq -R . | jq -s .)
	ins_vol_ls | jq -r --argjson patterns "$vol_patterns_json" '.volumes[]? | select([ $patterns[] as $p | (.name | contains($p)) ] | any) | "\(.volumeID) \(.name)"' > "$volumes_file" 2>>"$log_file"
	volumes=$(awk '{print $1}' "$volumes_file" | paste -sd, -)
	volumes_name=$(awk '{print $2}' "$volumes_file" | tr '\n' ' ')
	confirm_or_abort "Change tier of volumes matching \"${volchtier_names[*]}\" on VSI $vsi to $tier: $volumes_name" "$vsi"
	vchtier
    ;;

  -insvchtier)
	tier="tier$3"
	test=0
	flagj=1
	if [ $# -lt 3 ]
	then
		usage_insvchtier
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments missing! Syntax: bluexport_api.sh $1 VSI_NAME TIER_TO_CHANGE_TO" 1
	fi
	if [ $# -gt 3 ]
	then
		usage_insvchtier
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments! Syntax: bluexport_api.sh $1 VSI_NAME TIER_TO_CHANGE_TO" 1
	fi
	# Validate STORAGE TIER (insvchtier)
	if [[ "$tier" != "tier0" && "$tier" != "tier1" && "$tier" != "tier3" && "$tier" != "tier5k" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Invalid STORAGE TIER '$tier'. Valid values: 0 | 1 | 3 | 5k" 1
	fi
	vsi=$2
	vsi_id_bluexscrt
	check_locally_VSI_exists
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Changing ALL volumes of VSI $vsi_cloud_name to tier $tier..." "1"
	ins_vol_ls | jq -r '.volumes[]? | "\(.volumeID) \(.name)"' > "$volumes_file" 2>>"$log_file"
	volumes=$(awk '{print $1}' "$volumes_file" | paste -sd, -)
	volumes_name=$(awk '{print $2}' "$volumes_file" | tr '\n' ' ')
	confirm_or_abort "Change tier of ALL volumes attached to VSI $vsi to $tier: $volumes_name" "$vsi"
	vchtier
    ;;


   -chscrt)
# Change secrets file AND (optionally) change log file path in $conf_file
	# Behavior:
	#   - If a new secrets file is provided as arg2, use it (must exist).
	#   - Otherwise, list bluexscrt*.json files in the current secrets directory and ask the user to select one.
	#   - After selecting the secrets file, ask for the desired log file full path (press Enter to keep current).
	#
	# NOTE: This is the ONLY flag that changes paths inside $conf_file.

	# -------------------------------------------
	# Step 1: Determine new secrets file
	# -------------------------------------------
	new_scrt=""
	if [ $# -ge 2 ]
	then
		# Mode 1: path provided directly: -chscrt /path/bluexscrt_xxx.json
		if [ $# -gt 2 ]
		then
			usage_chscrt
			abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport_api.sh -chscrt bluexscrt_file_name  (use full path, e.g. /home/user/bluexscrt_new.json)" 1
		fi
		new_scrt="$2"
		if [ ! -f "$new_scrt" ]
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` - Secret file $new_scrt does not exist. Aborting..." 1
		fi
	else
		# Mode 2: no args -> list and ask which one to use
		scrt_dir=$(dirname "$bluexscrt")
		echoscreen ""
		echoscreen "### Available secret files in $scrt_dir (pattern: bluexscrt*.json):"
		shopt -s nullglob
		scrt_files=("$scrt_dir"/bluexscrt*.json)
		if [ ${#scrt_files[@]} -eq 0 ]
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` - No secret files found (pattern: bluexscrt*.json)." 1
		fi
		index=1
		for f in "${scrt_files[@]}"
		do
			if [[ "$f" == "$bluexscrt" ]]
			then
				marker="(in use)"
			else
				marker=""
			fi
			printf "[%s] %s %s
" "$index" "$f" "$marker"
			index=$((index + 1))
		done
		echo ""
		printf "### Select the secret file to use [1-%d]: " "${#scrt_files[@]}"
		read choice
		# Validate choice
		if ! [[ "$choice" =~ ^[0-9]+$ ]]
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` - Invalid selection (not a number)." 1
		fi
		if (( choice < 1 || choice > ${#scrt_files[@]} ))
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` - Invalid selection (out of range)." 1
		fi
		new_scrt="${scrt_files[$((choice-1))]}"
	fi

	# -------------------------------------------
	# Step 2: Ask for new log file path
	# -------------------------------------------
	current_log=$(jq -r '.log_file' "$conf_file" 2>/dev/null)
	if [[ -z "$current_log" || "$current_log" == "null" ]]
	then
		current_log="$log_file"
	fi

	echoscreen ""
	echoscreen "### Current log file path: $current_log"
	printf "### Full path for new log file (press Enter to keep current): "
	read new_log

	# Normalize: if empty, keep current
	if [[ -z "$new_log" ]]
	then
		new_log="$current_log"
	else
		# Basic sanity checks
		log_dir=$(dirname "$new_log")
		if [[ ! -d "$log_dir" ]]
		then
			echoscreen "### Directory '$log_dir' does not exist."
			read -p "Do you want to create it now? (Y/N) " mk_ans
			if [[ "$mk_ans" =~ ^[Yy]$ ]]
			then
				mkdir -p "$log_dir" 2>/dev/null
				if [ $? -ne 0 ]
				then
					abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Could not create directory $log_dir. Aborting..." 1
				fi
			else
				abort "`date +%Y-%m-%d_%H:%M:%S` - Aborting by user choice (log directory not created)."
			fi
		fi
		# Create file if missing (so later appends won't fail)
		if [[ ! -f "$new_log" ]]
		then
			echoscreen "### Log file '$new_log' does not exist."
			read -p "Do you want to create it now? (Y/N) " lf_ans
			if [[ "$lf_ans" =~ ^[Yy]$ ]]
			then
				: > "$new_log" 2>/dev/null
				if [ $? -ne 0 ]
				then
					abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Could not create log file $new_log. Aborting..." 1
				fi
				chmod 600 "$new_log" 2>/dev/null
			else
				abort "`date +%Y-%m-%d_%H:%M:%S` - Aborting by user choice (log file not created)."
			fi
		fi
	fi

	# -------------------------------------------
	# Step 3: Update $conf_file atomically
	# -------------------------------------------
	jq --arg new_scrt "$new_scrt" --arg new_log "$new_log" \
		'.bluexscrt = $new_scrt | .log_file = $new_log' \
		"$conf_file" > "$conf_file.tmp" && mv "$conf_file.tmp" "$conf_file"

	abort "`date +%Y-%m-%d_%H:%M:%S` - Config updated: bluexscrt=$new_scrt ; log_file=$new_log"
     ;;

  -viewscrt)
    if [ $# -gt 1 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport_api.sh $1" 1
	fi
	scrt_in_use=$(jq -r '.bluexscrt' "$conf_file")
	abort "`date +%Y-%m-%d_%H:%M:%S` - Secret file in use is $scrt_in_use"
    ;;

  -snapcr)
	# Args: VSI_NAME SNAPSHOT_NAME 0|"DESCRIPTION" 0|[VOLUMES (comma separated names or IDs)]
	if [ $# -lt 5 ]
	then
		usage_snapcr
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments Missing!! Syntax: bluexport_api.sh $1 VSI_NAME SNAPSHOT_NAME 0|\"DESCRIPTION\" 0|\"VOL1,VOL2,...\"" 1
	fi
	if [ $# -gt 5 ]
	then
		usage_snapcr
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments!! Syntax: bluexport_api.sh $1 VSI_NAME SNAPSHOT_NAME 0|\"DESCRIPTION\" 0|\"VOL1,VOL2,...\"" 1
	fi
	vsi="$2"
	vsi_id_bluexscrt
	test=0
	snap_name="$3"
	# Verificar se já existe snapshot com este nome PARA ESTA VSI via API
	snaps_json=$(snap_ls 2>>"$log_file")

	existing_snap_name=$(
		echo "$snaps_json" | jq -r \
			--arg name "$snap_name" \
			--arg pvm "$PVM_ID" \
			'.snapshots // [] | .[] | select(.name == $name and .pvmInstanceID == $pvm) | .name' \
			2>>"$log_file" | head -n1
	)

	if [ -n "$existing_snap_name" ] && [ "$existing_snap_name" != "null" ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Already exists one Snapshot with name $snap_name for VSI $vsi (PVM_ID $PVM_ID), please choose a different name or use flag -snapupd to change the name." 1
	fi
	# Argumento DESCRIPTION: 0 ou frase entre aspas
	description_arg="$4"
	if [ -n "$description_arg" ] && [ "$description_arg" -eq "$description_arg" ] 2>/dev/null
	then
		if [ "$description_arg" -eq 0 ]
		then
			snap_description=""
		else
			abort "$(date +%Y-%m-%d_%H:%M:%S) - Argument DESCRIPTION must be 0 or a phrase inside quotes!! Syntax: bluexport_api.sh $1 VSI_NAME SNAPSHOT_NAME 0|[\"DESCRIPTION\"] 0|\"VOL1,VOL2,...\"" 1
		fi
	else
		snap_description="$description_arg"
	fi
	# Argumento VOLUMES: 0 ou lista comma separated de nomes/IDs
	volumes_arg="$5"
	if [ -n "$volumes_arg" ] && [ "$volumes_arg" -eq "$volumes_arg" ] 2>/dev/null
	then
		if [ "$volumes_arg" -eq 0 ]
		then
			volumes_to_snap=""
			volumes_to_echo="ALL"
		else
			abort "$(date +%Y-%m-%d_%H:%M:%S) - Argument VOLUMES must be 0 or comma separated volume names or IDs!! Syntax: bluexport_api.sh $1 VSI_NAME SNAPSHOT_NAME 0|[\"DESCRIPTION\"] 0|\"VOL1,VOL2,...\"" 1
		fi
	else
		volumes_to_snap="$volumes_arg"
		volumes_to_echo="$volumes_arg"
	fi
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - === Starting Snapshot $snap_name of VSI $vsi with volumes: $volumes_to_echo !" "1"
	check_locally_VSI_exists
	do_snap_create
	abort "$(date +%Y-%m-%d_%H:%M:%S) - === Successfully finished Snapshot $snap_name of VSI $vsi with volumes: $volumes_to_echo !"
    ;;

  -snapupd)
	# Sintaxe: bluexport_api.sh -snapupd SNAPSHOT_NAME 0|[NEW_SNAPSHOT_NAME] 0|["DESCRIPTION"]
	if [ $# -lt 4 ]
	then
		usage_snapupd
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments Missing!! Syntax: bluexport_api.sh $1 SNAPSHOT_NAME 0|[NEW_SNAPSHOT_NAME] 0|[\"DESCRIPTION\"]" 1
	fi
	if [ $# -gt 4 ]
	then
	usage_snapupd
	abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments!! Syntax: bluexport_api.sh $1 SNAPSHOT_NAME 0|[NEW_SNAPSHOT_NAME] 0|[\"DESCRIPTION\"]" 1
	fi
	test=0
	flagj=1
	snap_name="$2"
	new_name_arg="$3"
	description_arg="$4"
	snap_new_name=""
	snap_new_description=""
	new_name_echo=""
	new_description_echo=""
	keep_current_desc=0
	# Têm de vir pelo menos um campo para alterar
	if [ "$new_name_arg" = "0" ] && [ "$description_arg" = "0" ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - You must pass at least one flag, DESCRIPTION or NEW_SNAPSHOT_NAME!..." 1
	fi
	#### Tratar NEW_SNAPSHOT_NAME
	if [ -n "$new_name_arg" ]
	then
		# Se for numérico
		if [ "$new_name_arg" -eq "$new_name_arg" ] 2>/dev/null
		then
			if [ "$new_name_arg" -eq 0 ]
			then
				# 0 = manter o nome atual
				new_name_echo=""
			else
				abort "$(date +%Y-%m-%d_%H:%M:%S) - Argument NEW_SNAPSHOT_NAME must be 0 or a name!! Syntax: bluexport_api.sh $1 SNAPSHOT_NAME 0|[NEW_SNAPSHOT_NAME] 0|[\"DESCRIPTION\"]" 1
			fi
		else
			# Nome novo e diferente do atual
			if [ "$new_name_arg" = "$snap_name" ]
			then
				new_name_echo=""
			else
				snap_new_name="$new_name_arg"
				new_name_echo="with new Name $snap_new_name"
			fi
		fi
	fi
	#### Tratar DESCRIPTION
	if [ -n "$description_arg" ]
	then
		# Se for numérico
		if [ "$description_arg" -eq "$description_arg" ] 2>/dev/null
		then
			if [ "$description_arg" -eq 0 ]
			then
				# 0 = manter descrição atual (vamos buscar ao snapshot)
				keep_current_desc=1
			else
				abort "$(date +%Y-%m-%d_%H:%M:%S) - Argument DESCRIPTION must be 0 or a phrase inside quotes!! Syntax: bluexport_api.sh $1 SNAPSHOT_NAME 0|[NEW_SNAPSHOT_NAME] 0|[\"DESCRIPTION\"]" 1
			fi
		else
			# Nova descrição
			snap_new_description="$description_arg"
			new_description_echo="with new Description \"$description_arg\""
		fi
	fi
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - === Starting Snapshot $snap_name Update !" "1"
	#### Procurar o snapshot em TODOS os workspaces (como no -snapdel)
	IFS=':' read -r -a wsnames_array <<< "$wsnames"
	read -r -a allws_array <<< "$allws"
	# Mapear ID -> nome do workspace
	declare -A wsmap
	for i in "${!allws_array[@]}"
	do
		wsmap[${allws_array[i]}]="${wsnames_array[i]}"
	done
	SNAP_ID=""
	current_desc=""
	found_workspace_name=""
	for ws in "${allws_array[@]}"
	do
		CRN=$(jq -r --arg k "$ws" '.workspaces[$k].crn' "$bluexscrt")
		CLOUD_INSTANCE_ID=$(jq -r --arg k "$ws" '.workspaces[$k].id' "$bluexscrt")
		full_ws_name="${wsmap[$ws]}"
		# Descobrir região para montar o base_url correto
		region_api=$(jq -r --arg k "$ws" '.workspaces[$k].crn | capture("power-iaas:(?<region>[^:]+)") | .region | gsub("-"; "_")' "$bluexscrt")
		base_url_var="base_${region_api}"
		base_url="${!base_url_var}"
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Checking snapshots at workspace $full_ws_name..." "1"
		snaps_json=$(snap_ls 2>>"$log_file")
		if [ $? -ne 0 ] || [[ -z "$snaps_json" ]]
		then
			echo "$snaps_json" >>"$log_file"
			continue
		fi
		snap_id=$(echo "$snaps_json" | jq -r --arg name "$snap_name" '.snapshots[]? | select(.name == $name) | .snapshotID' 2>>"$log_file" | head -n1)
		if [[ -n "$snap_id" && "$snap_id" != "null" ]]
		then
			SNAP_ID="$snap_id"
			found_workspace_name="$full_ws_name"
			# Buscar a descrição atual para poder preservá-la se necessário
			current_desc=$(echo "$snaps_json" | jq -r --arg name "$snap_name" '.snapshots[]? | select(.name == $name) | .description // ""' 2>>"$log_file" | head -n1)
			break
		fi
	done
	if [[ -z "$SNAP_ID" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Snapshot with name $snap_name does not exist in any configured workspace. Use -snapcr to create one." 1
	fi
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Found snapshot $snap_name in workspace $found_workspace_name with ID $SNAP_ID" "1"
	# Se o utilizador pediu para manter a descrição (0), usamos a atual
	if [ "$keep_current_desc" -eq 1 ]
	then
		snap_new_description="$current_desc"
		if [ -n "$snap_new_description" ]
		then
			new_description_echo="(keeping existing Description \"$snap_new_description\")"
		else
			new_description_echo="(keeping existing empty Description)"
		fi
	fi
	# Se no fim não houver nada para alterar, não vale a pena chamar a API
	if [ -z "$snap_new_name" ] && [ "$keep_current_desc" -eq 1 ] && [ -z "$current_desc" ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Nothing to update for snapshot $snap_name."
	fi
	do_snap_update
	abort "$(date +%Y-%m-%d_%H:%M:%S) - === Successfully finished Snapshot $snap_name Update $new_name_echo $new_description_echo !"
    ;;

  -snapdel)
	# Validate arguments
	if [ $# -lt 2 ]
	then
		usage_snapdel
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments Missing!! Syntax: bluexport_api.sh $1 SNAPSHOT_NAME" 1
	fi
	if [ $# -gt 2 ]
	then
		usage_snapdel
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments!! Syntax: bluexport_api.sh $1 SNAPSHOT_NAME" 1
	fi
	test=0
	flagj=1
	snap_name="$2"
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - === Searching for snapshot name $snap_name" "1"
	IFS=':' read -r -a wsnames_array <<< "$wsnames"
	# Convert allws (space separated) → array
        read -r -a allws_array <<< "$allws"
        # Create mapping: workspace shortname → full name
        declare -A wsmap
        for i in "${!allws_array[@]}"
        do
                wsmap[${allws_array[i]}]="${wsnames_array[i]}"
        done
        # Loop all workspaces
        for ws in "${allws_array[@]}"
        do
		# Get workspace CRN and ID from JSON
                CRN=$(jq -r --arg k "$ws" '.workspaces[$k].crn' "$bluexscrt")
                CLOUD_INSTANCE_ID=$(jq -r --arg k "$ws" '.workspaces[$k].id' "$bluexscrt")
                # Workspace human friendly name
                full_ws_name="${wsmap[$ws]}"
                echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - === Listing snapshots at workspace $full_ws_name" "1"
                region_api=$(jq -r --arg k "$ws" '.workspaces[$k].crn | capture("power-iaas:(?<region>[^:]+)") | .region | gsub("-"; "_")' "$bluexscrt")
                base_url_var="base_${region_api}"
                base_url="${!base_url_var}"
		snaps_json=$(snap_ls 2>>"$log_file")
                # Fix (1.18.1): ask whether THIS snapshot is here, not whether the
                # workspace has ANY. The old guard tested '.snapshots | length > 0', so a
                # workspace holding unrelated snapshots fell through to do_snap_delete, which
                # looks the name up in that workspace's list and aborts when it is not there -
                # ending the sweep before the workspace that actually holds the snapshot was
                # ever reached. It worked only when the target happened to live in the first
                # workspace that had any snapshots at all.
                if ! echo "$snaps_json" | jq -e --arg n "$snap_name" \
                        '[.snapshots[]? | select(.name == $n)] | length > 0' >/dev/null 2>&1
		then
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Snapshot with name $snap_name not found in Workspace $full_ws_name, moving on to next Workspace!" "1"
			continue
		fi
		do_snap_delete
	done
    ;;

  -snapres)
	# Syntax: bluexport_api.sh -snapres VSI_NAME SNAPSHOT_NAME
	if [ $# -lt 3 ]
	then
		usage_snapres
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments Missing!! Syntax: bluexport_api.sh $1 VSI_NAME SNAPSHOT_NAME" 1
	fi
	if [ $# -gt 3 ]
	then
		usage_snapres
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments!! Syntax: bluexport_api.sh $1 VSI_NAME SNAPSHOT_NAME" 1
	fi
	test=0
	flagj=1
	vsi=$2
	snap_name="$3"
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - === Starting Snapshot Restore for VSI $vsi and Snapshot $snap_name ===" "1"
	# Buscar contexto do VSI (workspace, CRN, CLOUD_INSTANCE_ID, PVM_ID, base_url)
	vsi_id_bluexscrt
	check_locally_VSI_exists
	# Estamos agora na workspace correta, com PVM_ID e base_url ajustados
	do_snap_restore
	;;

  -snaplsall)
	# Too many arguments?
	if [ $# -gt 1 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments!! Syntax: bluexport_api.sh $1" 1
	fi
	test=0
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - === Starting listing all snapshots in all workspaces!" "1"
	read -r -a allws_array <<< "$allws"
	# Loop all workspaces
	for ws in "${allws_array[@]}"
	do
		# Get workspace CRN and ID from JSON
		CRN=$(jq -r --arg k "$ws" '.workspaces[$k].crn' "$bluexscrt")
		CLOUD_INSTANCE_ID=$(jq -r --arg k "$ws" '.workspaces[$k].id' "$bluexscrt")
		# Workspace human friendly name
                full_ws_name=$(jq -r --arg k "$ws" '.workspaces[$k].name // $k' "$bluexscrt")
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - === Listing snapshots at workspace $full_ws_name" "1"
		region_api=$(jq -r --arg k "$ws" '.workspaces[$k].crn | capture("power-iaas:(?<region>[^:]+)") | .region | gsub("-"; "_")' "$bluexscrt")
		base_url_var="base_${region_api}"
		base_url="${!base_url_var}"
		snaps_json=$(snap_ls 2>>"$log_file")
		# Check if there are snapshots
		if ! echo "$snaps_json" | jq -e '.snapshots | length > 0' >/dev/null 2>&1
		then
			msg="----------------------- No Snapshots Found -----------------------"
			echoscreen "$msg" "1"
		else
			# Transform snapshots into TSV to process in bash
			echo "$snaps_json" | jq -r '.snapshots // [] |.[] |
			[
			.name,
			.description,
			.creationDate,
			.lastUpdateDate,
			.action,
			.snapshotID,
			.percentComplete,
			.status,
			.statusDetail,
			.pvmInstanceID,
			(.volumeSnapshots | tostring)
			] | @tsv' 2>>"$log_file" | \
			while IFS=$'\t' read -r s_name s_description s_cdate s_udate s_action s_id s_pct s_status s_sdetail s_pvmid s_vols
			do
				# Resolve Instance Name from config JSON for this workspace + pvmInstanceID
				instname=$(jq -r --arg ws "$ws" --arg id "$s_pvmid" '
				(.systems // [])
				| map(select(.workspace == $ws and .pvmInstanceID == $id))
				| if length > 0 then .[0].name else "N/A" end
				' "$bluexscrt")
				{
					echo "----------------------- Snapshot Found -----------------------"
					echo "Name: $s_name"
					echo "Description: $s_description" 
					echo "Creation Date: $s_cdate"
					echo "Last Update Date: $s_udate"
					echo "Action: $s_action"
					echo "Snapshot ID: $s_id"
					echo "Percentage Complete: $s_pct"
					echo "Status: $s_status"
					echo "Status Detail: $s_sdetail"
					echo "Instance ID: $s_pvmid"
					echo "Instance Name: $instname"
					echo "Volumes: $s_vols"
					echo "------------------------------------------------------------"
				} | tee -a "$log_file"
			done
		fi
		echoscreen "" "1"
	done
	abort "$(date +%Y-%m-%d_%H:%M:%S) - === Finished listing all snapshots in all workspaces"
    ;;

  -vsidetails)
	# Too many arguments?
	if [ $# -gt 1 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments!! Syntax: bluexport_api.sh $1" 1
	fi
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - === Starting listing compute and licences for all LPARs in all workspaces!" "1"
	read -r -a allws_array <<< "$allws"
	# Loop all workspaces
	for ws in "${allws_array[@]}"
	do
		CRN=$(jq -r --arg k "$ws" '.workspaces[$k].crn' "$bluexscrt")
		CLOUD_INSTANCE_ID=$(jq -r --arg k "$ws" '.workspaces[$k].id' "$bluexscrt")
		full_ws_name=$(jq -r --arg k "$ws" '.workspaces[$k].name // $k' "$bluexscrt")
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - === LPAR details at workspace $full_ws_name" "1"
		region_api=$(jq -r --arg k "$ws" '.workspaces[$k].crn | capture("power-iaas:(?<region>[^:]+)") | .region | gsub("-"; "_")' "$bluexscrt")
		base_url_var="base_${region_api}"
		base_url="${!base_url_var}"
		ins_json=$(ins_ls 2>>"$log_file")
		if ! echo "$ins_json" | jq -e '.pvmInstances | length > 0' >/dev/null 2>&1
		then
			echoscreen "----------------------- No LPARs Found -----------------------" "1"
		else
			# One TSV line per LPAR. The licence flags are rendered as a comma-separated list of
			# the ones that are ON, rather than four true/false columns: a consultant reads
			# "CSS, PHA" faster than four booleans, and an LPAR with none prints "-" rather than
			# four "false"s that look like an error.
			echo "$ins_json" | jq -r '.pvmInstances // [] | .[] |
			[
			.serverName,
			.status,
			(.memory | tostring),
			(.processors | tostring),
			.procType,
			((.virtualCores.assigned // "-") | tostring),
			(.sysType // "-"),
			(.osType // "-"),
			([ (.softwareLicenses // {}) | to_entries[]
			   | select(.value == true) | .key ] | join(", ") | if . == "" then "-" else . end),
			((.softwareLicenses.ibmiRDSUsers // "-") | tostring),
			.pvmInstanceID
			] | @tsv' 2>>"$log_file" | \
			while IFS=$'\t' read -r d_name d_status d_mem d_proc d_ptype d_vcores d_systype d_ostype d_lic d_rdsusers d_id
			do
				{
					echo "----------------------- LPAR Found -----------------------"
					echo "Name: $d_name"
					echo "Status: $d_status"
					echo "Memory (GB): $d_mem"
					echo "Processors: $d_proc ($d_ptype)"
					echo "Virtual Cores: $d_vcores"
					echo "System Type: $d_systype"
					echo "OS Type: $d_ostype"
					echo "Licences: $d_lic"
					echo "RDS Users: $d_rdsusers"
					echo "PVM Instance ID: $d_id"
					echo "----------------------------------------------------------"
				} | tee -a "$log_file"
			done
		fi
	done
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - === Finished listing compute and licences!" "1"
	exit 0
	;;

  -imglsall)
	if [ $# -gt 1 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments!! Syntax: bluexport_api.sh $1" 1
	fi
	test=0
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - === Starting Listing all Captured Images in all Workspaces !" "1"
	read -r -a allws_array <<< "$allws"
	for ws in "${allws_array[@]}"
	do
		# Get CRN and Workspace ID from JSON
		CRN=$(jq -r --arg ws "$ws" '.workspaces[$ws].crn' "$bluexscrt")
		CLOUD_INSTANCE_ID=$(jq -r --arg ws "$ws" '.workspaces[$ws].id'  "$bluexscrt")
		region_api=$(jq -r --arg k "$ws" '.workspaces[$k].crn | capture("power-iaas:(?<region>[^:]+)") | .region | gsub("-"; "_")' "$bluexscrt")
		base_url_var="base_${region_api}"
		base_url="${!base_url_var}"
                full_ws_name=$(jq -r --arg k "$ws" '.workspaces[$k].name // $k' "$bluexscrt")
		if [[ -z "$CRN" || "$CRN" == "null" || -z "$CLOUD_INSTANCE_ID" || "$CLOUD_INSTANCE_ID" == "null" ]]
		then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Workspace $ws ($full_ws_name) missing CRN or ID in $bluexscrt, skipping..." "1"
			continue
		fi
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - === Listing Captured Images at Workspace $full_ws_name :" "1"
		images_json=$(img_ls 2>>"$log_file")
		# Check if there are images
		if ! echo "$images_json" | jq -e '.images | length > 0' >/dev/null 2>&1
		then
			msg="----------------------- No Images Found -----------------------"
			echo "$msg" | tee -a "$log_file"
		else
			# If images exist → pretty formatted output
			echo "$images_json" | jq -r '
			.images[] |
			"----------------------- Image Found -----------------------\n" +
			"Name: \(.name)\n" +
			"Creation Date: \(.creationDate)\n" +
			"Last Update Date: \(.lastUpdateDate)\n" +
			"Description: \(.description)\n" +
			"Image ID: \(.imageID)\n" +
			"Operating System: \(.specifications.operatingSystem)\n" +
			"State: \(.state)\n" +
			"Storage Pool: \(.storagePool)\n" +
			"Storage Type: \(.storageType)\n" +
			"------------------------------------------------------------"
			' 2>>"$log_file" | tee -a "$log_file"
		fi
		echoscreen "" "1"
	done
	abort "$(date +%Y-%m-%d_%H:%M:%S) - === Finished Listing all Captured Images in all Workpsaces"
    ;;

   -imgdel)
	if [ $# -ne 2 ]
	then
		usage_imgdel
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many or too few arguments!! Syntax: bluexport_api.sh -imgdel IMG_NAME" 1
	fi
	img_name="$2"
	do_img_delete "$img_name"
    ;;

   -imgimport)
	if [[ $# -lt 8 || $# -gt 9 ]]
	then
		usage_imgimport
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many or too few arguments!! Syntax: bluexport_api.sh -imgimport IMGNAME BUCKET BUCKET_REGION WORKSPACE_TO_IMPORT IMGNAME_WS STORAGE_TYPE CURRACCOUNT|OTHERACCOUNT [HMAC_JSON_FILE]" 1
	fi
	img_import "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9"
    ;;

   -imgexport)
	if [[ $# -lt 5 || $# -gt 6 ]]
	then
		usage_imgexport
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many or too few arguments!! Syntax: bluexport_api.sh -imgexport IMGNAME BUCKET BUCKET_REGION CURRACCOUNT|OTHERACCOUNT [HMAC_JSON_FILE]" 1
	fi
	img_export "$2" "$3" "$4" "$5" "$6"
    ;;

   -ji)
	if [[ $# -ne 2 ]]
	then
		usage_ji
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many or too few arguments!! Syntax: bluexport_api.sh -ji WORKSPACE" 1
	fi
	img_import_monitor "$2"
    ;;

   -je)
	if [[ $# -ne 2 ]]
	then
		usage_je
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many or too few arguments!! Syntax: bluexport_api.sh -je IMAGE_NAME" 1
	fi
	img_export_monitor "$2"
    ;;

  # (1.21.0) Jobs: account-wide job listing/detail/cancel, across every configured workspace.
  -jobslsall)
	if [ $# -gt 1 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments!! Syntax: bluexport_api.sh $1" 1
	fi
	test=0
	do_jobs_lsall
    ;;

  -jobsls)
	if [ $# -ne 2 ]
	then
		usage_jobsls
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many or too few arguments!! Syntax: bluexport_api.sh -jobsls WORKSPACE" 1
	fi
	test=0
	do_jobs_ls "$2"
    ;;

  -jobget)
	if [ $# -ne 2 ]
	then
		usage_jobget
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many or too few arguments!! Syntax: bluexport_api.sh -jobget JOB_ID" 1
	fi
	test=0
	do_job_get "$2"
    ;;

  -jobcancel)
	if [ $# -ne 2 ]
	then
		usage_jobcancel
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many or too few arguments!! Syntax: bluexport_api.sh -jobcancel JOB_ID" 1
	fi
	test=0
	do_job_cancel "$2"
    ;;

  -vclonelsall)
	# Too many arguments?
	if [ $# -gt 1 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments!! Syntax: bluexport_api.sh $1" 1
	fi
	test=0
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - === Starting Listing all Volume Clones in all Workspaces !" "1"
	# Convert 'wsnames' (colon-separated) to array
	IFS=':' read -r -a wsnames_array <<< "$wsnames"
	# Convert 'allws' (space-separated) to array
	read -r -a allws_array <<< "$allws"
	# Map workspace short name -> full name
	declare -A wsmap
	for i in "${!allws_array[@]}"
	do
		 wsmap[${allws_array[i]}]="${wsnames_array[i]}"
	done
	# Loop all workspaces
	for ws in "${allws_array[@]}"
	do
		# Get workspace CRN and ID from JSON
		CRN=$(jq -r --arg k "$ws" '.workspaces[$k].crn' "$bluexscrt")
		CLOUD_INSTANCE_ID=$(jq -r --arg k "$ws" '.workspaces[$k].id' "$bluexscrt")
		full_ws_name=$(jq -r --arg k "$ws" '.workspaces[$k].name' "$bluexscrt")
		if [[ -z "$CRN" || "$CRN" == "null" || -z "$CLOUD_INSTANCE_ID" || "$CLOUD_INSTANCE_ID" == "null" ]]
		then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Workspace $ws ($full_ws_name) missing CRN or ID in $bluexscrt, skipping..." "1"
			continue
		fi
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - === Listing Volume Clones at Workspace $full_ws_name :" "1"
		region_api=$(jq -r --arg k "$ws" '.workspaces[$k].crn | capture("power-iaas:(?<region>[^:]+)") | .region | gsub("-"; "_")' "$bluexscrt")
		base_url_var="base_${region_api}"
		base_url="${!base_url_var}"
		clones_json=$(vol_cl_ls 2>>"$log_file")
		# Check if there are volume clones in this workspace
		if ! echo "$clones_json" | jq -e '.volumesClone | length > 0' >/dev/null 2>&1
		then
			msg="----------------------- No Volumes Clones Found -----------------------"
			echo "$msg" | tee -a "$log_file"
		else
			echo "$clones_json" | jq -r '
			.volumesClone[] |
			"----------------------- Volumes Clone Found -----------------------\n"
			+ "Clone ID: \(.volumesCloneID)\n"
			+ "Name: \(.name)\n"
			+ "Status: \(.status)\n"
			+ "Percent Complete: \(.percentComplete)\n"
			+ "Creation Date: \(.creationDate)\n"
			+ "Volumes Clone IDs \(.volumesCloneID)\n"
			+ "------------------------------------------------------------"
			' 2>>"$log_file" | tee -a "$log_file"
		fi
		echoscreen "" "1"
	done
	abort "$(date +%Y-%m-%d_%H:%M:%S) - === Finished Listing all Volume Clones in all Workpsaces"
    ;;

  -vclone)
	# (1.19.0) VOLUMES was documented here as IDs; it is names (ALL|name1,name2,...),
	# resolved against ins_vol_ls below - see usage_vclone.
	# Args: REQUEST_CLONE_NAME VOLUME_BASE_NAME LPAR_NAME Replication(True|False) Rollback(True|False) TARGET_TIER volumes(ALL|name1,name2,...)
	if [ $# -lt 8 ]
	then
		usage_vclone
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments Missing!! Syntax: bluexport_api.sh $1 REQUEST_CLONE_NAME VOLUME_BASE_NAME LPAR_NAME True|False(replication-enabled) True|False(rollback-prepare) tier0|tier1|tier3|tier5k ALL|\"VOL1,VOL2,...\"" 1
	fi
	if [ $# -gt 8 ]
	then
		usage_vclone
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments!! Syntax: bluexport_api.sh $1 REQUEST_CLONE_NAME VOLUME_BASE_NAME LPAR_NAME True|False(replication-enabled) True|False(rollback-prepare) tier0|tier1|tier3|tier5k ALL|\"VOL1,VOL2,...\"" 1
	fi
	test=0
	vclone_name="$2"
	base_name="$3"
	vsi="$4"
	vsi_id_bluexscrt
	check_locally_VSI_exists
	replication="${5,,}"
	rollback="${6,,}"
	target_tier="$7"
	volumes_to_clone_arg="$8"
	# Validar replication / rollback
	if [[ "$replication" != "true" && "$replication" != "false" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Replication value must be True or False...!" 1
	fi
	if [[ "$rollback" != "true" && "$rollback" != "false" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Rollback value must be True or False...!" 1
	fi
	# Validar tier
	if [[ "$target_tier" != "tier0" && "$target_tier" != "tier1" && "$target_tier" != "tier3" && "$target_tier" != "tier5k" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Target Tier must be tier0 or tier1 or tier3 or tier5k...!" 1
	fi
	# Garantir que não existe já um Volume Clone com este nome (via API)
	existing_vclone_json=$(vol_cl_ls 2>>"$log_file")
	if echo "$existing_vclone_json" | jq -e --arg name "$vclone_name" '.volumesClone[]? | select(.name == $name)' >/dev/null 2>&1
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Volume Clone with name $vclone_name already exists, please choose a different name!" 1
	fi
	# Resolver volumes a clonar
	if [[ "$volumes_to_clone_arg" == "ALL" ]]
	then
		# ALL → ir buscar os volumes anexados à VSI pelo API
		volumes_to_clone=$(ins_vol_ls 2>>"$log_file" | jq -r '.volumes[]?.volumeID' | paste -sd, -)
		if [[ -z "$volumes_to_clone" ]]
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - No volumes found attached to VSI $vsi to clone." 1
		fi
	else
		# (1.19.0) The tokens are volume NAMES (see usage_vclone), not volumeIDs, but used
		# to be sent to the API verbatim as volumeIDs. Resolve each comma-separated token
		# against the volumes attached to this VSI: an exact name match uses that volume's
		# volumeID, an exact volumeID match is used as-is, and a token that matches
		# neither (or a name shared by more than one volume) aborts naming it.
		vclone_vol_json=$(ins_vol_ls 2>>"$log_file")
		vclone_resolved_ids=""
		IFS=',' read -r -a vclone_req_array <<< "$volumes_to_clone_arg"
		for vclone_tok in "${vclone_req_array[@]}"
		do
			vclone_tok_trimmed=$(echo "$vclone_tok" | xargs)
			[ -z "$vclone_tok_trimmed" ] && continue
			vclone_name_matches=$(echo "$vclone_vol_json" | jq -r --arg n "$vclone_tok_trimmed" '[.volumes[]? | select(.name == $n)] | length')
			if [ "$vclone_name_matches" -eq 1 ]
			then
				vclone_resolved_id=$(echo "$vclone_vol_json" | jq -r --arg n "$vclone_tok_trimmed" '.volumes[]? | select(.name == $n) | .volumeID' | head -n1)
			elif [ "$vclone_name_matches" -gt 1 ]
			then
				abort "$(date +%Y-%m-%d_%H:%M:%S) - Volume name '$vclone_tok_trimmed' matches more than one volume attached to VSI $vsi. Use its volumeID instead." 1
			else
				vclone_id_matches=$(echo "$vclone_vol_json" | jq -r --arg id "$vclone_tok_trimmed" '[.volumes[]? | select(.volumeID == $id)] | length')
				if [ "$vclone_id_matches" -ge 1 ]
				then
					vclone_resolved_id="$vclone_tok_trimmed"
				else
					abort "$(date +%Y-%m-%d_%H:%M:%S) - '$vclone_tok_trimmed' is neither a volume name nor a volumeID attached to VSI $vsi." 1
				fi
			fi
			vclone_resolved_ids="${vclone_resolved_ids:+$vclone_resolved_ids,}$vclone_resolved_id"
		done
		volumes_to_clone="$vclone_resolved_ids"
	fi
	# Validar que temos pelo menos 2 volumes
	IFS=',' read -r -a vclone_array <<< "$volumes_to_clone"
	if [ "${#vclone_array[@]}" -lt 2 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Volume Clone Request must contain at least 2 volumes. You provided: ${#vclone_array[@]} ($volumes_to_clone)" 1
	fi
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - === Starting the three processes of Volume Clone $vclone_name" "1"
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - This is the list of volumes that will be cloned: $volumes_to_clone" "1"
	# Guardar a lista para as funções seguintes
	volumes_to_clone="$volumes_to_clone"
	confirm_or_abort "Create Volume Clone Request '$vclone_name' cloning volumes: $volumes_to_clone (target tier $target_tier)" "$vclone_name"
	do_volume_clone
	do_volume_clone_start
	do_volume_clone_execute
	abort "$(date +%Y-%m-%d_%H:%M:%S) - === Successfully finished -  Volume Clone $vclone_name !"
    ;;

  -vclonedel)
	# Syntax: bluexport_api.sh -vclonedel REQUEST_CLONE_NAME 0|delete_volumes
	if [ $# -lt 2 ]
	then
		usage_vclonedel
		abort "`date +%Y-%m-%d_%H:%M:%S` - Arguments Missing!! Syntax: bluexport_api.sh $1 REQUEST_CLONE_NAME 0|delete_volumes" 1
	fi
	if [ $# -gt 3 ]
	then
	usage_vclonedel
	abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport_api.sh $1 REQUEST_CLONE_NAME 0|delete_volumes" 1
	fi
	test=0
	found=0
	vclone_name=$2
	delete_mode="${3:-0}"
	# Validar o modo
	if [[ "$delete_mode" != "0" && "$delete_mode" != "delete_volumes" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Invalid parameter for delete_volumes. Use 0 or delete_volumes. Syntax: bluexport_api.sh $1 REQUEST_CLONE_NAME 0|delete_volumes" 1
	fi
	if [[ "$delete_mode" == "delete_volumes" ]]
	then
		confirm_or_abort "Delete Volume Clone Request '$vclone_name' AND delete the volumes it produced" "$vclone_name"
	else
		confirm_or_abort "Delete Volume Clone Request '$vclone_name' (the cloned volumes themselves are kept)" "$vclone_name"
	fi
	# Converter 'wsnames' (colon-separated) para array
	IFS=':' read -r -a wsnames_array <<< "$wsnames"
	# Converter 'allws' (space-separated) para array
	read -r -a allws_array <<< "$allws"
	# Map workspace short name -> full name
	declare -A wsmap
	for i in "${!allws_array[@]}"
	do
		wsmap[${allws_array[i]}]="${wsnames_array[i]}"
	done
	# Loop por todas as workspaces
	for ws in "${allws_array[@]}"
	do
		# Buscar CRN e ID da workspace ao JSON
		CRN=$(jq -r --arg k "$ws" '.workspaces[$k].crn' "$bluexscrt")
		CLOUD_INSTANCE_ID=$(jq -r --arg k "$ws" '.workspaces[$k].id' "$bluexscrt")
		# Nome “humano” da workspace
		full_ws_name="${wsmap[$ws]}"
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - === Listing volumes clones at workspace $full_ws_name " "1"
		# Resolver região e base_url
		region_api=$(jq -r --arg k "$ws" '.workspaces[$k].crn | capture("power-iaas:(?<region>[^:]+)") | .region | gsub("-"; "_")' "$bluexscrt")
		base_url_var="base_${region_api}"
		base_url="${!base_url_var}"
		vclone_name_exists=$(vol_cl_ls | jq -r --arg vclname "$vclone_name" '.volumesClone[]? | select(.name == $vclname) | .name')
		if [[ -z "$vclone_name_exists" ]]
		then
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Volume Clone with name $vclone_name doesn't exist in Workspace $full_ws_name, moving on to next Workspace!" "1"
			continue
		fi
		found=1
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - === Found Volume Clone with name $vclone_name in workspace $full_ws_name" "1"
		# Ir buscar o ID do volume clone
		VOL_CLONE_ID=$(vol_cl_ls | jq -r --arg vclname "$vclone_name" '.volumesClone[]? | select(.name == $vclname) | .volumesCloneID')
		if [[ -z "$VOL_CLONE_ID" || "$VOL_CLONE_ID" == "null" ]]
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Could not retrieve volumesCloneID for $vclone_name in workspace $full_ws_name." 1
		fi
		# (1.22.0) IBM Cloud refuses to delete a volumes-clone request unless its own
		# status is already completed/failed/cancelled - a 400 with no cancel offered.
		# Read the status ourselves first, every time (not only under delete_volumes,
		# which used to be the only path that ever called vol_cl_get), and branch:
		#   - terminal (completed/failed/cancelled): fall through, delete as before.
		#   - cancellable (available/running/preparing - the same "available" status
		#     do_volume_clone_start already waits for): ask, cancel only on an explicit
		#     yes, then wait (bounded) for a terminal status before deleting.
		#   - anything else (creating/executing/cancelling/unrecognized): nothing safe
		#     to cancel out of yet; abort naming the status.
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Checking status of Volume Clone Request $vclone_name before deleting..." "1"
		vcl_status_json=$(vol_cl_get 2>>"$log_file")
		if [[ -z "$vcl_status_json" ]]
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Could not read the status of Volume Clone Request $vclone_name before deleting." 1
		fi
		vclone_status=$(echo "$vcl_status_json" | jq -r '(.status // .state // .status.state // empty) | ascii_downcase' 2>/dev/null)
		case "$vclone_status" in
			completed|failed|cancelled)
				echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Volume Clone Request $vclone_name is in status '$vclone_status' (terminal) - proceeding." "1"
				;;
			available|running|preparing)
				confirm_or_abort "Volume Clone Request '$vclone_name' is in status '$vclone_status' - IBM Cloud will refuse to delete it until it is completed, failed or cancelled. Cancel it now, wait for it to finish cancelling, and then delete it" "$vclone_name"
				echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Cancelling Volume Clone Request $vclone_name (status '$vclone_status')..." "1"
				FORCE=true
				vcl_cancel_raw=$(vol_cl_ca 2>>"$log_file")
				printf '%s\n' "$vcl_cancel_raw" >> "$log_file"
				if printf '%s' "$vcl_cancel_raw" | jq -e '(.code? != null) or (.error? != null)' >/dev/null 2>&1
				then
					vcl_cancel_err=$(printf '%s' "$vcl_cancel_raw" | jq -r '.description // .message // .error // "Unknown error"' 2>/dev/null)
					abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Could not cancel Volume Clone Request $vclone_name: $vcl_cancel_err" 1
				fi
				echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Cancel requested for Volume Clone Request $vclone_name. Waiting for it to reach a terminal status..." "1"
				# Bounded: BLUEXPORT_JOB_MAX_SECS, the same cap vclone_time_left reads
				# elsewhere (default 24h). An unbounded poll here would be the same
				# defect being fixed, just moved one call later.
				vcl_cancel_started=$(date +%s)
				while :
				do
					sleep 5
					if [ $(( $(date +%s) - vcl_cancel_started )) -ge "${BLUEXPORT_JOB_MAX_SECS:-86400}" ]
					then
						abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Volume Clone Request $vclone_name was cancelled but not yet confirmed terminal after ${BLUEXPORT_JOB_MAX_SECS:-86400} seconds. Check its status and delete it manually (limit BLUEXPORT_JOB_MAX_SECS)." 1
					fi
					vcl_status_json=$(vol_cl_get 2>>"$log_file")
					if [[ -z "$vcl_status_json" ]]
					then
						abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Error reading status of Volume Clone Request $vclone_name while waiting for it to cancel." 1
					fi
					vclone_status=$(echo "$vcl_status_json" | jq -r '(.status // .state // .status.state // empty) | ascii_downcase' 2>/dev/null)
					case "$vclone_status" in
						completed|failed|cancelled)
							echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Volume Clone Request $vclone_name reached status '$vclone_status'. Proceeding with delete." "1"
							break
							;;
						*)
							echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Volume Clone Request $vclone_name is still '$vclone_status' after cancel. Waiting..." "1"
							;;
					esac
				done
				;;
			*)
				abort "`date +%Y-%m-%d_%H:%M:%S` - Volume Clone Request $vclone_name is in status '$vclone_status', which is neither terminal nor safely cancellable yet. Wait for it to reach completed, failed or cancelled, then retry -vclonedel." 1
				;;
		esac
		# Se o utilizador pediu delete_volumes, apagar primeiro os volumes clone
		if [[ "$delete_mode" == "delete_volumes" ]]
		then
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Retrieving cloned volumes for volume clone $vclone_name ($VOL_CLONE_ID)..." "1"
			vcl_json=$(vol_cl_get 2>>"$log_file")
			if [[ -z "$vcl_json" ]]
			then
				echoscreen "`date +%Y-%m-%d_%H:%M:%S` - WARNING: Could not retrieve cloned volumes for $vclone_name. Skipping cloned volumes deletion and proceeding only with the volume clone request delete." "1"
			else
				# IDs dos volumes clone
				clone_vol_ids=$(echo "$vcl_json" | jq -r '.clonedVolumes[]?.clone.volumeID' 2>>"$log_file")
				if [[ -z "$clone_vol_ids" ]]
				then
					echoscreen "`date +%Y-%m-%d_%H:%M:%S` - No cloned volumes found for $vclone_name. Nothing to delete at volume level." "1"
				else
					# Construir JSON de volumeIDs para o vol_bdel
					ids_json=$(printf '"%s", ' $clone_vol_ids | sed 's/, $//')
					ACTIONS=$(cat <<EOF
						"volumeIDs": [
						  $ids_json
						]
EOF
)
					echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Deleting cloned volumes associated with $vclone_name..." "1"
					resp_bdel=$(vol_bdel 2>>"$log_file")
					ret=$?
					# Log the API response (keep what you already like: screen + logfile)
					if [[ -n "$resp_bdel" ]]
					then
						printf '%s\n' "$resp_bdel" | tee -a "$log_file" >/dev/null
					fi
					# 1) Transport-level failure (curl really failed)
					if [[ $ret -ne 0 ]]
					then
						abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - vol_bdel call failed (curl rc=$ret) while deleting cloned volumes for $vclone_name." 1
					fi
					# 2) API-level failure (HTTP 400 etc, returned as JSON but curl rc=0)
					if [[ -n "$resp_bdel" ]] && echo "$resp_bdel" | jq . >/dev/null 2>&1
					then
						# If the API returns fields like { "error": "...", "description": "..." } or { "code": 400, "message": "..." }
						if echo "$resp_bdel" | jq -e '(.code? != null) or (.error? != null) or (.errors? != null)' >/dev/null 2>&1
						then
							errmsg=$(echo "$resp_bdel" | jq -r '.description // .message // .error // (.errors[0] // empty) // "Unknown API error"' 2>/dev/null)
							abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Error deleting cloned volumes for $vclone_name: $errmsg" 1
						fi
					else
						# Non-JSON error body fallback
						if echo "$resp_bdel" | grep -qi "Bad Request\|in-use\|migrating\|cannot be deleted"
						then
							abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Error deleting cloned volumes for $vclone_name. API response indicates volumes cannot be deleted (in-use/migrating/group)." 1
						fi
					fi
					echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Cloned volumes successfully deleted for $vclone_name." "1"
				fi
			fi
		fi
		# Agora apagar o Volume Clone request
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - === Trying to Delete Volume Clone with name $vclone_name" "1"
		# (1.18.8) ret used to be tee's status, so a refused delete read as success.
		del_raw=$(vol_cl_del 2>>"$log_file")
		ret=$?
		printf '%s\n' "$del_raw" >> "$log_file"
		# (1.22.0) The status pre-check above should have already ruled this out, but a
		# status-conflict 400 can still arrive here (e.g. the request slipped back out of
		# a terminal status between the check and this call). delete_check's own field
		# precedence picks .error ("Bad Request", the HTTP reason phrase, no information)
		# over .description (which names the current status and the terminal ones IBM
		# Cloud actually wants) for every caller it is shared with (img_del, do_job_cancel
		# included) - so this shape is special-cased right here instead of changing that
		# shared precedence.
		if [ $ret -eq 0 ]
		then
			del_body_precheck="${del_raw%$'\n'*}"
			del_conflict_desc=$(printf '%s' "$del_body_precheck" | jq -r 'select(.description? != null and (.description | test("currently in status .* is required to be in status"))) | .description' 2>/dev/null)
			if [ -n "$del_conflict_desc" ]
			then
				abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Volume Clone Request $vclone_name could not be deleted: $del_conflict_desc" 1
			fi
		fi
		if [ $ret -ne 0 ] || ! delete_check "$del_raw" "volume clone request $vclone_name"
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Error deleting Volume Clone $vclone_name. Check messages above this line..." 1
		fi
		abort "`date +%Y-%m-%d_%H:%M:%S` - === Successfully Deleted Volume Clone with name $vclone_name (mode: $delete_mode) !"
	done
	if [[ "$found" -eq 0 ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Volume Clone '$vclone_name' does not exist in any workspace." 1
	fi
     ;;

   -creategrs)
	# Syntax: bluexport_api.sh -creategrs SOURCE_VSI TARGET_VSI VG_NAME SOURCE_VOLUMES_NAME
	if [ $# -lt 5 ]
	then
		usage_creategrs
		abort "`date +%Y-%m-%d_%H:%M:%S` - Arguments Missing!! Syntax: bluexport_api.sh $1 SOURCE_VSI TARGET_VSI VG_NAME SOURCE_VOLUMES_NAME" 1
	fi
	if [ $# -gt 5 ]
	then
		usage_creategrs
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport_api.sh $1 SOURCE_VSI TARGET_VSI VG_NAME SOURCE_VOLUMES_NAME" 1
	fi
	test=0
	flagj=1    # não precisamos de iASP / flush aqui
	source_vsi=$2
	target_vsi=$3
	vg_name=$4
	vol_com_name=$5        # prefixo/nome comum dos volumes no SOURCE
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Validating source VSI $source_vsi and target VSI $target_vsi in config and in IBM Cloud." "1"
	# SOURCE VSI – verificar se existe e guardar contexto
	vsi=$source_vsi
	vsi_id_bluexscrt
	check_locally_VSI_exists
	source_ws_crn="$shortnamecrn"
	source_CLOUD_INSTANCE_ID="$CLOUD_INSTANCE_ID"
	source_base_url="$base_url"
	source_PVM_ID="$PVM_ID"
	source_vsi_id="$vsi_id"
	# TARGET VSI – verificar se existe e guardar contexto
	vsi=$target_vsi
	vsi_id_bluexscrt
	check_locally_VSI_exists
	target_ws_crn="$shortnamecrn"
	target_CLOUD_INSTANCE_ID="$CLOUD_INSTANCE_ID"
	target_base_url="$base_url"
	target_PVM_ID="$PVM_ID"
	target_vsi_id="$vsi_id"
	###############################################
	# Check snapshots on SOURCE VSI volumes first #
	###############################################
	# Forçar contexto da workspace / SOURCE_VSI
	base_url="$source_base_url"
	CRN="$source_ws_crn"
	CLOUD_INSTANCE_ID="$source_CLOUD_INSTANCE_ID"
	PVM_ID="$source_PVM_ID"
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Checking if there are existing Snapshots for source VSI $source_vsi volumes..." "1"
	# Volumes associados ao SOURCE_VSI via API
	source_vsi_vol_ids=$(ins_vol_ls | jq -r '.volumes[]? | .volumeID' 2>>"$log_file")
	if [[ -n "$source_vsi_vol_ids" ]]
	then
		snapshots_json=$(snap_ls 2>>"$log_file")
		vols_with_snaps=""
		for vol_id in $source_vsi_vol_ids
		do
			# Procurar snapshots onde o mapa volumeSnapshots tem a key = volumeID do VSI
			snap_names=$(echo "$snapshots_json" | jq -r --arg vol_id "$vol_id" '
				.snapshots // [] 
				| .[] 
				| select((.volumeSnapshots // {}) | has($vol_id)) 
				| .name
			' 2>>"$log_file")
			if [[ -n "$snap_names" ]]
			then
				vols_with_snaps="$vols_with_snaps\nVolumeID: $vol_id -> Snapshots: $snap_names"
			fi
		done
		if [[ -n "$vols_with_snaps" ]]
		then
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Existing Snapshots were found for volumes attached to source VSI $source_vsi. Replication cannot be enabled while these Snapshots exist." "1"
			echoscreen "$vols_with_snaps" "1"
			abort "`date +%Y-%m-%d_%H:%M:%S` - Aborting GRS creation - please delete the snapshots for these volumes and run bluexport_api.sh $flags again." 1
		fi
	fi
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Both VSIs found and validated. Proceeding with GRS creation..." "1"
	create_grs
     ;;

  -deletegrs)
	# Syntax: bluexport_api.sh -deletegrs SOURCE_VSI TARGET_VSI VG_NAME SOURCE_VOLUME_NAMES
	if [ $# -lt 5 ]
	then
		usage_deletegrs
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments Missing!! Syntax: bluexport_api.sh $1 SOURCE_VSI TARGET_VSI VG_NAME SOURCE_VOLUME_NAMES" 1
	fi
	if [ $# -gt 5 ]
	then
		usage_deletegrs
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments!! Syntax: bluexport_api.sh $1 SOURCE_VSI TARGET_VSI VG_NAME SOURCE_VOLUME_NAMES" 1
	fi
	test=0
	flagj=1    # não precisamos de iASP / flush aqui
	source_vsi=$2
	target_vsi=$3
	vg_name=$4
	vol_com_name=$5    # prefixo/nome comum dos volumes no SOURCE (e padrão para TARGET)
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Validating source VSI $source_vsi and target VSI $target_vsi in config and in IBM Cloud." "1"
	# SOURCE VSI – verificar se existe e guardar contexto
	vsi=$source_vsi
	vsi_id_bluexscrt
	check_locally_VSI_exists
	source_ws_crn="$shortnamecrn"
	source_CLOUD_INSTANCE_ID="$CLOUD_INSTANCE_ID"
	source_base_url="$base_url"
	source_PVM_ID="$PVM_ID"
	source_vsi_id="$vsi_id"
	# TARGET VSI – verificar se existe e guardar contexto
	vsi=$target_vsi
	vsi_id_bluexscrt
	check_locally_VSI_exists
	target_ws_crn="$shortnamecrn"
	target_CLOUD_INSTANCE_ID="$CLOUD_INSTANCE_ID"
	target_base_url="$base_url"
	target_PVM_ID="$PVM_ID"
	target_vsi_id="$vsi_id"
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Both VSIs validated. Proceeding with GRS delete..." "1"
	delete_grs
	abort "$(date +%Y-%m-%d_%H:%M:%S) - === Successfully finished GRS delete for VG $vg_name between $source_vsi and $target_vsi ==="
     ;;

  -grsfailover)
	# Syntax: bluexport_api.sh -grsfailover SOURCE_VSI VG_NAME NO_ATTACH|ATTACH [TARGET_VSI]
	if [ $# -lt 4 ]
	then
		usage_grsfailover
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments Missing!! Syntax: bluexport_api.sh $1 SOURCE_VSI VG_NAME NO_ATTACH|ATTACH [TARGET_VSI]" 1
	fi
	if [ $# -gt 5 ]
	then
		usage_grsfailover
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments!! Syntax: bluexport_api.sh $1 SOURCE_VSI VG_NAME NO_ATTACH|ATTACH [TARGET_VSI]" 1
	fi
	test=0
	flagj=1
	source_vsi="$2"
	vg_name="$3"
	attach_mode="$4"
	target_vsi=""
	if [[ "$attach_mode" == "ATTACH" ]]
	then
		if [ $# -ne 5 ]
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - TARGET_VSI is required when using ATTACH mode. Syntax: bluexport_api.sh $1 SOURCE_VSI VG_NAME ATTACH TARGET_VSI" 1
		fi
		target_vsi="$5"
	elif [[ "$attach_mode" != "NO_ATTACH" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Invalid MODE '$attach_mode'. Use NO_ATTACH or ATTACH." 1
	fi
	do_grs_failover
     ;;

  -grscancelfailover)
	# Syntax: bluexport_api.sh -grscancelfailover SOURCE_VSI VG_NAME NO_DETACH|DETACH TARGET_VSI
	if [ $# -ne 5 ]
	then
		usage_grscancelfailover
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments Missing/Invalid!! Syntax: bluexport_api.sh $1 SOURCE_VSI VG_NAME NO_DETACH|DETACH TARGET_VSI" 1
	fi
	test=0
	flagj=1
	source_vsi="$2"
	vg_name="$3"
	detach_mode="$4"
	target_vsi="$5"
	if [[ "$detach_mode" != "NO_DETACH" && "$detach_mode" != "DETACH" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Invalid MODE '$detach_mode'. Use NO_DETACH or DETACH." 1
	fi
	do_grs_cancel_failover
     ;;

  -grsfailback)
	# Syntax: bluexport_api.sh -grsfailback SOURCE_VSI TARGET_VSI VG_NAME
	if [ $# -ne 4 ]
	then
		usage_grsfailback
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments Missing/Invalid!! Syntax: bluexport_api.sh $1 SOURCE_VSI TARGET_VSI VG_NAME" 1
	fi
	test=0
	flagj=1
	source_vsi="$2"
	target_vsi="$3"
	vg_name="$4"
	do_grs_failback
     ;;

  -grsreversereplica)
	# Syntax: bluexport_api.sh -grsreversereplica SOURCE_VSI TARGET_VSI VG_NAME
	if [ $# -ne 4 ]
	then
		usage_grsreversereplica
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments Missing/Invalid!! Syntax: bluexport_api.sh $1 SOURCE_VSI TARGET_VSI VG_NAME" 1
	fi
	test=0
	flagj=1
	source_vsi="$2"
	target_vsi="$3"
	vg_name="$4"
	do_grs_reverse_replica
     ;;

   -vsistart)
	if [ $# -ne 2 ]
	then
		usage_vsistart
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many or too few arguments!! Syntax: bluexport_api.sh -vsistart VSI_NAME" 1
	fi
	vsi="$2"
	do_start_vsi "$vsi"
     ;;

   -vsioper)
	# Syntax: -vsioper VSI_NAME BOOT_MODE OPERATING_MODE
	if [ $# -ne 4 ]
	then
		usage_vsioper
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many or too few arguments!! Syntax: bluexport_api.sh -vsioper VSI_NAME BOOT_MODE OPERATING_MODE. BOOT_MODE: a | b | c | d  -  OPERATING_MODE: normal | manual" 1
	fi
	vsi="$2"
	boot_mode="$3"
	operating_mode="$4"
	do_vsi_oper "$vsi" "$boot_mode" "$operating_mode"
     ;;

   -vsitask)
	if [ $# -ne 3 ]
	then
		usage_vsitask
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many or too few arguments!! Syntax: bluexport_api.sh -vsitask VSI_NAME TASK. TASK: dston | retrydump | consoleservice | iopreset | remotedstoff | remotedston | iopdump | dumprestart" 1
	fi
	vsi="$2"
	task="$3"
	do_vsi_task "$vsi" "$task"
     ;;

   -vsisrcmon)
	if [ $# -ne 3 ]
	then
		usage_vsisrcmon
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many or too few arguments!! Syntax: bluexport_api.sh -vsisrcmon VSI_NAME START|SHUTOFF" 1
	fi
	vsi="$2"
	mode="$3"
	do_vsi_srcmon "$vsi" "$mode"
     ;;

   -attachvolumes)
	# Syntax: bluexport_api.sh -attachvolumes VOLUMES_COMMON_NAME VSI_NAME
	if [ $# -ne 3 ]
	then
		usage_attachvolumes
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many or too few arguments!! Syntax: bluexport_api.sh -attachvolumes VOLUMES_COMMON_NAME VSI_NAME" 1
	fi
	vol_common_name="$2"
	vsi="$3"
	do_vsi_attach_volumes "$vol_common_name" "$vsi"
     ;;

   -detachvolumes)
	# Syntax: bluexport_api.sh -detachvolumes VSI_NAME
	if [ $# -ne 2 ]
	then
		usage_detachvolumes
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many or too few arguments!! Syntax: bluexport_api.sh -detachvolumes VSI_NAME" 1
	fi
	vsi="$2"
	do_vsi_detach_volumes "$vsi"
     ;;

   -bucketslsall)
	# Lista todos os buckets por COS instance definido em .cos_instances no bluexscrt
	if [ $# -gt 1 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments!! Syntax: bluexport_api.sh $1" 1
	fi
	test=0
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - === Starting Listing all COS buckets for all COS instances defined in $bluexscrt ===" "1"
	# Ir buscar as chaves dos cos_instances (nomes lógicos completos, incluindo espaços)
	cos_keys=$(jq -r '.cos_instances | keys[]?' "$bluexscrt" 2>>"$log_file")
	if [[ -z "$cos_keys" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - No cos_instances section or no COS instances defined in $bluexscrt. Nothing to list."
	fi

	# Iterar linha a linha para não partir nomes com espaços
	while IFS= read -r cos
	do
		[[ -z "$cos" ]] && continue
		SERVICE_INSTANCE_ID=$(jq -r --arg ci "$cos" '.cos_instances[$ci].guid // ""' "$bluexscrt" 2>>"$log_file")
		cos_crn=$(jq -r --arg ci "$cos" '.cos_instances[$ci].crn  // ""' "$bluexscrt" 2>>"$log_file")
		if [[ -z "$SERVICE_INSTANCE_ID" || "$SERVICE_INSTANCE_ID" == "null" ]]
		then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - COS instance \"$cos\" has no GUID in $bluexscrt. Skipping." "1"
			continue
		fi
		# Região do endpoint S3: usa a region do .access
		REGION="$region"
		echoscreen "" "1"
		echoscreen "================================================================================" "1"
		echoscreen "COS INSTANCE: $cos" "1"
		echoscreen "GUID:        $SERVICE_INSTANCE_ID" "1"
		echoscreen "CRN:         $cos_crn" "1"
		echoscreen "REGION:      $REGION" "1"
		echoscreen "================================================================================" "1"
		# Chamada à API S3 para listar buckets deste COS instance
		buckets_xml=$(cos_ls_buckets 2>>"$log_file")
		ret=$?
		if [ $ret -ne 0 ]
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - COS bucket listing failed (curl rc=$ret). Likely no internet / DNS / TLS. See log: $log_file" 1
		fi
		# Guardar XML bruto no log para debug
		echo "$buckets_xml" >>"$log_file"
		if [[ -z "$buckets_xml" ]]
		then
			echoscreen "No Buckets Found or empty response" "1"
			continue
		fi
		# Parsing do XML em puro bash + sed (IBM i-safe):
		# Percorre cada bloco <Bucket>...</Bucket> dentro da string completa
		bxml="$buckets_xml"
		found_bucket=0
		while [[ "$bxml" == *"<Bucket>"*"</Bucket>"* ]]
		do
			# Extrair 1 bloco <Bucket>...</Bucket>
			bchunk="${bxml#*<Bucket>}"
			bchunk="${bchunk%%</Bucket>*}"
			# Avançar o cursor para a frente deste <Bucket> para o próximo ciclo
			bxml="${bxml#*</Bucket>}"
			# Extrair Name
			name=$(printf '%s\n' "$bchunk" | sed 's/^.*<Name>//; s/<\/Name>.*$//')
			# Extrair CreationDate
			date=$(printf '%s\n' "$bchunk" | sed 's/^.*<CreationDate>//; s/<\/CreationDate>.*$//')
			if [[ -n "$name" ]]
			then
				found_bucket=1
				echoscreen "Bucket Name:      $name" "1"
				[[ -n "$date" ]] && echoscreen "Creation Date:    $date" "1"
				echoscreen "------------------------------------------------------------" "1"
			fi
		done
		if [[ "$found_bucket" -eq 0 ]]
		then
			echoscreen "No <Bucket> entries found in XML response for COS instance \"$cos\"." "1"
		fi
		echoscreen "" "1"
	done <<< "$cos_keys"
	abort "$(date +%Y-%m-%d_%H:%M:%S) - === Finished Listing all COS buckets for all COS instances ==="
     ;;

  # (1.23.0) Read-only inventory report across every configured workspace
  # (and COS instance): workspaces, LPARs, volumes, volume groups,
  # snapshots, images, volume clones and COS buckets, plus totals. See
  # usage_invreport / -h -invreport for FORMAT/PATH/OLD_DAYS.
  -invreport)
	if [ $# -gt 4 ]
	then
		usage_invreport
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments!! Syntax: bluexport_api.sh $1" 1
	fi
	test=0
	invreport_format="${2:-md}"
	invreport_format="${invreport_format,,}"
	case "$invreport_format" in
		md|csv|html|all)
			;;
		*)
			usage_invreport
			abort "$(date +%Y-%m-%d_%H:%M:%S) - Unknown FORMAT '$2'. Use md|csv|html|all." 1
			;;
	esac
	invreport_path="${3:-./bluexport-inventory-$(date +%Y%m%d-%H%M)}"
	invreport_old_days="${4:-90}"
	if ! [[ "$invreport_old_days" =~ ^[0-9]+$ ]]
	then
		usage_invreport
		abort "$(date +%Y-%m-%d_%H:%M:%S) - OLD_DAYS must be a non-negative integer, got '$4'." 1
	fi
	do_invreport "$invreport_format" "$invreport_path" "$invreport_old_days"
    ;;

  -bucketlsobjs)
	# Lista objetos de um bucket COS escolhido interativamente
	if [ $# -gt 1 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments!! Syntax: bluexport_api.sh -bucketlsobjs" 1
	fi
	test=0
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - === Starting interactive COS bucket objects listing ===" "1"
	# 1) Obter COS instances do JSON
	cos_keys=$(jq -r '.cos_instances | keys[]?' "$bluexscrt" 2>>"$log_file")
	if [[ -z "$cos_keys" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - No cos_instances section or no COS instances defined in $bluexscrt. Nothing to list."
	fi
	# Guardar nomes em array para escolha
	cos_array=()
	while IFS= read -r cos_name
	do
		[[ -z "$cos_name" ]] && continue
		cos_array+=("$cos_name")
	done <<< "$cos_keys"
	cos_count=${#cos_array[@]}
	if [ "$cos_count" -eq 0 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - No COS instances found in $bluexscrt. Nothing to list."
	fi
	echoscreen "" "1"
	echoscreen "Available COS instances (from cos_instances in $bluexscrt):" "1"
	idx=1
	for cname in "${cos_array[@]}"
	do
		echoscreen "[$idx] $cname" "1"
		idx=$((idx+1))
	done
	echoscreen "" "1"
	# 2) Escolher COS instance
	while true
	do
		printf "Select COS instance index [1-%d]: " "$cos_count" > /dev/tty
		if ! read -r cos_choice < /dev/tty; then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - No input received from terminal. Aborting..." "1"
			abort "$(date +%Y-%m-%d_%H:%M:%S) - Aborted by user (no selection)."
		fi
		if ! [[ "$cos_choice" =~ ^[0-9]+$ ]]; then
			echo "Invalid input. Please enter a number between 1 and $cos_count." > /dev/tty
			continue
		fi
		if (( cos_choice < 1 || cos_choice > cos_count )); then
			echo "Choice out of range. Please select between 1 and $cos_count." > /dev/tty
			continue
		fi
		break
	done
	chosen_cos="${cos_array[$((cos_choice-1))]}"
	# Ler GUID e CRN da COS instance escolhida
	SERVICE_INSTANCE_ID=$(jq -r --arg ci "$chosen_cos" '.cos_instances[$ci].guid // ""' "$bluexscrt" 2>>"$log_file")
	cos_crn=$(jq -r --arg ci "$chosen_cos" '.cos_instances[$ci].crn  // ""' "$bluexscrt" 2>>"$log_file")
	if [[ -z "$SERVICE_INSTANCE_ID" || "$SERVICE_INSTANCE_ID" == "null" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - COS instance \"$chosen_cos\" has no GUID in $bluexscrt. Cannot list buckets." 1
	fi
	REGION="$region"  # por agora usamos a mesma region definida em .access
	echoscreen "" "1"
	echoscreen "================================================================================" "1"
	echoscreen "Selected COS INSTANCE: $chosen_cos" "1"
	echoscreen "GUID:                  $SERVICE_INSTANCE_ID" "1"
	echoscreen "CRN:                   $cos_crn" "1"
	echoscreen "REGION (S3 endpoint):  $REGION" "1"
	echoscreen "================================================================================" "1"
	# 3) Listar buckets dessa COS instance
	buckets_xml=$(cos_ls_buckets 2>>"$log_file")
	ret=$?
	if [ $ret -ne 0 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - COS bucket listing failed (curl rc=$ret). Likely no internet / DNS / TLS. See log: $log_file" 1
	fi
	echo "$buckets_xml" >>"$log_file"
	if [[ -z "$buckets_xml" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Empty response from S3 when listing buckets for COS instance \"$chosen_cos\"." 1
	fi
	# Extrair lista de bucket names (IBM i-safe)
	bxml="$buckets_xml"
	bucket_names=()
	while [[ "$bxml" == *"<Bucket>"*"</Bucket>"* ]]
	do
		bchunk="${bxml#*<Bucket>}"
		bchunk="${bchunk%%</Bucket>*}"
		bxml="${bxml#*</Bucket>}"
		bname=$(printf '%s\n' "$bchunk" | sed 's/^.*<Name>//; s/<\/Name>.*$//')
		if [[ -n "$bname" ]]
		then
			bucket_names+=("$bname")
		fi
	done
	bucket_count=${#bucket_names[@]}
	if [ "$bucket_count" -eq 0 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - No buckets found for COS instance \"$chosen_cos\"."
	fi
	echoscreen "" "1"
	echoscreen "Buckets in COS instance \"$chosen_cos\":" "1"
	i=1
	for bname in "${bucket_names[@]}"
	do
		echoscreen "[$i] $bname" "1"
		i=$((i+1))
	done
	echoscreen "" "1"
	# 4) Escolher bucket
	while true
	do
		printf "Select bucket index [1-%d]: " "$bucket_count" > /dev/tty
		if ! read -r bucket_choice < /dev/tty; then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - No input received from terminal. Aborting..." "1"
			abort "$(date +%Y-%m-%d_%H:%M:%S) - Aborted by user (no bucket selection)."
		fi
		if ! [[ "$bucket_choice" =~ ^[0-9]+$ ]]; then
			echo "Invalid input. Please enter a number between 1 and $bucket_count." > /dev/tty
			continue
		fi
		if (( bucket_choice < 1 || bucket_choice > bucket_count )); then
			echo "Choice out of range. Please select between 1 and $bucket_count." > /dev/tty
			continue
		fi
		break
	done
	chosen_bucket="${bucket_names[$((bucket_choice-1))]}"
	echoscreen "" "1"
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Listing objects from bucket \"$chosen_bucket\" in region $REGION..." "1"
	# 5) Listar objetos do bucket escolhido usando list_object()
	REGION="$region"
	BUCKET="$chosen_bucket"
	objects_xml=$(list_object 2>>"$log_file")
	echo "$objects_xml" >>"$log_file"
	if [[ -z "$objects_xml" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Empty response from S3 when listing objects in bucket \"$chosen_bucket\"." 1
	fi
	# Extrair todas as chaves <Key>...</Key> em modo IBM i-safe (sem confiar em \n)
	data="$objects_xml"
	counter=1
	found_obj=0
	while [[ "$data" == *"<Key>"*"</Key>"* ]]
	do
		tmp="${data#*<Key>}"       # corta tudo até ao primeiro <Key>
		key="${tmp%%</Key>*}"     # fica só até antes do </Key>
		data="${tmp#*</Key>}"     # avança o cursor para depois desse </Key>
		if [[ -n "$key" ]]
		then
			if [[ "$found_obj" -eq 0 ]]
			then
				echoscreen "" "1"
				echoscreen "Objects in bucket \"$chosen_bucket\":" "1"
			fi
			found_obj=1
			echoscreen "[$counter] $key" "1"
			counter=$((counter+1))
		fi
	done
	if [[ "$found_obj" -eq 0 ]]
	then
		echoscreen "No objects found in bucket \"$chosen_bucket\"." "1"
	fi
	abort "$(date +%Y-%m-%d_%H:%M:%S) - === Finished listing objects for bucket \"$chosen_bucket\" ==="
     ;;

   -restorefromarchive)
	# Restore an archived object from COS bucket (S3 Restore)
	if [ $# -lt 3 ]
	then
		usage_restorefromarchive
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments Missing!! Syntax: bluexport_api.sh -restorefromarchive BUCKET OBJECT [DAYS] [ARCHIVE_TYPE]" 1
	fi
	if [ $# -gt 5 ]
	then
		usage_restorefromarchive
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments!! Syntax: bluexport_api.sh -restorefromarchive BUCKET OBJECT [DAYS] [ARCHIVE_TYPE]" 1
	fi
	test=0
	bucket="$2"
	object="$3"
	days="$4"
	arch_type="$5"
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - === Starting -restorefromarchive for bucket '$bucket' object '$object' ===" "1"
	do_object_restore_from_archive "$bucket" "$object" "$days" "$arch_type"
     ;;

   -bucketdelobj)
	# Delete a single object from a COS bucket (interactive)
	if [ $# -gt 1 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments!! Syntax: bluexport_api.sh -bucketdelobj" 1
	fi
	test=0
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - === Starting interactive COS bucket object delete ===" "1"
	# 1) Obter COS instances do JSON
	cos_keys=$(jq -r '.cos_instances | keys[]?' "$bluexscrt" 2>>"$log_file")
	if [[ -z "$cos_keys" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - No cos_instances section or no COS instances defined in $bluexscrt. Nothing to list."
	fi
	# Construir array com nomes de COS instances
	cos_array=()
	while IFS= read -r cos
	do
		[[ -z "$cos" ]] && continue
		cos_array+=("$cos")
	done <<< "$cos_keys"
	cos_count=${#cos_array[@]}
	if [ "$cos_count" -eq 0 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - No COS instances found in $bluexscrt. Nothing to list."
	fi
	echoscreen "" "1"
	echoscreen "Available COS instances (from cos_instances in $bluexscrt):" "1"
	idx=1
	for cname in "${cos_array[@]}"
	do
		echoscreen "[$idx] $cname" "1"
		idx=$((idx+1))
	done
	echoscreen "" "1"
	# 2) Escolher COS instance (IBM i-safe: ler sempre de /dev/tty)
	while true
	do
		printf "Select COS instance index [1-%d]: " "$cos_count" > /dev/tty
		if ! read -r cos_choice < /dev/tty; then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - No input received from terminal. Aborting..." 1
		fi
		if ! echo "$cos_choice" | grep -Eq '^[0-9]+$'; then
			echo "Invalid input. Please enter a number between 1 and $cos_count." > /dev/tty
			continue
		fi
		if (( cos_choice < 1 || cos_choice > cos_count )); then
			echo "Choice out of range. Please select between 1 and $cos_count." > /dev/tty
			continue
		fi
		break
	done
	chosen_cos="${cos_array[$((cos_choice-1))]}"
	# Ler GUID e CRN da COS instance escolhida
	SERVICE_INSTANCE_ID=$(jq -r --arg ci "$chosen_cos" '.cos_instances[$ci].guid // ""' "$bluexscrt" 2>>"$log_file")
	cos_crn=$(jq -r --arg ci "$chosen_cos" '.cos_instances[$ci].crn  // ""' "$bluexscrt" 2>>"$log_file")
	if [[ -z "$SERVICE_INSTANCE_ID" || "$SERVICE_INSTANCE_ID" == "null" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - COS instance \"$chosen_cos\" has no GUID in $bluexscrt. Cannot list buckets." 1
	fi
	REGION="$region"	# mesma lógica do -bucketlsobjs
	echoscreen "" "1"
	echoscreen "================================================================================" "1"
	echoscreen "Selected COS INSTANCE: $chosen_cos" "1"
	echoscreen "GUID:                  $SERVICE_INSTANCE_ID" "1"
	echoscreen "CRN:                   $cos_crn" "1"
	echoscreen "REGION (S3 endpoint):  $REGION" "1"
	echoscreen "================================================================================" "1"
	# 3) Listar buckets dessa COS instance
	buckets_xml=$(cos_ls_buckets 2>>"$log_file")
	ret=$?
	if [ $ret -ne 0 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - COS bucket listing failed (curl rc=$ret). Likely no internet / DNS / TLS. See log: $log_file" 1
	fi
	echo "$buckets_xml" >>"$log_file"
	if [[ -z "$buckets_xml" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Empty response from S3 when listing buckets for COS instance \"$chosen_cos\"." 1
	fi
	# Extrair nomes dos buckets (mesmo parsing IBM i-safe usado no -bucketslsall)
	bucket_names=()
	bxml="$buckets_xml"
	while [[ "$bxml" == *"<Bucket>"*"</Bucket>"* ]]
	do
		bchunk="${bxml#*<Bucket>}"
		bchunk="${bchunk%%</Bucket>*}"
		bxml="${bxml#*</Bucket>}"
		bname=$(printf '%s\n' "$bchunk" | sed 's/^.*<Name>//; s/<\/Name>.*$//')
		if [[ -n "$bname" ]]
		then
			bucket_names+=("$bname")
		fi
	done
	bucket_count=${#bucket_names[@]}
	if [ "$bucket_count" -eq 0 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - No buckets found for COS instance \"$chosen_cos\"."
	fi
	echoscreen "" "1"
	echoscreen "Buckets in COS instance \"$chosen_cos\":" "1"
	i=1
	for bname in "${bucket_names[@]}"
	do
		echoscreen "[$i] $bname" "1"
		i=$((i+1))
	done
	echoscreen "" "1"
	# 4) Escolher bucket
	while true
	do
		printf "Select bucket index [1-%d]: " "$bucket_count" > /dev/tty
		if ! read -r bucket_choice < /dev/tty; then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - No input received from terminal. Aborting..." 1
		fi
		if ! echo "$bucket_choice" | grep -Eq '^[0-9]+$'; then
			echo "Invalid input. Please enter a number between 1 and $bucket_count." > /dev/tty
			continue
		fi
		if (( bucket_choice < 1 || bucket_choice > bucket_count )); then
			echo "Choice out of range. Please select between 1 and $bucket_count." > /dev/tty
			continue
		fi
		break
	done
	chosen_bucket="${bucket_names[$((bucket_choice-1))]}"
	echoscreen "" "1"
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Listing objects from bucket \"$chosen_bucket\" in region $REGION..." "1"
	# 5) Listar objetos do bucket escolhido (mesmo parsing do -bucketlsobjs, mas guardando em array)
	REGION="$region"
	BUCKET="$chosen_bucket"
	objects_xml=$(list_object 2>>"$log_file")
	echo "$objects_xml" >>"$log_file"
	if [[ -z "$objects_xml" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Empty response from S3 when listing objects in bucket \"$chosen_bucket\"." 1
	fi
	data="$objects_xml"
	obj_array=()
	while [[ "$data" == *"<Key>"*"</Key>"* ]]
	do
		tmp="${data#*<Key>}"
		key="${tmp%%</Key>*}"
		data="${tmp#*</Key>}"
		if [[ -n "$key" ]]
		then
			obj_array+=("$key")
		fi
	done
	obj_count=${#obj_array[@]}
	if [ "$obj_count" -eq 0 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - No objects found in bucket \"$chosen_bucket\". Nothing to delete."
	fi
	echoscreen "" "1"
	echoscreen "Objects in bucket \"$chosen_bucket\":" "1"
	j=1
	for obj in "${obj_array[@]}"
	do
		echoscreen "[$j] $obj" "1"
		j=$((j+1))
	done
	echoscreen "" "1"
	# 6) Escolher objeto a apagar
	while true
	do
		printf "Select object index to DELETE [1-%d]: " "$obj_count" > /dev/tty
		if ! read -r obj_choice < /dev/tty; then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - No input received from terminal. Aborting..." 1
		fi
		if ! echo "$obj_choice" | grep -Eq '^[0-9]+$'; then
			echo "Invalid input. Please enter a number between 1 and $obj_count." > /dev/tty
			continue
		fi
		if (( obj_choice < 1 || obj_choice > obj_count )); then
			echo "Choice out of range. Please select between 1 and $obj_count." > /dev/tty
			continue
		fi
		break
	done
	chosen_key="${obj_array[$((obj_choice-1))]}"
	echoscreen "" "1"
	echoscreen "You selected object to delete:" "1"
	echoscreen "  COS instance : $chosen_cos" "1"
	echoscreen "  Bucket       : $chosen_bucket" "1"
	echoscreen "  Object key   : $chosen_key" "1"
	echoscreen "" "1"
	# Confirmação antes de apagar
	printf "Are you sure you want to DELETE this object? (Y/N): " > /dev/tty
	if ! read -r confirm_del < /dev/tty; then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - No confirmation received. Aborting delete."
	fi
	case "$confirm_del" in
		Y|y|YES|yes)
			;;
		*)
			abort "$(date +%Y-%m-%d_%H:%M:%S) - Deletion cancelled by user."
			;;
	esac
	# 7) Chamar object_delete() com BUCKET/KEY/REGION definidos
	BUCKET="$chosen_bucket"
	KEY="$chosen_key"
	REGION="$region"
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Deleting object \"$KEY\" from bucket \"$BUCKET\" in region $REGION..." "1"
	del_raw=$(object_delete 2>>"$log_file")
	printf '%s\n' "$del_raw" >> "$log_file"
	delete_check "$del_raw" "object $KEY in bucket $BUCKET" || abort "$(date +%Y-%m-%d_%H:%M:%S) - Object \"$KEY\" was NOT deleted from bucket \"$BUCKET\"." 1
	abort "$(date +%Y-%m-%d_%H:%M:%S) - === Finished deleting object \"$KEY\" from bucket \"$BUCKET\" ==="
     ;;


    *)
	if [ -t 1 ]
	then
		help
	fi
	abort "`date +%Y-%m-%d_%H:%M:%S` - Missing or invalid Flag!" 1
    ;;
esac
####  END: Iniciate Log and Validate Arguments  ####

check_locally_VSI_exists

####  START: Get Volumes to capture  ####
eval $volumes_cmd > $volumes_file | tee -a $log_file
volumes=$(cat $volumes_file | awk {'print $1'} | tr '\n' ',' | sed 's/,$//')
volumes_api=$(echo $volumes | sed 's/,/","/g')
volumes_name=$(cat $volumes_file | awk {'print $2'} | tr '\n' ' ')
echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Volumes ID Captured: $volumes" "1"
echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Volumes Name Captured: $volumes_name" "1"
####  END: Get Volumes to capture  ####

####  START: Flush ASPs and iASP Memory to Disk  ####
if [ $shutoff -eq 0 ]
then
	if [[ "$vsi_os" == "ibmi" ]]
	then
		flush_asps
	else
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - VSI $vsi is $vsi_os - CHGASPACT not applicable, skipping ASP flush." "1"
	fi
else
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Skipping Flushing Memory to Disk..." "1"
fi

####  END: Flush ASPs and iASP Memory to Disk  ####

####  START: Make the Capture and Export  ####
if [[ $destination == "image-catalog" ]]
then
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - == Executing Capture to image catalog cloud command... ==" "1"
	ACTIONS="\"captureName\": \"$capture_name\", \"captureDestination\": \"$destination\", \"captureVolumeIDs\": [\"$volumes_api\"]"
	if [ $test -eq 1 ]
	then
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - ins_cap \"$ACTIONS\"" "1"
	else
		rm $job_id_file
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - ins_cap \"$ACTIONS\"" "1"
		cap_raw=$(ins_cap)
		parse_cap_response "$cap_raw" || abort "$(date +%Y-%m-%d_%H:%M:%S) - Capture request rejected, see message above."
	fi
else
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - == Executing Capture and Export cloud command... ==" "1"
	ACTIONS="\"captureName\": \"$capture_name\", \"captureDestination\": \"$destination\", \"captureVolumeIDs\": [\"$volumes_api\"], \"cloudStorageAccessKey\": \"$accesskey\", \"cloudStorageImagePath\": \"$bucket\", \"cloudStorageRegion\": \"$region\", \"cloudStorageSecretKey\": \"$secretkey\""
	if [ $test -eq 1 ]
	then
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - ins_cap \"$ACTIONS\"" "1"
	else
		rm $job_id_file
		cap_raw=$(ins_cap)
		parse_cap_response "$cap_raw" || abort "$(date +%Y-%m-%d_%H:%M:%S) - Capture request rejected, see message above."

	fi
fi
####  END: Make the Capture and Export  ####

####  START: Job Monitoring  ####
if [ $test -eq 0 ]
then
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - => Initiating Job Monitoring..." "1"
else
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - => Initiating Job Monitoring..." "1"
	abort "`date +%Y-%m-%d_%H:%M:%S` - Test Finished!"
fi

job_monitor
####  END: Job Monitoring  ####

       #####  END:CODE  #####
