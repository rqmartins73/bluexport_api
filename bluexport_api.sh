#!/bin/bash
#
# Capture IBM Cloud POWERVS IBM i VSI and Export to COS and/or Image Catalog, manage Snapshots, Volume Clones and GRS Volume Groups.
#
# === General ===
# Changing secret file:          ./bluexport_api.sh -chscrt bluexscrt_file_name   (use full path, e.g. /home/user/bluexscrt_new)
# View secret file in use:       ./bluexport_api.sh -viewscrt
#
# Show help:                     ./bluexport_api.sh -h | --help | -help
# Show version:                  ./bluexport_api.sh -v | --version
#
# === Capture & Export ===
# Usage for all volumes:         ./bluexport_api.sh -a VSI_Name_to_Capture Capture_Image_Name both|image-catalog|cloud-storage hourly|daily|weekly|monthly|single
# Usage for excluding volumes:   ./bluexport_api.sh -x volumes_name_to_exclude VSI_Name_to_Capture Capture_Image_Name both|image-catalog|cloud-storage hourly|daily|weekly|monthly|single
# Usage for monitoring job:      ./bluexport_api.sh -j VSI_NAME IMAGE_NAME
#
# === Snapshots ===
# Create snapshot:               ./bluexport_api.sh -snapcr   VSI_NAME SNAPSHOT_NAME 0|[DESCRIPTION] 0|[VOLUMES(Comma separated list)]
# Update snapshot:               ./bluexport_api.sh -snapupd  SNAPSHOT_NAME 0|[NEW_SNAPSHOT_NAME] 0|[DESCRIPTION]
# Delete snapshot:               ./bluexport_api.sh -snapdel  SNAPSHOT_NAME
# Restore snapshot:              ./bluexport_api.sh -snapres VSI_NAME SNAPSHOT_NAME
# List all snapshots (all WS):   ./bluexport_api.sh -snaplsall
#
# === Captured Images ===
# List all captured images
#  in all Workspaces:            ./bluexport_api.sh -imglsall
# Delete image:                  ./bluexport_api.sh -imgdel IMG_NAME
#
# === Cloud Object Storage (COS) ===
# List buckets for all COS instances (from bluexscrt): 	./bluexport_api.sh -bucketslsall
# List objects from a COS bucket:     			./bluexport_api.sh -bucketlsobjs
# Delete object from a COS bucket:    			./bluexport_api.sh -bucketdelobj
#
# === Volume Clones ===
# Create volume clone:           ./bluexport_api.sh -vclone VOLUME_CLONE_NAME BASE_NAME LPAR_NAME True|False(replication-enabled) True|False(rollback-prepare) STORAGE_TIER ALL|(Comma separated Volumes name list to clone)
# Delete volume clone:           ./bluexport_api.sh -vclonedel VOLUME_CLONE_NAME 0|delete_volumes
# List volume clones (all WS):   ./bluexport_api.sh -vclonelsall
#
# === Volume Tier ===
# Change volume tier:            ./bluexport_api.sh -vchtier VSI_NAME VOLUMES_NAME TIER_TO_CHANGE_TO
#
# === GRS (Global Replication Services) ===
# Create GRS Volume Group and onboard auxiliary volumes:  ./bluexport_api.sh -creategrs SOURCE_VSI TARGET_VSI VG_NAME SOURCE_VOLUMES_NAME
# Delete GRS Volume Group and auxiliary volumes:	  ./bluexport_api.sh -deletegrs SOURCE_VSI TARGET_VSI VG_NAME SOURCE_VOLUMES_NAME
# Failover GRS Volume Group (activate target):            ./bluexport_api.sh -grsfailover SOURCE_VSI VG_NAME NO_ATTACH|ATTACH [TARGET_VSI]
# Cancel GRS failover (sync master->aux):                 ./bluexport_api.sh -grscancelfailover SOURCE_VSI VG_NAME NO_DETACH|DETACH TARGET_VSI
# Failback GRS Volume Group (sync aux->master
#      and re-enable replication master->aux):            ./bluexport_api.sh -grsfailback SOURCE_VSI TARGET_VSI VG_NAME
#
#  SOURCE_VSI / TARGET_VSI:        Logical PowerVS instance names as defined in your JSON.
#  VG_NAME:                        Name for the Volume Group to create on the source workspace.
#  SOURCE_VOLUMES_NAME:            Common name/prefix to identify source VSI volumes (e.g. IBMiGRS).
#
# === VSI Operations ==="
# IPL VSI:                       ./bluexport_api.sh -vsistart VSI_NAME
#      Start a Virtual Server Instance. VSI must be in SHUTOFF status.
#
# VSI Operations:                ./bluexport_api.sh -vsioper VSI_NAME BOOT_MODE OPERATING_MODE
#      Set IBM i boot/operating mode for a VSI.
#      BOOT_MODE: a | b | c | d
#      OPERATING_MODE: normal | manual
#
# VSI Tasks:                     ./bluexport_api.sh -vsitask VSI_NAME TASK
#      Run an IBM i operation task on a VSI.
#      TASK: dston | retrydump | consoleservice | iopreset | remotedstoff |
#            remotedston | iopdump | dumprestart
#
# Monitor VSI SRC:               ./bluexport_api.sh -vsisrcmon VSI_NAME  START|SHUTOFF
#      START   -> Monitor until status=ACTIVE and SRC=00000000
#      SHUTOFF -> Monitor until status=SHUTOFF (SRC ignored)
#
# Attach volumes by common name: ./bluexport_api.sh -attachvolumes VOLUMES_COMMON_NAME VSI_NAME
#      Attach all volumes in the workspace whose name contains VOLUMES_COMMON_NAME.
#      VSI must be SHUTOFF. Volumes already attached are skipped.
# Detach ALL volumes from a VSI: ./bluexport_api.sh -detachvolumes VSI_NAME
#       Detach all volumes currently attached to the VSI. VSI must be SHUTOFF.
#
# === Examples ===
# Capture all volumes:           ./bluexport_api.sh -a vsiprd vsiprd_img image-catalog daily
# Capture excluding ASP2_:       ./bluexport_api.sh -x ASP2_ vsiprd vsiprd_img both monthly
# Capture excluding ASP2_ & iASPname:
#                                ./bluexport_api.sh -x "ASP2_ iASPname" vsiprd vsiprd_img both monthly
#
# Test mode (no capture):        ./bluexport_api.sh -tx ASP2_ vsiprd vsiprd_img both single
#
# Note: Recurrence "hourly" and "daily" only permits captures to image-catalog.
#
# Ricardo Martins - Blue Chip Portugal - 2025-2026
##########################################################################################
# Ensure required tools are in PATH (IBM i + Linux safe)
PATH="/QOpenSys/pkgs/bin:/QOpenSys/usr/bin:/usr/bin:${PATH}"
export PATH

       #####  START:CODE  #####

Version=1.7

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
	echo "`date +%Y-%m-%d_%H:%M:%S` - Config file $bluexscrt Missing!! Aborting!..."
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

    # Quebra linhas a cada 132 colunas
    wrapped=$(printf '%s\n' "$msg" | fold -w 377 -s)

    # Interactive (TTY) OR forced (IBM i batch)
    if [ -t 1 ] || [[ "${ECHOSCREEN_FORCE_STDOUT:-0}" == "1" ]]; then
        printf '%s\n' "$wrapped"
    fi

    if [[ "$flag" == "1" ]]; then
        printf '%s\n' "$wrapped" >> "$log_file"
    fi
}

#echoscreen() {
#	msg="$1"
#	flag="$2"
#
#	# Interactive (TTY) OR forced (IBM i batch)
#	if [ -t 1 ] || [[ "${ECHOSCREEN_FORCE_STDOUT:-0}" == "1" ]]; then
#		printf '%s\n' "$msg"
#	fi
#
#	if [[ "$flag" == "1" ]]; then
#		printf '%s\n' "$msg" >> "$log_file"
#	fi
#}
#### END:FUNCTION - Echo to log file and screen  ####

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



####  START: Constants Definition  #####
capture_time=`date +%Y-%m-%d_%H%M`
capture_date=`date +%Y-%m-%d`
capture_hour=`date "+%H"`
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

echoscreen ""
echoscreen "   ### Logging at $log_file" ""
echoscreen ""
fi


#### START: API Environment ###
#  authentication
header_json="Content-Type: application/json"
header_accept="Accept: application/json"
iam_token=$(curl -s -X POST "https://iam.cloud.ibm.com/identity/token" -H "Content-Type: application/x-www-form-urlencoded" -H "$header_accept" -d "grant_type=urn:ibm:params:oauth:grant-type:apikey&apikey=${api_key}" | jq -r '.access_token')
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


       #####  START: FUNCTIONS  #####

#### START:FUNCTION - Help  ####
help() {
	echoscreen ""
	echoscreen "Tool to Capture IBM Cloud PowerVS IBM i VSI and Export to COS and/or Image Catalog. Manage Snapshots, Volume Clones and GRS."
	echoscreen "Version: $Version"
	echoscreen ""
	echoscreen "=== === General === ==="
	echoscreen "Changing secret file:       ./bluexport_api.sh -chscrt bluexscrt_file_name   (use full path, e.g. /home/user/bluexscrt_new)"
	echoscreen "View secret file in use:    ./bluexport_api.sh -viewscrt"
	echoscreen ""
	echoscreen "Show help:                  ./bluexport_api.sh -h | --help | -help"
	echoscreen "Show version:               ./bluexport_api.sh -v | --version"
	echoscreen ""
	echoscreen "=== === Capture & Export === ==="
	echoscreen "Usage for all volumes:        ./bluexport_api.sh -a VSI_Name_to_Capture Capture_Image_Name both|image-catalog|cloud-storage hourly|daily|weekly|monthly|single"
	echoscreen "Usage for excluding volumes:  ./bluexport_api.sh -x volumes_name_to_exclude VSI_Name_to_Capture Capture_Image_Name both|image-catalog|cloud-storage hourly|daily|weekly|monthly|single"
	echoscreen "Usage for monitoring job:     ./bluexport_api.sh -j VSI_NAME IMAGE_NAME"
	echoscreen ""
	echoscreen "=== === Snapshots === ==="
	echoscreen "Create snapshot:            ./bluexport_api.sh -snapcr   VSI_NAME SNAPSHOT_NAME 0|[DESCRIPTION] 0|[VOLUMES(Comma separated list)]"
	echoscreen "Update snapshot:            ./bluexport_api.sh -snapupd  SNAPSHOT_NAME 0|[NEW_SNAPSHOT_NAME] 0|[DESCRIPTION]"
	echoscreen "Delete snapshot:            ./bluexport_api.sh -snapdel  SNAPSHOT_NAME"
	echoscreen "Restore snapshot:           ./bluexport_api.sh -snapres VSI_NAME SNAPSHOT_NAME"
	echoscreen "List all snapshots(all WS): ./bluexport_api.sh -snaplsall"
	echoscreen ""
	echoscreen "=== === Captured Images === ==="
	echoscreen "List all captured images"
	echoscreen " in all Workspaces:         ./bluexport_api.sh -imglsall"
	echoscreen "Delete image:               ./bluexport_api.sh -imgdel IMG_NAME"
	echoscreen ""
	echoscreen "=== === Cloud Object Storage (COS) === ==="
	echoscreen "List buckets for all COS instances: ./bluexport_api.sh -bucketslsall"
	echoscreen "List objects from a COS bucket:     ./bluexport_api.sh -bucketlsobjs"
	echoscreen "Delete object from a COS bucket:    ./bluexport_api.sh -bucketdelobj"
	echoscreen ""
	echoscreen "=== === Volume Clones === ==="
	echoscreen "Create volume clone:        ./bluexport_api.sh -vclone VOLUME_CLONE_NAME BASE_NAME LPAR_NAME True|False(replication-enabled) True|False(rollback-prepare) STORAGE_TIER ALL|(Comma separated Volumes name list to clone)"
	echoscreen "Delete volume clone:        ./bluexport_api.sh -vclonedel VOLUME_CLONE_NAME 0|delete_volumes"
	echoscreen "List volume clones(all WS): ./bluexport_api.sh -vclonelsall"
	echoscreen ""
	echoscreen "=== === Volume Tier === ==="
	echoscreen "Change volume tier:         ./bluexport_api.sh -vchtier VSI_NAME VOLUMES_NAME TIER_TO_CHANGE_TO"
	echoscreen ""
	echoscreen "=== === GRS (Global Replication Services) === ==="
	echoscreen "Create GRS Volume Group and onboard auxiliary volumes:"
	echoscreen "                            ./bluexport_api.sh -creategrs SOURCE_VSI TARGET_VSI VG_NAME SOURCE_VOLUMES_NAME"
	echoscreen "Delete GRS Volume Group and auxiliary volumes:"
	echoscreen "                            ./bluexport_api.sh -deletegrs SOURCE_VSI TARGET_VSI VG_NAME SOURCE_VOLUMES_NAME"
	echoscreen "Failover GRS Volume Group (activate target):"
	echoscreen "                            ./bluexport_api.sh -grsfailover SOURCE_VSI VG_NAME NO_ATTACH|ATTACH [TARGET_VSI]"
	echoscreen "Cancel GRS failover (start from master. Replication master->aux):"
	echoscreen "                            ./bluexport_api.sh -grscancelfailover SOURCE_VSI VG_NAME NO_DETACH|DETACH TARGET_VSI"
	echoscreen "Failback GRS Volume Group (sync aux->master and re-enable replication master->aux):"
	echoscreen "                            ./bluexport_api.sh -grsfailback SOURCE_VSI TARGET_VSI VG_NAME"
	echoscreen ""
	echoscreen "  SOURCE_VSI / TARGET_VSI:        Logical PowerVS instance names as defined in your JSON."
	echoscreen "  VG_NAME:                        Name for the Volume Group to create on the source workspace."
	echoscreen "  SOURCE_VOLUMES_NAME:            Common name/prefix to identify source VSI volumes (e.g. IBMiGRS)."
	echoscreen ""
	echoscreen "=== === VSI Operations === ==="
	echoscreen "IPL VSI:                    ./bluexport_api.sh -vsistart VSI_NAME"
	echoscreen "      Start a Virtual Server Instance. VSI must be in SHUTOFF status."
	echoscreen ""
	echoscreen "VSI Operations:             ./bluexport_api.sh -vsioper VSI_NAME BOOT_MODE OPERATING_MODE"
	echoscreen "      Set IBM i boot/operating mode for a VSI."
	echoscreen "      BOOT_MODE: a | b | c | d"
	echoscreen "      OPERATING_MODE: normal | manual"
	echoscreen ""
	echoscreen "VSI Tasks:                  ./bluexport_api.sh -vsitask VSI_NAME TASK"
	echoscreen "      Run an IBM i operation task on a VSI."
	echoscreen "      TASK: dston | retrydump | consoleservice | iopreset | remotedstoff |"
	echoscreen "            remotedston | iopdump | dumprestart"
	echoscreen ""
	echoscreen "Monitor VSI SRC:            ./bluexport_api.sh -vsisrcmon VSI_NAME START|SHUTOFF"
	echoscreen "      START   -> Monitor until VSI reaches ACTIVE and SRC 00000000"
	echoscreen "      SHUTOFF -> Monitor until VSI reaches SHUTOFF (SRC ignored)"
	echoscreen ""
	echoscreen "Attach volumes by common name: ./bluexport_api.sh -attachvolumes VOLUMES_COMMON_NAME VSI_NAME"
	echoscreen "      Attach all volumes in the workspace whose name contains VOLUMES_COMMON_NAME."
	echoscreen "      VSI must be SHUTOFF. Volumes already attached are skipped."
	echoscreen ""
	echoscreen "Detach ALL volumes from a VSI: ./bluexport_api.sh -detachvolumes VSI_NAME"
	echoscreen "      Detach all volumes currently attached to the VSI. VSI must be SHUTOFF."
        echoscreen ""
	echoscreen "=== === Examples === ==="
	echoscreen "Capture all volumes:        ./bluexport_api.sh -a vsiprd vsiprd_img image-catalog daily"
	echoscreen "Capture excluding ASP2_:    ./bluexport_api.sh -x ASP2_ vsiprd vsiprd_img both monthly"
	echoscreen "Capture excluding ASP2_ & iASPname:"
	echoscreen '                            ./bluexport_api.sh -x "ASP2_ iASPname" vsiprd vsiprd_img both monthly'
	echoscreen ""
	echoscreen "Test mode (no capture):     ./bluexport_api.sh -tx ASP2_ vsiprd vsiprd_img both single"
	echoscreen ""
	echoscreen "Note: Recurrence \"hourly\" and \"daily\" only permits captures to image-catalog."
	echoscreen ""
	echoscreen "Ricardo Martins - Blue Chip Portugal - 2025-2026"
	echoscreen ""
}
#### END:FUNCTION - Help  ####

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

#### START:FUNCTIONS - API Commands ####
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
	curl -sX DELETE "$base_url/pcloud/v2/cloud-instances/$CLOUD_INSTANCE_ID/pvm-instances/$PVM_ID/volumes" -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -d "{$ACTIONS}"
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
	curl -sX DELETE "$base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/volumes/$VOL_ID" -H "$header_auth" -H "CRN: $CRN" -H "$header_json"
}

vol_bdel() {
	curl -sX DELETE "$base_url/pcloud/v2/cloud-instances/$CLOUD_INSTANCE_ID/volumes" -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -d "{$ACTIONS}"
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
	curl -sX DELETE "$base_url/pcloud/v2/cloud-instances/$CLOUD_INSTANCE_ID/volumes-clone/$VOL_CLONE_ID" -H "$header_auth" -H "CRN: $CRN" -H "$header_json"
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
	curl -sX DELETE "$base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/volume-groups/$VOLUME_GROUP_ID" -H "$header_auth" -H "CRN: $CRN" -H "$header_json"
}

vg_upd() {
	curl -sX PUT "$base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/volume-groups/$VOLUME_GROUP_ID" -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -d "{$ACTIONS}"
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

img_del() {
	curl -sX DELETE $base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/images/$IMAGE_ID -H "$header_auth" -H "CRN: $CRN" -H "$header_json"
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

object_delete() {
	curl -sX DELETE https://s3.$REGION.cloud-object-storage.appdomain.cloud/$BUCKET/$KEY -H "$header_auth"
}

cos_ins_ls() {
	curl -sX GET https://resource-controller.cloud.ibm.com/v2/resource_instances?type=service_instance -H "$header_auth" -H "$header_accept"
}

cos_ls_buckets() {
	curl -sX GET https://s3.$REGION.cloud-object-storage.appdomain.cloud/ -H "$header_auth" -H "ibm-service-instance-id: $SERVICE_INSTANCE_ID"
}
#### END:FUNCTIONS - API Commands ####

#### START:FUNCTIONS - GRS Code Helpers ####
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
			vol_act 2>>"$log_file" | tee -a "$log_file" #>/dev/null
		fi
	done
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Replication check done." "1"
	if [[ "$flag" == "1" ]]
	then
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Some volumes had replicationEnabled=false and were changed to true. Rechecking until all are updated..." "1"
		sleep 10
		while true
		do
			if vol_ls | jq -r '.volumes[]? | "\(.name) \(.replicationEnabled)"' | grep -w "$vol_com_name" | grep false >/dev/null
			then
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
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Sleeping 180 seconds..." "1"
                sleep 180
        done
}

## Helper: monitor onboarding status until completion
chk_on_status() {
	while true
	do
		on_status=$(on_get | jq -r '.status' 2>>"$log_file")
		if [[ "$on_status" == "RUNNING" ]]
		then
			on_progress=$(on_get | jq -r '.progress' 2>>"$log_file")
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
	# Look for an image whose name contains both $vsi and $old_img
	local img_json
	img_json=$(img_ls 2>>"$log_file")
	img_id_old=$(echo "$img_json" | jq -r \
		--arg vsi "$vsi" \
		--arg old "$old_img" '
		.images[]?
		| select((.name | contains($vsi)) and (.name | contains($old)))
		| .imageID
	' 2>>"$log_file" | head -n1)
	img_name_old=$(echo "$img_json" | jq -r \
		--arg vsi "$vsi" \
		--arg old "$old_img" '
		.images[]?
		| select((.name | contains($vsi)) and (.name | contains($old)))
		| .name
	' 2>>"$log_file" | head -n1)
	# --- COS (Object Storage) via list_object() ---
	# list_object() returns XML (S3 ListBucketResult). We parse <Key>...</Key> lines.
	local list_xml
	list_xml=$(list_object 2>>"$log_file")
	# Previous export object (old_img)
	objstg_img=$(echo "$list_xml" | \
		awk -v vsi="$vsi" -v old="$old_img" '
			match($0, /<Key>([^<]+)<\/Key>/, m) {
				key = m[1]
				if (index(key, vsi) > 0 && index(key, old) > 0) {
					print key
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
		img_del 2>>"$log_file" | tee -a "$log_file"
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
			object_delete 2>>"$log_file" | tee -a "$log_file"
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
	CRN="$shortnamecrn"
	PVM_ID="$vsi_id"
	CLOUD_INSTANCE_ID=$(jq -r --arg ws "$vsiwsshort" '.workspaces[$ws].id' "$bluexscrt")
	ins_ls | jq -r --arg pvmid "$PVM_ID" '.pvmInstances[] | select(.pvmInstanceID == $pvmid) | "\(.pvmInstanceID) \(.serverName)"'# > "$vsi_list_id_tmp" 2>> "$log_file"
	vsi_id=$(grep -wi "$vsi" "$vsi_list_id_tmp" | awk '{print $1}')
	if [[ -z "$vsi_id" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Instance $vsi exists in your config file ($bluexscrt), but does not exist on IBM Cloud. Please update the JSON config!"
	fi
	awk '{print $2}' "$vsi_list_id_tmp" > "$vsi_list_tmp"
}
####  END:FUNCTION - Target DC and List all VSI in the POWERVS DC and Get VSI Name and ID  ####

####  START:FUNCTION - Monitor Capture and Export Job  ####
job_monitor() {
  # Get Capture & Export Job ID
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Job log in file $job_log" "1"
	if [ "$flagj" -eq 1 ]
	then
        	# Reuse existing job mapping from operid_file: <capture_name> <job_id>
		job_id=$(awk -v name="$capture_name" '$1 == name {print $2; exit}' "$operid_file")
		if [[ -z "$job_id" ]]; then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - No Job ID found for capture $capture_name in $operid_file"
		fi
	else
		if [[ -z "$job_id" ]]
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - Capturing instance $vsi has failed, see log file!"
		fi
		echo "$capture_name $job_id" >> "$operid_file"
	fi
  # Check Capture & Export Job Status
	echo "Job Monitoring of VM Capture $capture_name - Job ID: $job_id" >> "$job_log"
	operation_before=""
	while true
	do
		JOB_ID="$job_id"
		# Get current job JSON once and reuse
		job_json=$(job_get)
		# Save job output:
		#  - overwrite $job_monitor with the latest state
		#  - append to $job_log and $log_file for history
		printf '%s\n' "$job_json" | tee "$job_monitor" >>"$job_log"
		job_status=$(jq -r '.status.state // empty'    "$job_monitor")
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
				delete_previous_img
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
		elif [[ -z "$job_status" ]]
		then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - FAILED Getting Job ID or no Job Running!" "1"
			abort "$(date +%Y-%m-%d_%H:%M:%S) - Check file $job_monitor for more details."
		elif [[ "$job_status" == "queued" ]]
		then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Job ID $job_id Status: ${job_status^^}" "1"
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Message: $message" "1"
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Waiting for Operation Change... Operation Running Now: ${operation^^}" "1"
			echo "$(date +%Y-%m-%d_%H:%M:%S) - Running ${operation^^}... Sleeping 60 seconds..." >> "$job_log"
			sleep 60
			operation_before="$operation"
		elif [[ "$job_status" == "failed" ]]
		then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Job ID $job_id Status: ${job_status^^}" "1"
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Message: $message" "1"
			abort "$(date +%Y-%m-%d_%H:%M:%S) - Job Failed, check message!!"
		else
			if [[ "$operation" != "$operation_before" ]]
			then
        		        echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Job ID $job_id Status: ${job_status^^}" "1"
	        	       	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Message: $message" "1"
        	        	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Waiting for Operation Change... Operation Running Now: ${operation^^}" "1"
	                	echo "$(date +%Y-%m-%d_%H:%M:%S) - Running ${operation^^}... Sleeping 60 seconds..." >> "$job_log"
		                sleep 60
        		        operation_before="$operation"
			else
        		        echo "$(date +%Y-%m-%d_%H:%M:%S) - Still Running ${operation^^}... Sleeping 60 seconds..." >> "$job_log"
                		sleep 60
			fi
		fi
	done
}
####  END:FUNCTION - Monitor Capture and Export Job  ####

####  START:FUNCTION - Get iASP name  ####
get_iASP_name() {
	vsi_status=$(ins_get | jq -r '.status')
	shutoff=0
	if [ $test -eq 0 ]
	then
		vsi_ip=$(jq -r --arg name "$vsi" '.systems[] | select((.name | ascii_downcase) == ($name | ascii_downcase)) | .ip' "$bluexscrt")
		if [[ -z "$vsi_ip" || "$vsi_ip" == "null" ]]
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - VSI $vsi not found in JSON systems[] section. Aborting..."
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
						abort "$(date +%Y-%m-%d_%H:%M:%S) - Cannot ping VSI $vsi at $vsi_ip ! Aborting..."
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
				abort "$(date +%Y-%m-%d_%H:%M:%S) - Unable to SSH to $vsi! Try STRTCPSVR *SSHD. Aborting..."
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
	# Case-insensitive check if VSI exists in JSON
	if jq -e --arg vsi "$vsi" 'any(.systems[]; (.name | ascii_downcase) == ($vsi | ascii_downcase))' "$bluexscrt" > /dev/null
	then
		# Get workspace short name (e.g., WSMAD2) for this VSI (case-insensitive)
		vsiwsshort=$(jq -r --arg vsi "$vsi" '.systems[]	| select((.name | ascii_downcase) == ($vsi | ascii_downcase)) | .workspace' "$bluexscrt")
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
		abort "   ### VSI $vsi not found in any of the workspaces available in $bluexscrt!"
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
			system "CHGASPACT ASPDEV(*SYSBAS) OPTION(*FRCWRT)" >> "$log_file" 2>&1
			if [[ -n "$iasp_names" ]]
			then
				for iasp_name in $iasp_names
				do
					echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Flushing Memory to Disk for $iasp_name ..." "1"
					system "CHGASPACT ASPDEV($iasp_name) OPTION(*FRCWRT)" >> "$log_file" 2>&1
				done
			fi
		else
			# Remote via SSH
			ssh -T -i "$sshkeypath" "$vsi_user@$vsi_ip" 'system "CHGASPACT ASPDEV(*SYSBAS) OPTION(*FRCWRT)"' >> "$log_file" | tee -a "$log_file"
			if [[ $? -ne 0 ]]
			then
				abort "$(date +%Y-%m-%d_%H:%M:%S) - ERRO: ligação SSH falhou ou deu timeout, abortando..."
			fi
			if [[ -n "$iasp_names" ]]
			then
				for iasp_name in $iasp_names
				do
					echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Flushing Memory to Disk for $iasp_name ..." "1"
					ssh -T -i "$sshkeypath" "$vsi_user@$vsi_ip" "system \"CHGASPACT ASPDEV($iasp_name) OPTION(*FRCWRT)\"" >> "$log_file" | tee -a "$log_file"
					if [[ $? -ne 0 ]]
					then
						abort "$(date +%Y-%m-%d_%H:%M:%S) - ERRO: ligação SSH falhou ou deu timeout, abortando..."
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
	flush_asps
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
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Could not list instance volumes via API. Check log above this line..."
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
				abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Volume '$vtrim' not found on VSI $vsi. Use exact Volume Name or Volume ID."
			fi
			json_ids="$json_ids\"$vol_id\","
		done
		# remover última vírgula
		json_ids="${json_ids%,}"
		if [[ -z "$json_ids" ]]
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - No valid volumes resolved from '$volumes_to_snap'."
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
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Error calling snapshot create API. Check log above this line..."
	fi

	# Verificar se veio algum erro no JSON
	if echo "$resp" | jq -e '.error? // .errors? | length > 0' >/dev/null 2>&1
	then
		echo "$resp" | jq >>"$log_file"
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Snapshot creation returned error. Check log above this line..."
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
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Could not retrieve snapshot ID for $snap_name. Check IBM Cloud portal / API."
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
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Error reading snapshot status from API."
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
		abort "$(date +%Y-%m-%d_%H:%M:%S) - INTERNAL ERROR - No fields to update for snapshot $snap_name (ACTIONS empty)."
	fi
	ACTIONS="$actions"
	if [[ -z "$SNAP_ID" ]]; then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - INTERNAL ERROR - SNAP_ID not set before do_snap_update."
	fi
	local resp
	resp=$(snap_upd 2>>"$log_file")
	if [ $? -ne 0 ] || [[ -z "$resp" ]]; then
		echo "$resp" >>"$log_file"
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Error calling snapshot update API. Check log above this line..."
	fi
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Snapshot $snap_name updated $new_name_echo $new_description_echo - Done!" "1"
}
####  END:FUNCTION - Do the Snapshot Update  ####

####  START:FUNCTION - Do the Snapshot Restore  ####
do_snap_restore() {
	# 1) Confirmar estado da VSI antes de fazer restore
	vsi_status=$(ins_get 2>>"$log_file" | jq -r '.status // empty' 2>>"$log_file")
	if [[ -z "$vsi_status" || "$vsi_status" == "null" ]]; then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Could not retrieve VSI status for $vsi (PVM_ID $PVM_ID). Aborting snapshot restore."
	fi
	# Regra: SÓ fazemos restore se estiver SHUTOFF
	if [[ "$vsi_status" != "SHUTOFF" ]]; then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - VSI $vsi is in status $vsi_status. Snapshot restore is only allowed when VSI is SHUTOFF."
	fi
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - VSI $vsi is in status: $vsi_status. Proceeding with snapshot restore..." "1"
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Searching Snapshot with name $snap_name for VSI $vsi (PVM_ID $PVM_ID) in current workspace..." "1"
	# 2) List snapshots in this workspace
	snaps_json=$(snap_ls 2>>"$log_file")
	if [[ -z "$snaps_json" ]]; then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Could not list snapshots in current workspace. Check log file $log_file."
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
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Snapshot with name $snap_name for VSI $vsi (PVM_ID $PVM_ID) not found in this workspace."
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
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - curl error calling snapshot restore API. Check log file $log_file."
	fi

	# Confirmar que é JSON válido
	if ! echo "$restore_output" | jq . >/dev/null 2>&1; then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Snapshot restore API did not return valid JSON. Raw output logged above."
	fi

	# Verificar erros no JSON: .error/.errors/.code
	has_error_fields="no"
	if echo "$restore_output" | jq -e '.error? // .errors? | length > 0' >/dev/null 2>&1; then
		has_error_fields="yes"
	fi
	err_code=$(echo "$restore_output" | jq -r '.code // empty' 2>>"$log_file")
	err_msg=$(echo "$restore_output" | jq -r '.message // empty' 2>>"$log_file")
	if [[ "$has_error_fields" == "yes" ]] || { [[ -n "$err_code" ]] && [[ "$err_code" != "0" ]] && [[ "$err_code" != "200" ]]; }; then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Snapshot restore API returned an error (code=$err_code, message=\"$err_msg\"). Check log file $log_file."
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
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Error reading snapshot status during restore monitoring."
		fi
		# Ler status e percentComplete do snapshot específico
		snap_status=$(echo "$snaps_json" | jq -r --arg id "$SNAP_ID" '.snapshots // [] | .[] | select(.snapshotID == $id) | .status // empty' 2>>"$log_file")

		snap_percent=$(echo "$snaps_json" | jq -r --arg id "$SNAP_ID" '.snapshots // [] | .[] | select(.snapshotID == $id) | .percentComplete // 0' 2>>"$log_file")
		if [[ -z "$snap_status" || "$snap_status" == "null" ]]
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Snapshot ID $SNAP_ID not found in list while monitoring restore."
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
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Snapshot '$snap_name' does not exist. Choose another name or use -snapcr to create one."
	fi
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Snapshot '$snap_name' found with ID: $snap_id" "1"
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Executing delete for snapshot ID $snap_id ..." "1"
	SNAP_ID=$snap_id
	resp=$(snap_del 2>>"$log_file")
	# Check API response
	if echo "$resp" | grep -q '"error"'
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED deleting snapshot '$snap_name'. API error: $resp"
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
	abort "$(date +%Y-%m-%d_%H:%M:%S) - WARNING: Snapshot delete requested but snapshot still appears in list. Check IBM Cloud."
}
####  END:FUNCTION - Do the Snapshot Delete  ####

####  START:FUNCTION - Do the Volume Clone Execute ####
do_volume_clone_execute() {
	# Flush ASPs na origem antes de executar o clone
	if [[ $shutoff == "0" ]]
	then
		flush_asps
	fi
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - == Executing Volume Clone with name $vclone_name ..." "1"
	if [[ -z "$vclone_id" ]]; then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - vclone_id not set before do_volume_clone_execute."
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
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Error executing Volume Clone $vclone_name (API call failed or empty response)."
	fi
	# 2) response must be valid JSON (otherwise jq will blow up later)
	if ! echo "$resp_ex" | jq . >/dev/null 2>&1
	then
		echo "$resp_ex" >>"$log_file"
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Volume Clone execute returned non-JSON response. Check log for raw payload."
	fi
	# 3) if API returned an error payload (e.g., {"code":400,"message":"..."}) abort immediately
	api_code=$(echo "$resp_ex" | jq -r '.code // empty' 2>>"$log_file")
	api_msg=$(echo "$resp_ex" | jq -r '.message // .error // empty' 2>>"$log_file")

	if [[ -n "$api_code" && "$api_code" != "null" ]]
	then
		echo "$resp_ex" >>"$log_file"
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Volume Clone execute API error (code=$api_code): $api_msg"
	fi

	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Waiting for Volume Clone $vclone_name execution to finish..." "1"
	local vcloneex_percent=0
	local vcloneex_percent_before=0
	while :
	do
		sleep 5
		local status_json
		status_json=$(vol_cl_get 2>>"$log_file")
		if [ $? -ne 0 ] || [ -z "$status_json" ]
		then
			echo "$status_json" >>"$log_file"
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Error getting status for Volume Clone execution $vclone_name."
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
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - vclone_id not set before do_volume_clone_start."
	fi
	VOL_CLONE_ID="$vclone_id"
	local resp_start
	resp_start=$(vol_cl_st 2>>"$log_file")
	if [ $? -ne 0 ]
	then
		echo "$resp_start" >>"$log_file"
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Error starting Volume Clone $vclone_name (API call failed)."
	fi
	local status_json
	status_json=$(vol_cl_get 2>>"$log_file")
	if [ $? -ne 0 ] || [ -z "$status_json" ]
	then
		echo "$status_json" >>"$log_file"
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Error reading status after start for Volume Clone $vclone_name."
	fi
	local vclone_start_action vclone_start_status
	vclone_start_action=$(echo "$status_json" | jq -r '.action // .status.action // empty')
	vclone_start_status=$(echo "$status_json" | jq -r '.status // .state // .status.state // empty')
	if [[ "$vclone_start_action" == "start" && "$vclone_start_status" == "available" ]]
	then
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Volume Clone $vclone_name Started and ready to execute..." "1"
	else
		echo "$status_json" >>"$log_file"
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Volume Clone $vclone_name not in expected state after start (action=$vclone_start_action status=$vclone_start_status)."
	fi
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
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Could not retrieve Volume Clone Request ID for $vclone_name. Check the log above this line..."
		fi
		vclone_percent=0
		while [ "$vclone_percent" -lt 100 ]
		do
			vclone_percent_before=$vclone_percent
			sleep 5
			vclone_percent=$(vol_cl_ls 2>>"$log_file" | jq -r --arg id "$vclone_id" '.volumesClone[]? | select(.volumesCloneID == $id) | .percentComplete // 0')
			# Garantir valor numérico
			[ -z "$vclone_percent" ] && vclone_percent=0
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
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Error creating Volume Clone Request $vclone_name (API call failed). See $log_file for details."
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
		abort "$(date +%Y-%m-%d_%H:%M:%S) - VSI ID missing or VSI Name '$vsi' not found in $bluexscrt. Please add it to the JSON or check the name."
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
		abort "$(date +%Y-%m-%d_%H:%M:%S) - There are no volumes with any of these words \"${volchtier_names[*]}\" in instance $vsi_cloud_name"
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
		resp=$(vol_act 2>&1 | tee -a "$log_file")
		echo "$resp" > "$vol_failed_tst"
		# 1º caso especial: já está no mesmo tier -> NÃO é erro "a sério"
		if echo "$resp" | grep -q "current storage tier"
		then
			same_tier=1
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Volume $vol_name ($vol) is already in tier $tier, no change required." "1"
		# 2º qualquer outro erro com campo "error" -> erro real
		elif echo "$resp" | grep -q '"error"'
		then
			api_error=1
		echo "$resp" >> "$vol_ch_tier"
		fi
	done
	failed_vol=$(grep -B2 Failed "$vol_ch_tier" | grep Performing | awk '{print $5}')
	if [[ -n "$failed_vol" || $api_error -ne 0 ]]
	then
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Some volumes failed to change tier!" "1"
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Try changing the tier manually with the following commands..." "1"
		for vol in $failed_vol
		do
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - vol_act for volume ID: $vol change to tier $tier" "1"
		done
		abort "`date +%Y-%m-%d_%H:%M:%S` - Tier change finished, but there were errors! Please check the log above..."
	fi
	if [ $same_tier -eq 1 ]
	then
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Some volumes were already in tier $tier, no action done on those volumes!" "1"
	fi
	abort "`date +%Y-%m-%d_%H:%M:%S` - Tier change finished successfully!"
}
####  END:FUNCTION  Change Instance Volumes Tier  ####

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
		abort "`date +%Y-%m-%d_%H:%M:%S` - No volumes attached to source VSI $source_vsi. Aborting GRS creation."
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
	resp_vg=$(vg_cr 2>>"$log_file")
	echo "$resp_vg" >>"$log_file"
	# Confirmar ID do VG
	VOLUME_GROUP_ID=$(vg_ls | jq -r --arg vg_name "$vg_name" '.volumeGroups[]? | select(.name == $vg_name) | .id' 2>>"$log_file")
	if [[ -z "$VOLUME_GROUP_ID" || "$VOLUME_GROUP_ID" == "null" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Could not find Volume Group ID for $vg_name after creation."
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
			abort "`date +%Y-%m-%d_%H:%M:%S` - VG $vg_name did not reach expected aux volume count ($vol_count) after $max_wait_loops minutes. Aborting."
		fi

		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Waiting for VG $vg_name aux volumes to match source count... Sleeping 60 seconds..." "1"
		sleep 60
	done
	if [[ -z "$auxvol_names" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - No auxiliary volumes found in remote-copy relationships for $vg_name after waiting. Aborting."
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
		abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Could not retrieve consistencyGroupName for VG $vg_name."
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
	resp_on=$(on_cr 2>>"$log_file")
	echo "$resp_on" >>"$log_file"
	# Se a API devolver um objeto com campo .code (ex.: 400), abortamos
	if echo "$resp_on" | jq -e '.code? != null' >/dev/null 2>&1
	then
		errmsg=$(echo "$resp_on" | jq -r '.message // .error // "Unknown error"' 2>/dev/null)
		abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Error creating volume onboarding: $errmsg"
	fi
	VOLUME_ONBOARDING_ID=$(on_ls | jq -r --arg desc "$ondesc" '[.onboardings[]? | select(.description == $desc)][-1].id' 2>>"$log_file")
	if [[ -z "$VOLUME_ONBOARDING_ID" || "$VOLUME_ONBOARDING_ID" == "null" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Could not find onboarding ID for description $ondesc."
	fi
	if [[ -z "$VOLUME_ONBOARDING_ID" || "$VOLUME_ONBOARDING_ID" == "null" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Could not find onboarding ID for description $ondesc."
	fi
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Onboarding request ID: $VOLUME_ONBOARDING_ID" "1"
	# 2.11 – Monitor onboarding
	chk_on_status
	# 2.12 – Validar Volume Group no TARGET (mesmo consistencyGroupName)
	VOLUME_GROUP_ID=$(vg_ls | jq -r --arg cgname "$cgname" '.volumeGroups[]? | select(.consistencyGroupName == $cgname) | .id' 2>>"$log_file")
	if [[ -z "$VOLUME_GROUP_ID" || "$VOLUME_GROUP_ID" == "null" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Onboarding finished, but target Volume Group with consistencyGroupName $cgname not found."
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
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Volume Group $vg_name not found in source workspace. Aborting GRS delete."
	fi
	cgname=$(echo "$vg_json" | jq -r --arg vg "$vg_name" '
		.volumeGroups[]? | select(.name == $vg) | .consistencyGroupName
	' 2>>"$log_file")
	if [[ -z "$cgname" || "$cgname" == "null" ]]; then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Could not retrieve consistencyGroupName for VG $vg_name in source workspace."
	fi
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Source VG $vg_name has ID $VOLUME_GROUP_ID and consistencyGroupName $cgname." "1"
	# 1.1 Remover volumes do VG (source)
	src_vol_ids=$(vol_ls 2>>"$log_file" | jq -r --arg prefix "$vol_com_name" '
		.volumes[]? | select(.name | startswith($prefix)) | .volumeID
	')
	if [[ -z "$src_vol_ids" ]]; then
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - No source volumes found with prefix $vol_com_name to remove from VG $vg_name. Continuing..." "1"
	else
		local json_ids=""
		for vid in $src_vol_ids; do
			json_ids="$json_ids\"$vid\","
		done
		json_ids="${json_ids%,}"
		ACTIONS="\"removeVolumes\":[${json_ids}]"
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Removing source volumes from VG $vg_name: [${json_ids}]..." "1"
		vg_upd 2>>"$log_file" | tee -a "$log_file" #>/dev/null
		# 1.2 Esperar o VG ficar em estado empty
		while true
		do
			local vg_state
			vg_state=$(vg_sd 2>>"$log_file" | jq -r '.state // empty')
			if [[ "$vg_state" == "empty" ]]; then
				echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Source Volume Group $vg_name is in state 'empty'." "1"
				break
			fi
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Source VG $vg_name still in state '$vg_state'. Waiting 30 seconds..." "1"
			sleep 30
		done
	fi
	# 1.3 Apagar o VG no source
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Deleting source Volume Group $vg_name..." "1"
	vg_del 2>>"$log_file" | tee -a "$log_file" #>/dev/null
	# 1.4 Desativar replication nos volumes de origem (sem os apagar)
	if [[ -n "$src_vol_ids" ]]; then
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Disabling replication on source volumes with prefix $vol_com_name..." "1"
		for vid in $src_vol_ids
		do
			VOL_ID="$vid"
			ACTIONS='"replicationEnabled": false'
			vol_act 2>>"$log_file" | tee -a "$log_file" #>/dev/null
		done
		# Esperar até todos ficarem replicationEnabled=false
		while true
		do
			if vol_ls 2>>"$log_file" | jq -r --arg prefix "$vol_com_name" '
				.volumes[]? | select(.name | startswith($prefix)) | .replicationEnabled
			' | grep -q true
			then
				echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Some source volumes still have replicationEnabled=true. Waiting 10 seconds..." "1"
				sleep 10
			else
				echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - All source volumes with prefix $vol_com_name now have replicationEnabled=false." "1"
				break
			fi
		done
	else
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - No source volumes to disable replication for (prefix $vol_com_name)." "1"
	fi
	####################################
	# 2. TARGET WORKSPACE / TARGET VG  #
	####################################
	base_url="$target_base_url"
	CRN="$target_ws_crn"
	CLOUD_INSTANCE_ID="$target_CLOUD_INSTANCE_ID"
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Working on TARGET workspace for VSI $target_vsi..." "1"
	vg_json=$(vg_ls 2>>"$log_file")
	VOLUME_GROUP_ID=$(echo "$vg_json" | jq -r --arg cg "$cgname" '
		.volumeGroups[]? | select(.name | startswith($cg)) | .id
	' 2>>"$log_file")
	if [[ -z "$VOLUME_GROUP_ID" || "$VOLUME_GROUP_ID" == "null" ]]; then
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Target Volume Group for consistencyGroupName $cgname not found. Skipping VG delete on target." "1"
	else
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Target VG found with ID $VOLUME_GROUP_ID (name starts with $cgname)." "1"
		# 2.1 Remover auxiliary volumes do VG no target
		# Usamos o mesmo prefixo vol_com_name, tal como no source,
		# porque os volumes auxiliares mantêm o padrão (ex.: IBMiGRS)
		tg_vol_ids=$(vol_ls 2>>"$log_file" | jq -r --arg prefix "$vol_com_name" '
			.volumes[]? 
			| select(.name | contains($prefix)) 
			| .volumeID
			')
		if [[ -z "$tg_vol_ids" ]]
		then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - No target volumes found with pattern $vol_com_name to remove from VG. Continuing..." "1"
		else
			local tg_json_ids=""
			for vid in $tg_vol_ids
			do
				tg_json_ids="$tg_json_ids\"$vid\","
			done
			tg_json_ids="${tg_json_ids%,}"
			ACTIONS="\"removeVolumes\":[${tg_json_ids}]"
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Removing target volumes from VG (CG: $cgname): [${tg_json_ids}]..." "1"
			vg_upd 2>>"$log_file" | tee -a "$log_file" #>/dev/null
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
	ins_vol_bdet 2>>"$log_file" | tee -a "$log_file" #>/dev/null
	# Esperar até não haver volumes anexados
	while true
	do
		local attached
		attached=$(ins_vol_ls 2>>"$log_file" | jq -r '.volumes[]? | .name' 2>/dev/null)
		if [[ -z "$attached" ]]; then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - No volumes attached to target VSI $target_vsi." "1"
			break
		fi
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Target VSI $target_vsi still has attached volumes. Waiting 30 seconds..." "1"
		sleep 30
	done
	# SAFETY CHECK – ensure aux volumes are NOT replicationEnabled
	unsafe_aux=""
	for vid in $tg_vol_ids
	do
		VOL_ID="$vid"
		rep_enabled=$(vol_get 2>>"$log_file" | jq -r '.replicationEnabled // "false"')
		if [[ "$rep_enabled" == "true" ]]
		then
			unsafe_aux="$unsafe_aux $vid"
		fi
	done
	if [[ -n "$unsafe_aux" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Some target (aux) volumes still have replicationEnabled=true: $unsafe_aux. Aborting GRS delete to avoid impacting primary volumes."
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
		vol_bdel 2>>"$log_file" | tee -a "$log_file" #>/dev/null
	else
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - No auxiliary volumes to delete on target with name $tgvol_com_name." "1"
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
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Source Volume Group $vg_name not found in source workspace $source_ws_name. Aborting failover."
	fi
	local cgname
	cgname=$(echo "$vg_json" | jq -r --arg vg "$vg_name" '.volumeGroups[]? | select(.name == $vg) | .consistencyGroupName' 2>>"$log_file")
	if [[ -z "$cgname" || "$cgname" == "null" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Could not retrieve consistencyGroupName for source VG $vg_name (workspace $source_ws_name)."
	fi
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Source workspace: $source_ws_name (id=$source_cloud_instance_id_local) - Source VG ID=$source_vg_id - consistencyGroupName=$cgname" "1"

	# Identify BOOT auxiliary volume name (from SOURCE VSI attached volumes list)
	local boot_aux_name
	boot_aux_name=$(ins_vol_ls 2>>"$log_file" | jq -r '.volumes[]? | select(.bootable == true) | .auxVolumeName // empty' 2>>"$log_file" | head -n1)
	if [[ -z "$boot_aux_name" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Could not determine boot auxiliary volume name from source VSI $source_vsi. Aborting."
	fi
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Boot auxiliary volume name (from source): $boot_aux_name" "1"

	# Collect ALL auxiliary volume names for this VG (from SOURCE VG remote-copy relationships)
	VOLUME_GROUP_ID="$source_vg_id"
	local aux_names
	aux_names=$(vg_rcr 2>>"$log_file" | jq -r '.remoteCopyRelationships[]? | select(.primaryRole=="master") | .auxVolumeName' 2>>"$log_file")
	if [[ -z "$aux_names" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Could not retrieve auxiliary volumes from remote-copy relationships for source VG $vg_name. Aborting."
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
		local found_id
		found_id=$(echo "$vg_tmp" | jq -r --arg cg "$cgname" '.volumeGroups[]? | select(.consistencyGroupName == $cg) | .id' 2>>"$log_file" | head -n1)

		if [[ -n "$found_id" && "$found_id" != "null" ]]
		then
			target_ws_key="$ws"
			target_ws_name=$(jq -r --arg k "$ws" '.workspaces[$k].name' "$bluexscrt")
			target_ws_crn="$ws_crn"
			target_cloud_instance_id="$CLOUD_INSTANCE_ID"
			target_base_url="$base_url"
			target_vg_id="$found_id"
			break
		fi
	done

	if [[ -z "$target_vg_id" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Could not find target Volume Group with consistencyGroupName $cgname in any other configured workspace. Aborting failover."
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
	resp_act=$(vg_act 2>>"$log_file")
	echo "$resp_act" >>"$log_file"
	if ! echo "$resp_act" | jq . >/dev/null 2>&1
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - vg_act did not return valid JSON when activating target. Raw output logged."
	fi
	if echo "$resp_act" | jq -e '.code? != null or .error? != null' >/dev/null 2>&1
	then
		errmsg=$(echo "$resp_act" | jq -r '.message // .error // .description // "Unknown error"' 2>/dev/null)
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Error activating target VG (stop access): $errmsg"
	fi

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
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Could not read target VG storage-details/state while waiting for failover."
		fi
		i=$((i + 1))
		if (( i >= max_wait ))
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Target VG did not reach state 'idling' after $max_wait minutes (last state=$t_state)."
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
		abort "$(date +%Y-%m-%d_%H:%M:%S) - TARGET_VSI is required when using ATTACH mode. Syntax: bluexport_api.sh -grsfailover SOURCE_VSI VG_NAME ATTACH TARGET_VSI"
	fi

	# Resolve TARGET_VSI context (must be in the same workspace we just found)
	vsi="$target_vsi"
	vsi_id_bluexscrt
	check_locally_VSI_exists
	local target_pvm_id_local="$PVM_ID"

	if [[ "$shortnamecrn" != "$target_ws_crn" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - TARGET_VSI $target_vsi is not in the target workspace where the VG was activated ($target_ws_name). Aborting attach to avoid cross-workspace mistakes."
	fi

	# Map aux volume NAMES -> volumeIDs in TARGET workspace
	local target_vols_json
	target_vols_json=$(vol_ls 2>>"$log_file")
	if [[ -z "$target_vols_json" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Could not list volumes in target workspace $target_ws_name."
	fi

	local boot_vol_id
	boot_vol_id=$(echo "$target_vols_json" | jq -r --arg n "$boot_aux_name" '.volumes[]? | select(.name == $n) | .volumeID' 2>>"$log_file" | head -n1)
	if [[ -z "$boot_vol_id" || "$boot_vol_id" == "null" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Could not resolve boot auxiliary volume name $boot_aux_name to a volumeID in target workspace $target_ws_name."
	fi

	# Attach boot volume first
	ACTIONS="\"volumeIDs\":[\"$boot_vol_id\"]"
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Attaching BOOT volume to TARGET_VSI $target_vsi (volumeID=$boot_vol_id, name=$boot_aux_name)..." "1"
	resp_att_boot=$(vol_att_multi 2>>"$log_file")
	echo "$resp_att_boot" >>"$log_file"
	if echo "$resp_att_boot" | jq -e '.code? != null or .error? != null' >/dev/null 2>&1
	then
		errmsg=$(echo "$resp_att_boot" | jq -r '.message // .error // .description // "Unknown error"' 2>/dev/null)
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Error attaching boot volume to $target_vsi: $errmsg"
	fi

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
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Boot volume ($boot_aux_name / $boot_vol_id) did not become attached/visible on $target_vsi after ~10 minutes. Aborting."
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
		local vid
		vid=$(echo "$target_vols_json" | jq -r --arg n "$aux_name" '.volumes[]? | select(.name == $n) | .volumeID' 2>>"$log_file" | head -n1)
		if [[ -z "$vid" || "$vid" == "null" ]]
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Could not resolve auxiliary volume name $aux_name to a volumeID in target workspace $target_ws_name."
		fi
		json_ids="$json_ids\"$vid\","
	done
	json_ids="${json_ids%,}"

	if [[ -n "$json_ids" ]]
	then
		ACTIONS="\"volumeIDs\":[${json_ids}]"
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Attaching remaining auxiliary volumes to TARGET_VSI $target_vsi..." "1"
		resp_att=$(vol_att_multi 2>>"$log_file")
		echo "$resp_att" >>"$log_file"
		if echo "$resp_att" | jq -e '.code? != null or .error? != null' >/dev/null 2>&1
		then
			errmsg=$(echo "$resp_att" | jq -r '.message // .error // .description // "Unknown error"' 2>/dev/null)
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Error attaching auxiliary volumes to $target_vsi: $errmsg"
		fi
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
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Could not read attached volumes count on TARGET_VSI $target_vsi while waiting for volume attaches."
		fi

		if (( tgt_count >= expected_attached ))
		then
			break
		fi
		att_try=$((att_try + 1))
		if (( att_try >= max_attach_wait ))
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - TARGET_VSI $target_vsi did not reach $expected_attached attached volumes after ~10 minutes (last count=$tgt_count)."
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
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Source Volume Group $vg_name not found in source workspace $source_ws_name. Aborting cancel failover."
	fi
	local cgname
	cgname=$(echo "$vg_json" | jq -r --arg vg "$vg_name" '.volumeGroups[]? | select(.name == $vg) | .consistencyGroupName' 2>>"$log_file")
	if [[ -z "$cgname" || "$cgname" == "null" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Could not retrieve consistencyGroupName for source VG $vg_name (workspace $source_ws_name)."
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
		local found_id
		found_id=$(echo "$vg_tmp" | jq -r --arg cg "$cgname" '.volumeGroups[]? | select(.consistencyGroupName == $cg) | .id' 2>>"$log_file" | head -n1)

		if [[ -n "$found_id" && "$found_id" != "null" ]]
		then
			target_ws_key="$ws"
			target_ws_name=$(jq -r --arg k "$ws" '.workspaces[$k].name' "$bluexscrt")
			target_ws_crn="$ws_crn"
			target_cloud_instance_id="$CLOUD_INSTANCE_ID"
			target_base_url="$base_url"
			target_vg_id="$found_id"
			break
		fi
	done

	if [[ -z "$target_vg_id" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Could not find target Volume Group with consistencyGroupName $cgname in any other configured workspace. Aborting cancel failover."
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
		abort "$(date +%Y-%m-%d_%H:%M:%S) - TARGET_VSI $target_vsi is not in the target workspace ($target_ws_name) where the VG exists. Aborting to avoid cross-workspace mistakes."
	fi

	# Switch API context to TARGET workspace for volume checks/detach
	base_url="$target_base_url"
	CRN="$target_ws_crn"
	CLOUD_INSTANCE_ID="$target_cloud_instance_id"

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
			resp_det=$(ins_vol_bdet 2>>"$log_file")
			echo "$resp_det" >>"$log_file"
			if ! echo "$resp_det" | jq . >/dev/null 2>&1
			then
				abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - ins_vol_bdet did not return valid JSON when detaching volumes. Raw output logged."
			fi
			if echo "$resp_det" | jq -e '.code? != null or .error? != null' >/dev/null 2>&1
			then
				errmsg=$(echo "$resp_det" | jq -r '.message // .error // .description // "Unknown error"' 2>/dev/null)
				abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Error detaching volumes from $target_vsi: $errmsg"
			fi

			# Wait until no volumes are attached
			while true
			do
				local attached_now
				attached_now=$(ins_vol_ls 2>>"$log_file" | jq -r '.volumes[]? | .name' 2>>"$log_file")
				if [[ -z "$attached_now" ]]
				then
					echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - All volumes detached from TARGET_VSI $target_vsi." "1"
					break
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
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Could not read SOURCE VG storage-details/state before stop."
	fi
	if [[ "$s_state_pre" == "idling" ]]
	then
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - SOURCE VG is already in state 'idling' (stopped). Skipping stop.access=true." "1"
	else
		ACTIONS='"stop":{"access":true}'
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Cancel Failover step: VG action stop.access=true on SOURCE VG $source_vg_id..." "1"
		resp_stop=$(vg_act 2>>"$log_file")
		echo "$resp_stop" >>"$log_file"
		if ! echo "$resp_stop" | jq . >/dev/null 2>&1
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - vg_act did not return valid JSON (stop access). Raw output logged."
		fi
		if echo "$resp_stop" | jq -e '.code? != null or .error? != null' >/dev/null 2>&1
		then
			errmsg=$(echo "$resp_stop" | jq -r '.message // .error // .description // "Unknown error"' 2>/dev/null)
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Error stopping SOURCE VG (stop access): $errmsg"
		fi
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
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Could not read SOURCE VG storage-details/state while waiting for stop."
		fi
		i=$((i + 1))
		if (( i >= max_wait ))
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - SOURCE VG did not reach state 'idling' after $max_wait minutes (last state=$s_state)."
		fi
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - SOURCE VG state is '$s_state'. Waiting 60 seconds..." "1"
		sleep 60
	done

	# Step B: start with source=master (per IBM docs)
	ACTIONS='"start":{"source":"master"}'
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Cancel Failover step: VG action start.source=master on SOURCE VG $source_vg_id..." "1"
	resp_start=$(vg_act 2>>"$log_file")
	echo "$resp_start" >>"$log_file"
	if ! echo "$resp_start" | jq . >/dev/null 2>&1
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - vg_act did not return valid JSON (start master). Raw output logged."
	fi
	if echo "$resp_start" | jq -e '.code? != null or .error? != null' >/dev/null 2>&1
	then
		errmsg=$(echo "$resp_start" | jq -r '.message // .error // .description // "Unknown error"' 2>/dev/null)
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Error starting SOURCE VG as master: $errmsg"
	fi

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
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Could not read SOURCE VG storage-details/state while waiting for consistent_copying."
		fi
		i=$((i + 1))
		if (( i >= max_wait ))
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - SOURCE VG did not reach state 'consistent_copying' after $max_wait minutes (last state=$state_now)."
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
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - TARGET VG did not reach replicationStatus=enabled after $t_max_wait minutes (last replicationStatus=$t_rep, state=$t_state)."
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
		abort "$(date +%Y-%m-%d_%H:%M:%S) - SOURCE_VSI $source_vsi and TARGET_VSI $target_vsi are in the same workspace ($source_ws_name). Failback requires two different workspaces."
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
		abort "$(date +%Y-%m-%d_%H:%M:%S) - SOURCE_VSI $source_vsi is not SHUTOFF (current: $s_status). Stop it before running -grsfailback."
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
		abort "$(date +%Y-%m-%d_%H:%M:%S) - TARGET_VSI $target_vsi is not SHUTOFF (current: $t_status). Stop it before running -grsfailback."
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
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Could not list volume groups in source workspace $source_ws_name."
	fi

	local source_vg_id
	source_vg_id=$(echo "$vg_json" | jq -r --arg vg "$vg_name" '.volumeGroups[]? | select(.name == $vg) | .id' 2>>"$log_file")
	if [[ -z "$source_vg_id" || "$source_vg_id" == "null" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Source Volume Group $vg_name not found in source workspace $source_ws_name. Aborting failback."
	fi

	local cgname
	cgname=$(echo "$vg_json" | jq -r --arg vg "$vg_name" '.volumeGroups[]? | select(.name == $vg) | .consistencyGroupName' 2>>"$log_file")
	if [[ -z "$cgname" || "$cgname" == "null" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Could not retrieve consistencyGroupName for source VG $vg_name (workspace $source_ws_name)."
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
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Could not list volume groups in target workspace $target_ws_name."
	fi

	local target_vg_id
	target_vg_id=$(echo "$t_vg_json" | jq -r --arg cg "$cgname" '.volumeGroups[]? | select(.consistencyGroupName == $cg) | .id' 2>>"$log_file" | head -n1)
	if [[ -z "$target_vg_id" || "$target_vg_id" == "null" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Target Volume Group with consistencyGroupName $cgname not found in target workspace $target_ws_name. Aborting failback."
	fi
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Target workspace: $target_ws_name (id=$target_cloud_instance_id_local) - Target VG ID=$target_vg_id" "1"

	##############################################
	# 3) TARGET: start.source=aux (sync aux -> master)
	##############################################
	VOLUME_GROUP_ID="$target_vg_id"
	ACTIONS='"start":{"source":"aux"}'
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Step 4.1: Synchronizing I/O updates from AUX to MASTER (target VG action start.source=aux)..." "1"
	resp_act=$(vg_act 2>>"$log_file")
	echo "$resp_act" >>"$log_file"
	if ! echo "$resp_act" | jq . >/dev/null 2>&1
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - vg_act did not return valid JSON in Step 4.1. Raw output logged."
	fi
	if echo "$resp_act" | jq -e '.code? != null or .error? != null' >/dev/null 2>&1
	then
		errmsg=$(echo "$resp_act" | jq -r '.message // .error // .description // "Unknown error"' 2>/dev/null)
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Step 4.1 failed: $errmsg"
	fi

	# Monitor until state=consistent_copying and primaryRole=aux
	local max_wait=60
	local i=0
	while true
	do
		local t_state
		t_state=$(vg_sd 2>>"$log_file" | jq -r '.state // empty' 2>>"$log_file")
		local t_primary
		t_primary=$(vg_get 2>>"$log_file" | jq -r '.primaryRole // empty' 2>>"$log_file")

		if [[ -z "$t_state" ]]
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Could not read target VG state while monitoring Step 4.1."
		fi

		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Target VG status: state=$t_state, primaryRole=${t_primary:-UNKNOWN}" "1"

		if [[ "$t_state" == "consistent_copying" && "$t_primary" == "aux" ]]
		then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Target VG reached state 'consistent_copying' with primaryRole 'aux'." "1"
			break
		fi

		i=$((i + 1))
		if (( i >= max_wait ))
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Target VG did not reach state consistent_copying with primaryRole=aux after $max_wait minutes (last: state=$t_state, primaryRole=$t_primary)."
		fi
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Waiting 60 seconds..." "1"
		sleep 60
	done

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
		resp_act=$(vg_act 2>>"$log_file")
		echo "$resp_act" >>"$log_file"
		if ! echo "$resp_act" | jq . >/dev/null 2>&1
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - vg_act did not return valid JSON in Step 4.2. Raw output logged."
		fi
		if echo "$resp_act" | jq -e '.code? != null or .error? != null' >/dev/null 2>&1
		then
			errmsg=$(echo "$resp_act" | jq -r '.message // .error // .description // "Unknown error"' 2>/dev/null)
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Step 4.2 failed: $errmsg"
		fi
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
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Could not read source VG replicationStatus while monitoring Step 4.2."
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
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Source VG replicationStatus did not reach 'disabled' after $max_wait minutes (last: $rep_status)."
		fi
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Waiting 60 seconds..." "1"
		sleep 60
	done

	##############################################
	# 5) SOURCE: start.source=master (re-enable replication)
	##############################################
	ACTIONS='"start":{"source":"master"}'
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Step 4.3: Re-enabling replication on SOURCE VG (VG action start.source=master)..." "1"
	resp_act=$(vg_act 2>>"$log_file")
	echo "$resp_act" >>"$log_file"
	if ! echo "$resp_act" | jq . >/dev/null 2>&1
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - vg_act did not return valid JSON in Step 4.3. Raw output logged."
	fi
	if echo "$resp_act" | jq -e '.code? != null or .error? != null' >/dev/null 2>&1
	then
		errmsg=$(echo "$resp_act" | jq -r '.message // .error // .description // "Unknown error"' 2>/dev/null)
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Step 4.3 failed: $errmsg"
	fi

	# Wait for replicationStatus=enabled and state=consistent_copying on SOURCE VG
	i=0
	while true
	do
		local rep_status
		rep_status=$(vg_get 2>>"$log_file" | jq -r '.replicationStatus // empty' 2>>"$log_file")
		s_state=$(vg_sd 2>>"$log_file" | jq -r '.state // empty' 2>>"$log_file")

		if [[ -z "$rep_status" || -z "$s_state" ]]
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Could not read source VG status while monitoring Step 4.3."
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
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Source VG did not reach replicationStatus=enabled and state=consistent_copying after $max_wait minutes (last: state=$s_state, replicationStatus=$rep_status)."
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
			abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Could not read target VG status while monitoring replication re-enable."
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

#### START:FUNCTION - Start VSI (do_start_vsi) ####
do_start_vsi() {
	local vsi="$1"
	if [[ -z "$vsi" ]]; then
		abort "`date +%Y-%m-%d_%H:%M:%S` - VSI_NAME is missing. Syntax: bluexport_api.sh -vsistart VSI_NAME"
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
		abort "`date +%Y-%m-%d_%H:%M:%S` - VSI $vsi is not in SHUTOFF status (current: $vsi_status). Aborting start."
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
		abort "`date +%Y-%m-%d_%H:%M:%S` - VSI_NAME, BOOT_MODE and OPERATING_MODE are mandatory. Syntax: bluexport_api.sh -vsioper VSI_NAME BOOT_MODE OPERATING_MODE"
	fi
	# Validate BOOT_MODE
	case "$boot_mode" in
		a|b|c|d) ;;
		*) abort "`date +%Y-%m-%d_%H:%M:%S` - Invalid BOOT_MODE '$boot_mode'. Valid values: a, b, c, d." ;;
	esac
	# Validate OPERATING_MODE
	case "$operating_mode" in
		manual|normal) ;;
		*) abort "`date +%Y-%m-%d_%H:%M:%S` - Invalid OPERATING_MODE '$operating_mode'. Valid values: normal, manual." ;;
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
		abort "`date +%Y-%m-%d_%H:%M:%S` - VSI_NAME and TASK are mandatory. Syntax: bluexport_api.sh -vsitask VSI_NAME TASK"
	fi
	case "$task" in
		dston|retrydump|consoleservice|iopreset|remotedstoff|remotedston|iopdump|dumprestart)
			;;
		*)
			abort "`date +%Y-%m-%d_%H:%M:%S` - Invalid TASK '$task'. Valid values: dston, retrydump, consoleservice, iopreset, remotedstoff, remotedston, iopdump, dumprestart."
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
		abort "`date +%Y-%m-%d_%H:%M:%S` - VSI_NAME or MODE is missing. Syntax: bluexport_api.sh -vsisrcmon VSI_NAME START|SHUTOFF"
	fi

	mode_u=$(echo "$mode" | tr '[:lower:]' '[:upper:]')
	if [[ "$mode_u" != "START" && "$mode_u" != "SHUTOFF" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Invalid MODE '$mode'. Use START or SHUTOFF. Syntax: bluexport_api.sh -vsisrcmon VSI_NAME START|SHUTOFF"
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

	while true
	do
		vsi_json=$(ins_get 2>>"$log_file")
		if [[ -z "$vsi_json" ]]
		then
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - WARNING: Could not retrieve VSI status/SRC. Retrying in 30 seconds..." "1"
			sleep 30
			continue
		fi

		vsi_status=$(echo "$vsi_json" | jq -r '.status // "UNKNOWN"' 2>>"$log_file")
		# srcs is an array-of-array, like: "srcs": [[{ "src": "00000000", ... }]]
		vsi_src=$(echo "$vsi_json" | jq -r '.srcs[0][0].src // "UNKNOWN"' 2>>"$log_file")

		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - VSI $vsi_name - Status: $vsi_status, SRC: $vsi_src" "1"

		if [[ "$mode_u" == "SHUTOFF" ]]
		then
			# SHUTOFF mode: ignore SRC as a completion condition
			if [[ "$vsi_status" == "SHUTOFF" ]]
			then
				abort "`date +%Y-%m-%d_%H:%M:%S` - === VSI $vsi_name reached status SHUTOFF. SRC monitoring completed. ==="
			fi

			sleep 30
			continue
		fi

		##############################################
		# START mode
		##############################################
		# If not ACTIVE yet, just keep waiting (SHUTOFF here is normal while starting)
		if [[ "$vsi_status" != "ACTIVE" ]]
		then
			sleep 30
			continue
		fi

		# VSI is ACTIVE at this point
		if [[ "$vsi_src" != "00000000" ]]
		then
			# SRC is rolling
			saw_nonzero=1
			stable_zero=0
			sleep 30
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
			sleep 30
			continue
		fi

		# We have NOT observed any non-zero SRC yet (avoid false-positive: ACTIVE + 00000000 too early)
		if [ "$first_active_ts" -eq 0 ]
		then
			first_active_ts=$(date +%s)
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - VSI $vsi_name reached ACTIVE with SRC=00000000. Waiting up to ${grace_seconds}s to detect SRC rolling before declaring START completed..." "1"
			sleep 30
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
do_vsi_attach_volumes() {
	local vol_common_name="$1"
	local vsi_name="$2"

	if [[ -z "$vol_common_name" || -z "$vsi_name" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Arguments missing!! Syntax: bluexport_api.sh -attachvolumes VOLUMES_COMMON_NAME VSI_NAME"
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
		abort "`date +%Y-%m-%d_%H:%M:%S` - VSI $vsi_name is not SHUTOFF (current: $vsi_status). Stop it before running -attachvolumes."
	fi

	# Current volumes already attached to this VSI
	local attached_ids
	attached_ids=$(ins_vol_ls 2>>"$log_file" | jq -r '.volumes[]? | .volumeID' 2>>"$log_file" | tr '\n' ' ')

	# Get all volumes in workspace matching common name (contains)
	local match_lines
	match_lines=$(vol_ls 2>>"$log_file" | jq -r --arg p "$vol_common_name" '.volumes[]? | select(.name | contains($p)) | "\(.volumeID) \(.name)"' 2>>"$log_file")
	if [[ -z "$match_lines" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - No volumes found in workspace $shortnamecrn with name containing '$vol_common_name'. Nothing to attach."
	fi

	# Build list to attach (exclude already attached)
	local ids_json=""
	local attach_count=0
	local names_to_attach=""
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
		if [[ -n "$ids_json" ]]
		then
			ids_json="$ids_json,\"$vid\""
		else
			ids_json="\"$vid\""
		fi
		attach_count=$((attach_count + 1))
		names_to_attach="$names_to_attach $vname"
	done <<< "$match_lines"

	if [[ $attach_count -eq 0 ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - All volumes matching '$vol_common_name' are already attached to VSI $vsi_name. Nothing to do."
	fi

	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Volumes to attach ($attach_count):$names_to_attach" "1"

	ACTIONS="\"volumeIDs\":[${ids_json}]"
	local resp_att
	resp_att=$(vol_att_multi 2>>"$log_file")
	echo "$resp_att" >>"$log_file"
	if echo "$resp_att" | jq -e '.code? != null or .error? != null or .description? != null' >/dev/null 2>&1
	then
		errmsg=$(echo "$resp_att" | jq -r '.message // .error // .description // "Unknown error"' 2>/dev/null)
		abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Error attaching volumes to $vsi_name: $errmsg"
	fi

	# Wait for attach completion (async)
	local expected_min
	expected_min=$(( $(echo "$attached_ids" | wc -w) + attach_count ))
	if [[ -z "$expected_min" || "$expected_min" -le 0 ]]
	then
		expected_min=$attach_count
	fi

	local max_wait=60
	local i=0
	while true
	do
		local cur_count
		cur_count=$(ins_vol_ls 2>>"$log_file" | jq -r '.volumes | length' 2>>"$log_file")
		if [[ -z "$cur_count" || "$cur_count" == "null" ]]
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Could not read attached volumes count while waiting for attaches."
		fi
		if (( cur_count >= expected_min ))
		then
			break
		fi
		i=$((i + 1))
		if (( i >= max_wait ))
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - VSI $vsi_name did not reach $expected_min attached volumes after ~10 minutes (last count=$cur_count)."
		fi
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Volumes still attaching on $vsi_name... currently $cur_count/$expected_min attached. Waiting 10 seconds (attempt $i/$max_wait)" "1"
		sleep 10
	done

	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - === Successfully requested attach of $attach_count volumes to VSI $vsi_name. ===" "1"
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
		abort "`date +%Y-%m-%d_%H:%M:%S` - VSI_NAME is missing. Syntax: bluexport_api.sh -detachvolumes VSI_NAME"
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
		abort "`date +%Y-%m-%d_%H:%M:%S` - VSI $vsi_name is not SHUTOFF (current: $vsi_status). Stop it before running -detachvolumes."
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
		abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Error detaching volumes from $vsi_name: $errmsg"
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
			abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Could not read attached volumes count while waiting for detaches."
		fi
		if (( cur_count == 0 ))
		then
			break
		fi
		i=$((i + 1))
		if (( i >= max_wait ))
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - VSI $vsi_name still has $cur_count attached volumes after ~10 minutes."
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
		abort "`date +%Y-%m-%d_%H:%M:%S` - IMG_NAME is missing. Syntax: bluexport_api.sh -imgdel IMG_NAME"
	fi
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - === Starting Image Delete for $img_name in all Workspaces ===" "1"
	# Vamos construir os arrays de workspaces e o mapa curto->nome completo
	IFS=':' read -r -a wsnames_array <<< "$wsnames"
	read -r -a allws_array <<< "$allws"
	declare -A wsmap
	local i
	for i in "${!allws_array[@]}"
	do
		wsmap[${allws_array[i]}]="${wsnames_array[i]}"
	done
	local IMAGE_ID=""
	local found_ws=""
	local found_ws_name=""
	# Percorrer todas as workspaces definidas
	for ws in "${allws_array[@]}"
	do
		CRN=$(jq -r --arg ws "$ws" '.workspaces[$ws].crn' "$bluexscrt")
		CLOUD_INSTANCE_ID=$(jq -r --arg ws "$ws" '.workspaces[$ws].id' "$bluexscrt")
		full_ws_name="${wsmap[$ws]}"
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
		IMAGE_ID=$(echo "$imgs_json" | jq -r --arg name "$img_name" '.images[]? | select(.name == $name) | .imageID' 2>>"$log_file" | head -n1)
		if [[ -n "$IMAGE_ID" && "$IMAGE_ID" != "null" ]]
		then
			found_ws="$ws"
			found_ws_name="$full_ws_name"
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Image $img_name found in Workspace $found_ws_name with ID: $IMAGE_ID" "1"
			break
		fi
	done
	if [[ -z "$IMAGE_ID" || "$IMAGE_ID" == "null" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Image with name $img_name not found in any Workspace."
	fi
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Calling Image Delete API for $img_name (ID $IMAGE_ID) in Workspace $found_ws_name..." "1"
	# Chamar API de delete na workspace onde foi encontrada
	del_output=$(img_del 2>>"$log_file")
	ret=$?
	echo "$del_output" >> "$log_file"
	# Verificar exit code e possível payload de erro
	if [ $ret -ne 0 ] || echo "$del_output" | jq -e '.code? != null' >/dev/null 2>&1
	then
		errmsg=$(echo "$del_output" | jq -r '.message // .error // "Unknown error"' 2>/dev/null)
		abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Error calling image delete API for $img_name: $errmsg"
	fi
	abort "`date +%Y-%m-%d_%H:%M:%S` - === Image $img_name (ID $IMAGE_ID) deleted successfully from Workspace $found_ws_name. ==="
}
#### END:FUNCTION - Delete Image (do_img_delete) ####

       ####  END - FUNCTIONS  ####

####  START: Iniciate Log and Validate Arguments  ####
timestamp=$(date +%F" "%T" "%Z)
echo "==== START ======= $timestamp =========" | tee -a $log_file
echo "Flags Used: $@" | tee -a $log_file
if [ $# -eq 0 ]
then
	help
	abort "`date +%Y-%m-%d_%H:%M:%S` - No arguments supplied!!"
fi

case $1 in
   -h | --help | -help)
	help
	abort "`date +%Y-%m-%d_%H:%M:%S` - Help requested!!"
    ;;

   -j)
	if [ $# -lt 3 ]
	then
		echoscreen "Flag -j selected, but Arguments Missing!! Syntax: bluexport_api.sh -j VSI_NAME IMAGE_NAME"
		abort "`date +%Y-%m-%d_%H:%M:%S` - Flag -j selected, but Arguments Missing!! Syntax: bluexport_api.sh -j VSI_NAME IMAGE_NAME"
	fi
	if [ $# -gt 3 ]
	then
		echoscreen "Flag -j selected, but too many arguments!! Syntax: bluexport_api.sh -j VSI_NAME IMAGE_NAME"
		abort "`date +%Y-%m-%d_%H:%M:%S` - Flag -j selected, but too many arguments!! Syntax: bluexport_api.sh -j VSI_NAME IMAGE_NAME"
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
		abort "`date +%Y-%m-%d_%H:%M:%S` - Arguments Missing!! Syntax: bluexport_api.sh $1 VSI_NAME IMAGE_NAME EXPORT_LOCATION [daily|weekly|monthly|single]"
	fi
	if [ $# -gt 5 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport_api.sh $1 VSI_NAME IMAGE_NAME EXPORT_LOCATION [daily|weekly|monthly|single]"
	fi
	destination=$4
	capture_img_name=${3^^}
	capture_name=$capture_img_name"_"$capture_time
	if [[ $5 == "hourly" ]] || [[ $5 == "daily" ]]
	then
		if [[ $destination == "both" ]] || [[ $destination == "cloud-storage" ]]
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` - Destination $destination is not valid with hourly and daily parameter!! Only image-catalog is possible."
		fi
		if [[ $5 == "hourly" ]]
		then
			old_img=$(date --date '1 hour ago' "+_%H")
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
		abort "`date +%Y-%m-%d_%H:%M:%S` - Reocurrence must be weekly or monthly or single!"
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
		abort "`date +%Y-%m-%d_%H:%M:%S` - Export Destination $destination is NOT valid!"
	fi
	volumes_cmd="ins_vol_ls | jq -r '.volumes[] | \"\(.volumeID) \(.name)\"'"
    ;;

   -x | -tx)
	if [ $# -lt 6 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Arguments Missing!! Syntax: bluexport_api.sh $1 EXCLUDE_NAME VSI_NAME IMAGE_NAME EXPORT_LOCATION [daily|weekly|monthly|single]"
	fi
	if [ $# -gt 6 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport_api.sh $1 EXCLUDE_NAME VSI_NAME IMAGE_NAME EXPORT_LOCATION [daily|weekly|monthly|single]"
	fi
	capture_img_name=${4^^}
	capture_name=$capture_img_name"_"$capture_time
	if [[ $6 == "hourly" ]] || [[ $6 == "daily" ]]
	then
		if [[ $destination == "both" ]] || [[ $destination == "cloud-storage" ]]
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` - Destination $destination is not valid with hourly and daily parameter!! Only image-catalog is possible."
		fi
		if [[ $6 == "hourly" ]]
		then
			old_img=$(date --date '1 hour ago' "+%H")
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
		abort "`date +%Y-%m-%d_%H:%M:%S` - Reocurrence must be weekly or monthly or single!"
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
	destination=$5
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Export Destination: $destination" "1"
	if [[ $destination == "both" ]] || [[ $destination == "image-catalog" ]] || [[ $destination == "cloud-storage" ]]
	then
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Export Destination $destination is valid!" "1"
	else
		abort "`date +%Y-%m-%d_%H:%M:%S` - Export Destination $destination is NOT valid!"
	fi
	volumes_cmd="ins_vol_ls | jq -r --arg re \"$exclude_names_regex\" '.volumes[] | select(.name | test(\$re; \"i\") | not) | \"\(.volumeID) \(.name)\"'"
    ;;

  -vchtier)
	tier="tier$4"
	test=0
	flagj=1
	if [ $# -lt 4 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments missing! Syntax: bluexport_api.sh $1 VSI_NAME VOLUMES_NAME TIER_TO_CHANGE_TO"
	fi
	if [ $# -gt 4 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments! Syntax: bluexport_api.sh $1 VSI_NAME VOLUMES_NAME TIER_TO_CHANGE_TO"
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
	vchtier
    ;;

  -insvchtier)
	tier="tier$3"
	test=0
	flagj=1
	if [ $# -lt 3 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments missing! Syntax: bluexport_api.sh $1 VSI_NAME TIER_TO_CHANGE_TO"
	fi
	if [ $# -gt 3 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments! Syntax: bluexport_api.sh $1 VSI_NAME TIER_TO_CHANGE_TO"
	fi
	vsi=$2
	vsi_id_bluexscrt
	check_locally_VSI_exists
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Changing ALL volumes of VSI $vsi_cloud_name to tier $tier..." "1"
	ins_vol_ls | jq -r '.volumes[]? | "\(.volumeID) \(.name)"' > "$volumes_file" 2>>"$log_file"
	volumes=$(awk '{print $1}' "$volumes_file" | paste -sd, -)
	volumes_name=$(awk '{print $2}' "$volumes_file" | tr '\n' ' ')
	vchtier
    ;;


   -chscrt)
	# Modo 1: foi passado um caminho diretamente: -chscrt /path/bluexscrt_xxx.json
	if [ $# -ge 2 ]
	then
		if [ $# -gt 2 ]
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport_api.sh -chscrt bluexscrt_file_name  (use full path, e.g. /home/user/bluexscrt_new.json)"
		fi
		new_scrt="$2"
		if [ ! -f "$new_scrt" ]
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` - Secret file $new_scrt does not exist. Aborting..."
		fi
		jq --arg new "$new_scrt" '.bluexscrt = $new' "$conf_file" > "$conf_file.tmp" && mv "$conf_file.tmp" "$conf_file"
		abort "`date +%Y-%m-%d_%H:%M:%S` - Secret file changed to $new_scrt !"
	fi
	# Modo 2: sem argumentos → lista e pergunta qual usar
	scrt_dir=$(dirname "$bluexscrt")
	echoscreen ""
	echoscreen "### Available secret files in $scrt_dir (pattern: bluexscrt*.json):"
	shopt -s nullglob
	scrt_files=("$scrt_dir"/bluexscrt*.json)
	if [ ${#scrt_files[@]} -eq 0 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - No secret files found (pattern: bluexscrt*.json)."
	fi
	index=1
	current_index=0
	for f in "${scrt_files[@]}"
	do
		if [[ "$f" == "$bluexscrt" ]]
		then
			marker="(in use)"
			current_index=$index
		else
			marker=""
		fi
		# ⚙️ Aqui é onde sai exatamente como queres:
		printf "[%s] %s %s\n" "$index" "$f" "$marker"
		index=$((index + 1))
	done
	echo ""
	printf "### Select the secret file to use [1-%d]: " "${#scrt_files[@]}"
	read choice
	# Validar escolha
	if ! [[ "$choice" =~ ^[0-9]+$ ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Invalid selection (not a number)."
	fi
	if (( choice < 1 || choice > ${#scrt_files[@]} ))
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Invalid selection (out of range)."
	fi
	new_scrt="${scrt_files[$((choice-1))]}"
	jq --arg new "$new_scrt" '.bluexscrt = $new' "$conf_file" > "$conf_file.tmp" && mv "$conf_file.tmp" "$conf_file"
	abort "`date +%Y-%m-%d_%H:%M:%S` - Secret file changed to $new_scrt !"
     ;;

  -viewscrt)
    if [ $# -gt 1 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport_api.sh $1"
	fi
	scrt_in_use=$(jq -r '.bluexscrt' "$conf_file")
	abort "`date +%Y-%m-%d_%H:%M:%S` - Secret file in use is $scrt_in_use"
    ;;

  -snapcr)
	# Args: VSI_NAME SNAPSHOT_NAME 0|"DESCRIPTION" 0|[VOLUMES (comma separated names or IDs)]
	if [ $# -lt 5 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments Missing!! Syntax: bluexport_api.sh $1 LPAR_NAME SNAPSHOT_NAME 0|\"DESCRIPTION\" 0|[Comma separated Volumes name list to snap]"
	fi
	if [ $# -gt 5 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments!! Syntax: bluexport_api.sh $1 LPAR_NAME SNAPSHOT_NAME 0|\"DESCRIPTION\" 0|[Comma separated Volumes name list to snap]"
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
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Already exists one Snapshot with name $snap_name for VSI $vsi (PVM_ID $PVM_ID), please choose a different name or use flag -snapupd to change the name."
	fi
	# Argumento DESCRIPTION: 0 ou frase entre aspas
	description_arg="$4"
	if [ -n "$description_arg" ] && [ "$description_arg" -eq "$description_arg" ] 2>/dev/null
	then
		if [ "$description_arg" -eq 0 ]
		then
			snap_description=""
		else
			abort "$(date +%Y-%m-%d_%H:%M:%S) - Argument DESCRIPTION must be 0 or a phrase inside quotes!! Syntax: bluexport_api.sh $1 LPAR_NAME SNAPSHOT_NAME 0|[\"DESCRIPTION\"] 0|[VOLUMES - Comma separated Volumes name list to snap]"
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
			abort "$(date +%Y-%m-%d_%H:%M:%S) - Argument VOLUMES must be 0 or comma separated names or IDs!! Syntax: bluexport_api.sh $1 LPAR_NAME SNAPSHOT_NAME 0|[\"DESCRIPTION\"] 0|[VOLUMES - Comma separated Volumes name list to snap]"
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
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments Missing!! Syntax: bluexport_api.sh $1 SNAPSHOT_NAME 0|[NEW_SNAPSHOT_NAME] 0|[\"DESCRIPTION\"]"
	fi
	if [ $# -gt 4 ]
	then
	abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments!! Syntax: bluexport_api.sh $1 SNAPSHOT_NAME 0|[NEW_SNAPSHOT_NAME] 0|[\"DESCRIPTION\"]"
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
		abort "$(date +%Y-%m-%d_%H:%M:%S) - You must pass at least one flag, DESCRIPTION or NEW_SNAPSHOT_NAME!..."
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
				abort "$(date +%Y-%m-%d_%H:%M:%S) - Argument NEW_SNAPSHOT_NAME must be 0 or a name!! Syntax: bluexport_api.sh $1 SNAPSHOT_NAME 0|[NEW_SNAPSHOT_NAME] 0|[\"DESCRIPTION\"]"
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
				abort "$(date +%Y-%m-%d_%H:%M:%S) - Argument DESCRIPTION must be 0 or a phrase inside quotes!! Syntax: bluexport_api.sh $1 SNAPSHOT_NAME 0|[NEW_SNAPSHOT_NAME] 0|[\"DESCRIPTION\"]"
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
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Snapshot with name $snap_name does not exist in any configured workspace. Use -snapcr to create one."
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
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments Missing!! Syntax: bluexport_api.sh $1 VSI_NAME SNAPSHOT_NAME"
	fi
	if [ $# -gt 2 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments!! Syntax: bluexport_api.sh $1 VSI_NAME SNAPSHOT_NAME"
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
                # Check if there are snapshots
                if ! echo "$snaps_json" | jq -e '.snapshots | length > 0' >/dev/null 2>&1
		then
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Snapshot with name $snap_name doesn't exists in Workspace $full_ws_name, moving on to next Workspace!" "1"
			continue
		else
			do_snap_delete
		fi
	done
    ;;

  -snapres)
	# Syntax: bluexport_api.sh -snapres VSI_NAME SNAPSHOT_NAME
	if [ $# -lt 3 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments Missing!! Syntax: bluexport_api.sh $1 VSI_NAME SNAPSHOT_NAME"
	fi
	if [ $# -gt 3 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments!! Syntax: bluexport_api.sh $1 VSI_NAME SNAPSHOT_NAME"
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
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments!! Syntax: bluexport_api.sh $1"
	fi
	test=0
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - === Starting listing all snapshots in all workspaces!" "1"
	# Convert wsnames from colon-separated string → array
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

  -imglsall)
	if [ $# -gt 1 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments!! Syntax: bluexport_api.sh $1"
	fi
	test=0
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - === Starting Listing all Captured Images in all Workspaces !" "1"
	# Convert 'wsnames' string to an array (built antes a partir do JSON)
	IFS=':' read -r -a wsnames_array <<< "$wsnames"
	# Convert 'allws' string to an array (built antes a partir do JSON)
	read -r -a allws_array <<< "$allws"
	# Map workspace short name -> full name
	declare -A wsmap
	for i in "${!allws_array[@]}"
	do
		wsmap[${allws_array[i]}]="${wsnames_array[i]}"
	done
	for ws in "${allws_array[@]}"
	do
		# Get CRN and Workspace ID from JSON
		CRN=$(jq -r --arg ws "$ws" '.workspaces[$ws].crn' "$bluexscrt")
		CLOUD_INSTANCE_ID=$(jq -r --arg ws "$ws" '.workspaces[$ws].id'  "$bluexscrt")
		region_api=$(jq -r --arg k "$ws" '.workspaces[$k].crn | capture("power-iaas:(?<region>[^:]+)") | .region | gsub("-"; "_")' "$bluexscrt")
		base_url_var="base_${region_api}"
		base_url="${!base_url_var}"
		full_ws_name="${wsmap[$ws]}"
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
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many or too few arguments!! Syntax: bluexport_api.sh -imgdel IMG_NAME"
	fi
	img_name="$2"
	do_img_delete "$img_name"
    ;;

  -vclonelsall)
	# Too many arguments?
	if [ $# -gt 1 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments!! Syntax: bluexport_api.sh $1"
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
		full_ws_name="${wsmap[$ws]}"
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
	# Args: VOLUME_CLONE_NAME BASE_NAME LPAR_NAME Replication(True|False) Rollback(True|False) TARGET_TIER volumes(ALL|id1,id2,...)
	if [ $# -lt 8 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments Missing!! Syntax: bluexport_api.sh $1 VOLUME_CLONE_NAME BASE_NAME LPAR_NAME (Replication)True|False (Rollback)True|False TARGET_STORAGE_TIER ALL|VOLUMES(Comma separated Volumes ID list to clone)"
	fi
	if [ $# -gt 8 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments!! Syntax: bluexport_api.sh $1 VOLUME_CLONE_NAME BASE_NAME LPAR_NAME (Replication)True|False (Rollback)True|False TARGET_STORAGE_TIER ALL|VOLUMES(Comma separated Volumes ID list to clone)"
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
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Replication value must be True or False...!"
	fi
	if [[ "$rollback" != "true" && "$rollback" != "false" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Rollback value must be True or False...!"
	fi
	# Validar tier
	if [[ "$target_tier" != "tier0" && "$target_tier" != "tier1" && "$target_tier" != "tier3" && "$target_tier" != "tier5k" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Target Tier must be tier0 or tier1 or tier3 or tier5k...!"
	fi
	# Garantir que não existe já um Volume Clone com este nome (via API)
	existing_vclone_json=$(vol_cl_ls 2>>"$log_file")
	if echo "$existing_vclone_json" | jq -e --arg name "$vclone_name" '.volumeClones[]? | select(.name == $name)' >/dev/null 2>&1
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Volume Clone with name $vclone_name already exists, please choose a different name!"
	fi
	# Resolver volumes a clonar
	if [[ "$volumes_to_clone_arg" == "ALL" ]]
	then
		# ALL → ir buscar os volumes anexados à VSI pelo API
		volumes_to_clone=$(ins_vol_ls 2>>"$log_file" | jq -r '.volumes[]?.volumeID' | paste -sd, -)
		if [[ -z "$volumes_to_clone" ]]
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - No volumes found attached to VSI $vsi to clone."
		fi
	else
		# Lista explícita de IDs, tal como passado na linha de comando
		volumes_to_clone="$volumes_to_clone_arg"
	fi
	# Validar que temos pelo menos 2 volumes
	IFS=',' read -r -a vclone_array <<< "$volumes_to_clone"
	if [ "${#vclone_array[@]}" -lt 2 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Volume Clone Request must contain at least 2 volumes. You provided: ${#vclone_array[@]} ($volumes_to_clone)"
	fi
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - === Starting the three processes of Volume Clone $vclone_name" "1"
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - This is the list of volumes that will be cloned: $volumes_to_clone" "1"
	# Guardar a lista para as funções seguintes
	volumes_to_clone="$volumes_to_clone"
	do_volume_clone
	do_volume_clone_start
	do_volume_clone_execute
	abort "$(date +%Y-%m-%d_%H:%M:%S) - === Successfully finished -  Volume Clone $vclone_name !"
    ;;

  -vclonedel)
	# Syntax: bluexport_api.sh -vclonedel VOLUME_CLONE_NAME 0|delete_volumes
	if [ $# -lt 2 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Arguments Missing!! Syntax: bluexport_api.sh $1 VOLUME_CLONE_NAME 0|delete_volumes"
	fi
	if [ $# -gt 3 ]
	then
	abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport_api.sh $1 VOLUME_CLONE_NAME 0|delete_volumes"
	fi
	test=0
	found=0
	vclone_name=$2
	delete_mode="${3:-0}"
	# Validar o modo
	if [[ "$delete_mode" != "0" && "$delete_mode" != "delete_volumes" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Invalid parameter for delete_volumes. Use 0 or delete_volumes. Syntax: bluexport_api.sh $1 VOLUME_CLONE_NAME 0|delete_volumes"
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
			abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Could not retrieve volumesCloneID for $vclone_name in workspace $full_ws_name."
		fi
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
						abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - vol_bdel call failed (curl rc=$ret) while deleting cloned volumes for $vclone_name."
					fi
					# 2) API-level failure (HTTP 400 etc, returned as JSON but curl rc=0)
					if [[ -n "$resp_bdel" ]] && echo "$resp_bdel" | jq . >/dev/null 2>&1
					then
						# If the API returns fields like { "error": "...", "description": "..." } or { "code": 400, "message": "..." }
						if echo "$resp_bdel" | jq -e '(.code? != null) or (.error? != null) or (.errors? != null)' >/dev/null 2>&1
						then
							errmsg=$(echo "$resp_bdel" | jq -r '.description // .message // .error // (.errors[0] // empty) // "Unknown API error"' 2>/dev/null)
							abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Error deleting cloned volumes for $vclone_name: $errmsg"
						fi
					else
						# Non-JSON error body fallback
						if echo "$resp_bdel" | grep -qi "Bad Request\|in-use\|migrating\|cannot be deleted"
						then
							abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Error deleting cloned volumes for $vclone_name. API response indicates volumes cannot be deleted (in-use/migrating/group)."
						fi
					fi
					echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Cloned volumes successfully deleted for $vclone_name." "1"
				fi
			fi
		fi
		# Agora apagar o Volume Clone request
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - === Trying to Delete Volume Clone with name $vclone_name" "1"
		vol_cl_del 2>>"$log_file" | tee -a "$log_file" #>/dev/null
		ret=$?
		if [ $ret -ne 0 ]
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Error deleting Volume Clone $vclone_name. Check messages above this line..."
		fi
		abort "`date +%Y-%m-%d_%H:%M:%S` - === Successfully Deleted Volume Clone with name $vclone_name (mode: $delete_mode) !"
	done
	if [[ "$found" -eq 0 ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Volume Clone '$vclone_name' does not exist in any workspace."
	fi
     ;;

   -creategrs)
	# Syntax: bluexport_api.sh -creategrs SOURCE_VSI TARGET_VSI VG_NAME SOURCE_VOLUMES_NAME
	if [ $# -lt 5 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Arguments Missing!! Syntax: bluexport_api.sh $1 SOURCE_VSI TARGET_VSI VG_NAME SOURCE_VOLUMES_NAME"
	fi
	if [ $# -gt 5 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport_api.sh $1 SOURCE_VSI TARGET_VSI VG_NAME SOURCE_VOLUMES_NAME"
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
			abort "`date +%Y-%m-%d_%H:%M:%S` - Aborting GRS creation - please delete the snapshots for these volumes and run bluexport_api.sh $flags again."
		fi
	fi
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Both VSIs found and validated. Proceeding with GRS creation..." "1"
	create_grs
     ;;

  -deletegrs)
	# Syntax: bluexport_api.sh -deletegrs SOURCE_VSI TARGET_VSI VG_NAME SOURCE_VOLUME_NAMES
	if [ $# -lt 5 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments Missing!! Syntax: bluexport_api.sh $1 SOURCE_VSI TARGET_VSI VG_NAME SOURCE_VOLUME_NAMES"
	fi
	if [ $# -gt 5 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments!! Syntax: bluexport_api.sh $1 SOURCE_VSI TARGET_VSI VG_NAME SOURCE_VOLUME_NAMES"
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
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments Missing!! Syntax: bluexport_api.sh $1 SOURCE_VSI VG_NAME NO_ATTACH|ATTACH [TARGET_VSI]"
	fi
	if [ $# -gt 5 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments!! Syntax: bluexport_api.sh $1 SOURCE_VSI VG_NAME NO_ATTACH|ATTACH [TARGET_VSI]"
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
			abort "$(date +%Y-%m-%d_%H:%M:%S) - TARGET_VSI is required when using ATTACH mode. Syntax: bluexport_api.sh $1 SOURCE_VSI VG_NAME ATTACH TARGET_VSI"
		fi
		target_vsi="$5"
	elif [[ "$attach_mode" != "NO_ATTACH" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Invalid MODE '$attach_mode'. Use NO_ATTACH or ATTACH."
	fi
	do_grs_failover
     ;;

  -grscancelfailover)
	# Syntax: bluexport_api.sh -grscancelfailover SOURCE_VSI VG_NAME NO_DETACH|DETACH TARGET_VSI
	if [ $# -ne 5 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments Missing/Invalid!! Syntax: bluexport_api.sh $1 SOURCE_VSI VG_NAME NO_DETACH|DETACH TARGET_VSI"
	fi
	test=0
	flagj=1
	source_vsi="$2"
	vg_name="$3"
	detach_mode="$4"
	target_vsi="$5"
	if [[ "$detach_mode" != "NO_DETACH" && "$detach_mode" != "DETACH" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Invalid MODE '$detach_mode'. Use NO_DETACH or DETACH."
	fi
	do_grs_cancel_failover
     ;;

  -grsfailback)
	# Syntax: bluexport_api.sh -grsfailback SOURCE_VSI TARGET_VSI VG_NAME
	if [ $# -ne 4 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments Missing/Invalid!! Syntax: bluexport_api.sh $1 SOURCE_VSI TARGET_VSI VG_NAME"
	fi
	test=0
	flagj=1
	source_vsi="$2"
	target_vsi="$3"
	vg_name="$4"
	do_grs_failback
     ;;

   -vsistart)
	if [ $# -ne 2 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many or too few arguments!! Syntax: bluexport_api.sh -startvsi VSI_NAME"
	fi
	vsi="$2"
	do_start_vsi "$vsi"
     ;;

   -vsioper)
	# Syntax: -vsioper VSI_NAME BOOT_MODE OPERATING_MODE
	if [ $# -ne 4 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many or too few arguments!! Syntax: bluexport_api.sh -vsioper VSI_NAME BOOT_MODE OPERATING_MODE. BOOT_MODE: a | b | c | d  -  OPERATING_MODE: normal | manual"
	fi
	vsi="$2"
	boot_mode="$3"
	operating_mode="$4"
	do_vsi_oper "$vsi" "$boot_mode" "$operating_mode"
     ;;

   -vsitask)
	if [ $# -ne 3 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many or too few arguments!! Syntax: bluexport_api.sh -vsitask VSI_NAME TASK. TASK: dston (21) | retrydump (34) | consoleservice | iopreset (67) | remotedstoff (65) | remotedston (66) | iopdump (70) | dumprestart (22)"
	fi
	vsi="$2"
	task="$3"
	do_vsi_task "$vsi" "$task"
     ;;

   -vsisrcmon)
	if [ $# -ne 3 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many or too few arguments!! Syntax: bluexport_api.sh -vsisrcmon VSI_NAME START|SHUTOFF"
	fi
	vsi="$2"
	mode="$3"
	do_vsi_srcmon "$vsi" "$mode"
     ;;

   -attachvolumes)
	# Syntax: bluexport_api.sh -attachvolumes VOLUMES_COMMON_NAME VSI_NAME
	if [ $# -ne 3 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many or too few arguments!! Syntax: bluexport_api.sh -attachvolumes VOLUMES_COMMON_NAME VSI_NAME"
	fi
	vol_common_name="$2"
	vsi="$3"
	do_vsi_attach_volumes "$vol_common_name" "$vsi"
     ;;

   -detachvolumes)
	# Syntax: bluexport_api.sh -detachvolumes VSI_NAME
	if [ $# -ne 2 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many or too few arguments!! Syntax: bluexport_api.sh -detachvolumes VSI_NAME"
	fi
	vsi="$2"
	do_vsi_detach_volumes "$vsi"
     ;;

   -bucketslsall)
	# Lista todos os buckets por COS instance definido em .cos_instances no bluexscrt
	if [ $# -gt 1 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments!! Syntax: bluexport_api.sh $1"
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

  -bucketlsobjs)
	# Lista objetos de um bucket COS escolhido interativamente
	if [ $# -gt 1 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments!! Syntax: bluexport_api.sh -bucketlsobjs"
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
		abort "$(date +%Y-%m-%d_%H:%M:%S) - COS instance \"$chosen_cos\" has no GUID in $bluexscrt. Cannot list buckets."
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
	echo "$buckets_xml" >>"$log_file"
	if [[ -z "$buckets_xml" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Empty response from S3 when listing buckets for COS instance \"$chosen_cos\"."
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
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Empty response from S3 when listing objects in bucket \"$chosen_bucket\"."
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

   -bucketdelobj)
	# Delete a single object from a COS bucket (interactive)
	if [ $# -gt 1 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments!! Syntax: bluexport_api.sh -bucketdelobj"
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
			abort "$(date +%Y-%m-%d_%H:%M:%S) - No input received from terminal. Aborting..."
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
		abort "$(date +%Y-%m-%d_%H:%M:%S) - COS instance \"$chosen_cos\" has no GUID in $bluexscrt. Cannot list buckets."
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
	echo "$buckets_xml" >>"$log_file"
	if [[ -z "$buckets_xml" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Empty response from S3 when listing buckets for COS instance \"$chosen_cos\"."
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
			abort "$(date +%Y-%m-%d_%H:%M:%S) - No input received from terminal. Aborting..."
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
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Empty response from S3 when listing objects in bucket \"$chosen_bucket\"."
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
			abort "$(date +%Y-%m-%d_%H:%M:%S) - No input received from terminal. Aborting..."
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
	object_delete 2>>"$log_file" | tee -a "$log_file"
	abort "$(date +%Y-%m-%d_%H:%M:%S) - === Finished deleting object \"$KEY\" from bucket \"$BUCKET\" ==="
     ;;


    *)
	if [ -t 1 ]
	then
		help
	fi
	abort "`date +%Y-%m-%d_%H:%M:%S` - Missing or invalid Flag!"
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
	flush_asps
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
		job_id=$(ins_cap | jq -r '.id' 2>> $log_file | tee -a $log_file $job_id_file)
	fi
else
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - == Executing Capture and Export cloud command... ==" "1"
	ACTIONS="\"captureName\": \"$capture_name\", \"captureDestination\": \"$destination\", \"captureVolumeIDs\": [\"$volumes_api\"], \"cloudStorageAccessKey\": \"$accesskey\", \"cloudStorageImagePath\": \"$bucket\", \"cloudStorageRegion\": \"$region\", \"cloudStorageSecretKey\": \"$secretkey\""
	if [ $test -eq 1 ]
	then
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - ins_cap \"$ACTIONS\"" "1"
	else
		rm $job_id_file
		job_id=$(ins_cap | jq -r '.id' 2>> $log_file | tee -a $log_file $job_id_file)

	fi
fi
####  END: Make the Capture and Export  ####

####  START: Job Monitoring  ####
if [ $test -eq 0 ]
then
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - => Iniciating Job Monitorization..." "1"
else
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - => Iniciating Job Monitorization..." "1"
	abort "`date +%Y-%m-%d_%H:%M:%S` - Test Finished!"
fi

job_monitor
####  END: Job Monitoring  ####

       #####  END:CODE  #####
