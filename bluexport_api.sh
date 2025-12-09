#!/bin/bash
#
# Capture IBM Cloud POWERVS VSI and Export to COS or/and Image Catalog and Snapshots
#
# Version 3.x now supports the creation, update, delete and list Snapshots.
#
# Usage for changing secret file:	./bluexport_api.sh -chscrt bluexscrt_file_name - Use the full path ex: /home/user/bluexscrt_new
#
# Usage to view secret file in use:	./bluexport_api.sh -viewscrt
#
# Usage for all volumes:		./bluexport_api.sh -a VSI_Name_to_Capture Capture_Image_Name both|image-catalog|cloud-storage hourly|daily|weekly|monthly|single
# Usage for excluding volumes:		./bluexport_api.sh -x volumes_name_to_exclude VSI_Name_to_Capture Capture_Image_Name both|image-catalog|cloud-storage hourly|daily|weekly|monthly|single
# Usage for monitoring job:		./bluexport_api.sh -j VSI_NAME IMAGE_NAME
#
# Usage to create a snapshot:		./bluexport_api.sh -snapcr VSI_NAME SNAPSHOT_NAME 0|["DESCRIPTION"] 0|[VOLUMES(Comma separated list)]
# Usage to update a snapshot:		./bluexport_api.sh -snapupd VSI_NAME SNAPSHOT_NAME 0|[NEW_SNAPSHOT_NAME] 0|["DESCRIPTION"]
# Usage to delete snapshot:		./bluexport_api.sh -snapdel VSI_NAME SNAPSHOT_NAME
# Usage to list all snapshot
#        in all Workspaces:		./bluexport_api.sh -snaplsall
#
# Usage to list all Captured
# images in all Workspaces:             ./bluexport_api.sh -imglsall
#
# Usage to create a volume clone:   	./bluexport_api.sh -vclone VOLUME_CLONE_NAME BASE_NAME LPAR_NAME True|False(replication-enabled) True|False(rollback-prepare) STORAGE_TIER ALL|(Comma seperated Volumes name list to clone)"
# Usage to delete a volume clone:	./bluexport_api.sh -vclonedel VOLUME_CLONE_NAME
# Usage to list all volume clones
#        in all Workspaces:		./bluexport_api.sh -vclonelsall
#
# Usage to change volume tier:          ./bluexport_api.sh -vchtier VSI_NAME VOLUMES_NAME TIER_TO_CHANGE_TO
#
# Example:  ./bluexport_api.sh -a vsiprd vsiprd_img image-catalog daily            ---- Includes all Volumes and exports to COS and image catalog
# Example:  ./bluexport_api.sh -x ASP2_ vsiprd vsiprd_img both monthly             ---- Excludes Volumes with ASP2_ in the name and exports to image catalog and COS
# Example:  ./bluexport_api.sh -x "ASP2_ iASPname" vsiprd vsiprd_img both monthly  ---- Excludes Volumes with ASP2_ and iASPname in the name and exports to image catalog and COS
#
# Note: Reocurrence "hourly" and "daily" only permits captures to image-catalog
#
#
# Ricardo Martins - Blue Chip Portugal - 2023-2025
###########################################################################################

       #####  START:CODE  #####

Version=1.0

conf_file="$HOME/bluexport_conf.json"

log_file=$(jq -r '.log_file' "$conf_file")
bluexscrt=$(jq -r '.bluexscrt' "$conf_file")
env_file=$(jq -r '.env_file' "$conf_file")
end_log_file='==== END ========= $timestamp ========='

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

if [[ $1 != "-chscrt" ]] && [[ $1 != "-viewscrt" ]] && [[ $1 != "-v" ]] && [[ $1 != "--version" ]] && [[ $1 != "-h" ]] && [[ $1 != "--help" ]] && [[ $1 != "-help" ]] && [[ $1 != "" ]]
then
	####  START: Check if Config File exists  ####
	if [ ! -f $bluexscrt ]
	then
		echoscreen ""
		timestamp=$(date +%F" "%T" "%Z)
		echo "==== START ======= $timestamp =========" >> $log_file
		echo "Flags Used: $@" >> $log_file
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Config file $bluexscrt Missing!! Aborting!..." "1"
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
	echoscreen "Capture IBM Cloud POWERVS IBM i VSI and Export to COS and/or Image Catalog, manage Snapshots, Volume Clones and GRS Volume Groups."
	echoscreen "Version: $Version"
	echoscreen ""
	echoscreen "=== General ==="
	echoscreen "Changing secret file:          ./bluexport_api.sh -chscrt bluexscrt_file_name   (use full path, e.g. /home/user/bluexscrt_new)"
	echoscreen "View secret file in use:      ./bluexport_api.sh -viewscrt"
	echoscreen ""
	echoscreen "Show help:                    ./bluexport_api.sh -h | --help | -help"
	echoscreen "Show version:                 ./bluexport_api.sh -v | --version"
	echoscreen ""
	echoscreen "=== Capture & Export ==="
	echoscreen "Usage for all volumes:        ./bluexport_api.sh -a VSI_Name_to_Capture Capture_Image_Name both|image-catalog|cloud-storage hourly|daily|weekly|monthly|single"
	echoscreen "Usage for excluding volumes:  ./bluexport_api.sh -x volumes_name_to_exclude VSI_Name_to_Capture Capture_Image_Name both|image-catalog|cloud-storage hourly|daily|weekly|monthly|single"
	echoscreen "Usage for monitoring job:     ./bluexport_api.sh -j VSI_NAME IMAGE_NAME"
	echoscreen ""
	echoscreen "=== Snapshots ==="
	echoscreen "Create snapshot:              ./bluexport_api.sh -snapcr   VSI_NAME SNAPSHOT_NAME 0|[DESCRIPTION] 0|[VOLUMES(Comma separated list)]"
	echoscreen "Update snapshot:              ./bluexport_api.sh -snapupd  VSI_NAME SNAPSHOT_NAME 0|[NEW_SNAPSHOT_NAME] 0|[DESCRIPTION]"
	echoscreen "Delete snapshot:              ./bluexport_api.sh -snapdel  VSI_NAME SNAPSHOT_NAME"
	echoscreen "List all snapshots (all WS):  ./bluexport_api.sh -snaplsall"
	echoscreen ""
	echoscreen "=== Captured Images ==="
	echoscreen "List all captured images"
	echoscreen " in all Workspaces:           ./bluexport_api.sh -imglsall"
	echoscreen ""
	echoscreen "=== Volume Clones ==="
	echoscreen "Create volume clone:          ./bluexport_api.sh -vclone VOLUME_CLONE_NAME BASE_NAME LPAR_NAME True|False(replication-enabled) True|False(rollback-prepare) STORAGE_TIER ALL|(Comma separated Volumes name list to clone)"
	echoscreen "Delete volume clone:          ./bluexport_api.sh -vclonedel VOLUME_CLONE_NAME"
	echoscreen "List volume clones (all WS):  ./bluexport_api.sh -vclonelsall"
	echoscreen ""
	echoscreen "=== Volume Tier ==="
	echoscreen "Change volume tier:           ./bluexport_api.sh -vchtier VSI_NAME VOLUMES_NAME TIER_TO_CHANGE_TO"
	echoscreen ""
	echoscreen "=== GRS (Global Replication Services) ==="
	echoscreen "Create GRS Volume Group and onboard auxiliary volumes:"
	echoscreen "  ./bluexport_api.sh -creategrs SOURCE_VSI TARGET_VSI VG_NAME SOURCE_VOLUME_NAMES TARGET_VOLUME_NAMES"
	echoscreen ""
	echoscreen "  SOURCE_VSI / TARGET_VSI:        Logical PowerVS instance names as defined in your JSON."
	echoscreen "  VG_NAME:                        Name for the Volume Group to create on the source workspace."
	echoscreen "  SOURCE_VOLUME_NAMES:            Common name/prefix to identify source VSI volumes (e.g. IBMiGRS)."
	echoscreen "  TARGET_VOLUME_NAMES:            Common name/prefix for target VSI volumes (used mainly for documentation/logging)."
	echoscreen ""
	echoscreen "=== Examples ==="
	echoscreen "Capture all volumes:          ./bluexport_api.sh -a vsiprd vsiprd_img image-catalog daily"
	echoscreen "Capture excluding ASP2_:      ./bluexport_api.sh -x ASP2_ vsiprd vsiprd_img both monthly"
	echoscreen "Capture excluding ASP2_ & iASPname:"
	echoscreen '                               ./bluexport_api.sh -x "ASP2_ iASPname" vsiprd vsiprd_img both monthly'
	echoscreen ""
	echoscreen "Test mode (no capture):       ./bluexport_api.sh -tx ASP2_ vsiprd vsiprd_img both single"
	echoscreen ""
	echoscreen "Note: Recurrence \"hourly\" and \"daily\" only permits captures to image-catalog."
	echoscreen ""
	echoscreen "Ricardo Martins - Blue Chip Portugal - 2023-2025"
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

snap_del() {
	curl -sX DELETE $base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/snapshots/$SNAP_ID -H "$header_auth" -H "CRN: $CRN" -H "$header_json"
}
#### END:FUNCTION - API Commands ####

#### START:FUNCTION - Check if image-catalog and Cloud Object has images from last time and deleted it ####
delete_previous_img() {
##########!!!!!!!!!!	img_id_old=$(/usr/local/bin/ibmcloud pi img ls | grep -wi $vsi | grep $old_img | awk {'print $1'})
###########!!!!!!!!!!	img_name_old=$(/usr/local/bin/ibmcloud pi img ls | grep -wi $vsi | grep $old_img | awk {'print $2'})
##########!!!!!!!!!	objstg_img=$(/usr/local/bin/ibmcloud cos list-objects-v2 --bucket $bucket | grep -wi $vsi | grep $old_img | awk {'print $1'})
##############!!!!!	today_img=$(/usr/local/bin/ibmcloud cos list-objects-v2 --bucket $bucket | grep -wi $vsi | grep $capture_date | awk {'print $1'})
	if [ ! $img_id_old ]
	then
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - There is no Image from $old_img - Nothing to delete in image catalog." "1"
	else
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - == Deleting from image catalog image name $img_name_old - image ID $img_id_old - from day $old_img... ==" "1"
#############!!!!!!!!!!		sh -c '/usr/local/bin/ibmcloud pi img del '$img_id_old 2>> $log_file | tee -a $log_file
	fi
	if [ ! $objstg_img ]
	then
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - No image from previous export to delete in Object Storage." "1"
	else
		if [ ! $today_img ]
		then
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - == Something went wrong... Today's image is not in Bucket $bucket. Keeping ( Not deleted ) image name $objstg_img from day $old_img... ==" "1"
		else
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - == Deleting from Bucket $bucket, image name $objstg_img from day $old_img... ==" "1"
##########!!!!!!!!!!!!			sh -c '/usr/local/bin/ibmcloud cos object-delete --bucket '$bucket' --key '$objstg_img' --force' 2>> $log_file | tee -a $log_file
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
		vsi_ip=$(jq -r --arg name "$vsi" '.systems[] | select(.name == $name) | .ip' "$bluexscrt")
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

	# Check if VSI exists in JSON
	if jq -e --arg vsi "$vsi" 'any(.systems[]; (.name == $vsi ))' "$bluexscrt" > /dev/null
	then
		# Get workspace short name (e.g., WSMAD2) for this VSI
		vsiwsshort=$(jq -r --arg vsi "$vsi" '.systems[] | select(.name == $vsi) | .workspace' "$bluexscrt")
		# Get workspace CRN for that short name
		shortnamecrn=$(jq -r --arg ws "$vsiwsshort" '.workspaces[$ws].crn' "$bluexscrt")
		# Call function that lists VSIs in that workspace (writes to $vsi_list_tmp)
		dc_vsi_list "$shortnamecrn"
		# Get the cloud VSI name from the list file
		vsi_cloud_name=$(grep -wi "$vsi" "$vsi_list_tmp" | awk '{print $1}')
		# Get full workspace name directly from JSON
		full_ws_name=$(jq -r --arg ws "$vsiwsshort" '.workspaces[$ws].name' "$bluexscrt")
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - VSI $vsi_cloud_name was found in $full_ws_name..." "1"
		if [ "$flagj" -eq 0 ]
		then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - VSI to Capture: $vsi_cloud_name" "1"
			get_iASP_name
		fi
	else
		echoscreen ""
		echoscreen "   ### VSI $vsi not found in any of the workspaces available in $bluexscrt!"
		echoscreen ""
		exit 0
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
			if [[ -n "$iasp_names" ]]
			then
				for iasp_name in $iasp_names
				do
					echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Flushing Memory to Disk for $iasp_name ..." "1"
					ssh -T -i "$sshkeypath" "$vsi_user@$vsi_ip" "system \"CHGASPACT ASPDEV('$iasp_name') OPTION(*FRCWRT)\"" >> "$log_file" | tee -a "$log_file"
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
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - == Executing Snapshot $snap_name of Instance $vsi with volumes $volumes_to_echo" "1"
########!!!!!!!!!	snap_cr_cmd="/usr/local/bin/ibmcloud pi ins snap cr $vsi_id --name $snap_name $description $flag_volumes $volumes_to_snap"
	eval $snap_cr_cmd 2>> $log_file
	if [ $? -eq 1 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Oops something went wrong!... Check the log above this line..."
	else
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Waiting for Snapshot $snap_name to reach 100%..." "1"
		snap_percent=0
		while [ $snap_percent -lt 100 ]
		do
			snap_percent_before=$snap_percent
			sleep 10
#########!!!!!!!!!!!!!			snap_percent=$(/usr/local/bin/ibmcloud pi ins snap ls | grep -w $snap_name | awk 'NF>1{print $NF}')
			if [[ "$snap_percent" == "" ]]
			then
				abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Oops something went wrong!... Check the log above this line..."
			fi
			if [[ "$snap_percent" != "$snap_percent_before" ]]
			then
				if [[ "$snap_percent" == "100" ]]
				then
					echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Snapshot $snap_name reached 100% - Done!" "1"
				else
					echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Snapshot $snap_name at $snap_percent%" "1"
				fi
			fi
		done
	fi
}
####  END:FUNCTION - Do the Snapshot Create  ####

####  START:FUNCTION - Do the Snapshot Update  ####
do_snap_update() {
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - == Executing Snapshot $snap_name Update $new_name_echo" "1"
########!!!!!!!!!!!!	snap_id=$(/usr/local/bin/ibmcloud pi ins snap ls | grep -w $snap_name | awk {'print $1'})
##########!!!!!!!!	snap_upd_cmd="/usr/local/bin/ibmcloud pi ins snap upd $snap_id $description $new_name"
	eval $snap_upd_cmd 2>> $log_file
	if [ $? -eq 0 ]
	then
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Snapshot $snap_name updated $new_name_echo $new_description_echo - Done!" "1"
	else
		abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Oops something went wrong!... Check the log above this line..."
	fi
}
####  END:FUNCTION - Do the Snapshot Update  ####

####  START:FUNCTION - Do the Snapshot Delete  ####
do_snap_delete() {
        echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - === Starting Snapshot Delete '$snap_name' from VSI $vsi !" "1"
        # Retrieve snapshots via API
        snaps_json=$(snap_ls 2>>"$log_file")
        # Find snapshot ID by name (exact match)
        snap_id=$(echo "$snaps_json" | jq -r --arg name "$snap_name" '.snapshots[]? | select(.name == $name) | .snapshotID ')
        if [[ -z "$snap_id" || "$snap_id" == "null" ]]; then
            abort "$(date +%Y-%m-%d_%H:%M:%S) - Snapshot '$snap_name' does not exist. Choose another name or use -snapcr to create one."
        fi
        echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Snapshot '$snap_name' found with ID: $snap_id" "1"
        # Delete snapshot via API
        echo "$(date +%Y-%m-%d_%H:%M:%S) - Executing delete for snapshot ID $snap_id ..." | tee -a "$log_file"
	SNAP_ID=$snap_id
        resp=$(snap_del 2>>"$log_file")
        # Check API response
        if echo "$resp" | grep -q '"error"'; then
            abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED deleting snapshot '$snap_name'. API error: $resp"
        fi
        echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Snapshot '$snap_name' delete request sent successfully." "1"
        # Optional: Poll snapshot list until it disappears
        echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Waiting for snapshot deletion to complete..." "1"
        for i in {1..100}; do
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
	flush_asps
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - == Executing Volume Clone with name $vclone_name ..." "1"
#############!!!!!!!!!!!	/usr/local/bin/ibmcloud pi vol cl ex $vclone_id --name $base_name --replication-enabled=$replication --rollback-prepare=$rollback --target-tier $target_tier 2>> $log_file
	if [ $? -eq 0 ]
	then
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Waiting for Volume Clone $vclone_name execution to finish..." "1"
		vcloneex_percent=0
		while [ $vcloneex_percent -lt 100 ]
		do
			vcloneex_percent_before=$vcloneex_percent
			sleep 5
##########!!!!!!!!!!!!!			vcloneex_percent=$(/usr/local/bin/ibmcloud pi vol cl ls | grep -A6 $vclone_name | grep "Percent Completed:" | awk {'print $3'})
			if [[ "$vcloneex_percent" != "$vcloneex_percent_before" ]]
			then
				if [ $vcloneex_percent -eq 100 ]
				then
					echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Volume Clone $vclone_name Done and ready to be used!" "1"
				else
					echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Volume Clone $vclone_name execution at $vcloneex_percent%" "1"
				fi
			fi
		done
	else
		abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Oops something went wrong!... Check the log above this line..."
	fi
}
####  END:FUNCTION -  Do the Volume Clone Execute ####

####  START:FUNCTION - Do the Volume Clone Start ####
do_volume_clone_start() {
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - == Starting Volume Clone with name $vclone_name ..." "1"
###########!!!!!!!!!	vclone_id=$(/usr/local/bin/ibmcloud pi vol cl ls | grep -A6 $vclone_name | grep "Volume Clone Request ID:" | awk {'print $5'})
############!!!!!!!!	/usr/local/bin/ibmcloud pi vol cl st $vclone_id 2>> $log_file
	if [ $? -eq 0 ]
	then
#######!!!!!!!!!!		vclone_start_action=$(/usr/local/bin/ibmcloud pi vol cl get $vclone_id | grep "Action" | awk {'print $2'})
########!!!!!!!!!!		vclone_start_status=$(/usr/local/bin/ibmcloud pi vol cl get $vclone_id | grep "Status" | awk {'print $2'})
		if [[ "$vclone_start_action" == "start" ]] && [[ "$vclone_start_status" == "available" ]]
		then
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Volume Clone $vclone_name Started and ready to execute..." "1"
		else
			abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Oops something went wrong!... Check the log above this line..."
		fi
	else
		abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Oops something went wrong!... Check the log above this line..."
	fi

}
####  END:FUNCTION -  Do the Volume Clone Start ####

####  START:FUNCTION - Do the Volume Clone ####
do_volume_clone() {
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - == Creating Volume Clone Request with name $vclone_name ..." "1"
#########!!!!!!!!!!	/usr/local/bin/ibmcloud pi vol cl cr --name $vclone_name --volumes $volumes_to_clone 2>> $log_file
	if [ $? -eq 0 ]
	then
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Waiting for Volume Clone Request $vclone_name creation to finish..." "1"
		vclone_percent=0
		while [ $vclone_percent -lt 100 ]
		do
			vclone_percent_before=$vclone_percent
			sleep 5
##########!!!!!!!!!!!!!			vclone_percent=$(/usr/local/bin/ibmcloud pi vol cl ls | grep -A6 $vclone_name | grep "Percent Completed:" | awk {'print $3'})
			if [[ "$vclone_percent" != "$vclone_percent_before" ]]
			then
				if [ $vclone_percent -eq 100 ]
				then
					echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Volume Clone Request $vclone_name Done!" "1"
				else
					echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Volume Clone Request $vclone_name creation at $vclone_percent%" "1"
				fi
			fi
		done
	else
		abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Oops something went wrong!... Check the log above this line..."
	fi
}
####  END:FUNCTION -  Do the Volume Clone ####

####  START:FUNCTION  Check if VSI ID exists in bluexscrt file  ####
vsi_id_bluexscrt() {
	# Lookup VSI data inside the "systems" array
	vsi_ip=$(jq -r --arg name "$vsi" '.systems[] | select(.name == $name) | .ip' "$bluexscrt")
	vsi_id=$(jq -r --arg name "$vsi" '.systems[] | select(.name == $name) | .pvmInstanceID' "$bluexscrt")

	PVM_ID="$vsi_id"

	# Validation: instance not found
	if [[ -z "$vsi_id" || "$vsi_id" == "null" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - VSI ID missing or VSI Name '$vsi' not found in $bluexscrt. Please add it to the JSON..."
	fi

	# Retrieve workspace key, example: "WSMAD2"
	vsi_ws=$(jq -r --arg name "$vsi" '.systems[] | select(.name == $name) | .workspace' "$bluexscrt")

	# Retrieve workspace ID using the workspace key
	vsi_ws_id=$(jq -r --arg ws "$vsi_ws" '.workspaces[$ws].id' "$bluexscrt")
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

####  START:FUNCTION  Export to COS an existent Image  ####
export_img() {
	abort "`date +%Y-%m-%d_%H:%M:%S` - Under construction!!"
}
####  END:FUNCTION  Export to COS an existent Image  ####

####  START:FUNCTION  Delete Image from image-catalog  ####
delete_img() {
	abort "`date +%Y-%m-%d_%H:%M:%S` - Under construction!!"
}
####  END:FUNCTION  Export to COS an existent Image  ####

#################  GRS Code  ####################

####  START:FUNCTION  Create Volume Group  ####
create_vg() {
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Starting Create $vg_flag_echo $vg_name" "1"
	echoscreen ""
	test=0
	flagj=1
	vsi_id_bluexscrt
#	cloud_login
	check_locally_VSI_exists
######!!!!!!!!!!!!!!!!	volumes_to_GRS=$(/usr/local/bin/ibmcloud pi ins vol ls $vsi_id | tail -n +2 | awk {'print $1'} | sed -z 's/\n/,/g' | sed 's/.$//')
	ret=$?
	if [ $ret -ne 0 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` -     FAILED - Oops something went wrong!... Check messages above this line..."
	fi
	volumes_rep=$(echo $volumes_to_GRS | sed 's/,/\n/g')
	index=0
	fail=0
	all_good=0
	while [ $all_good -eq 0 ]
	do
		for volume in $volumes_rep
		do
###########!!!!!!!!!!!			tmp_vol=$(/usr/local/bin/ibmcloud pi vol get $volume | grep -we "Replication Enabled" -we "Name" -we "ID")
			ret=$?
			if [ $ret -ne 0 ]
			then
				abort "`date +%Y-%m-%d_%H:%M:%S` -     FAILED - Oops something went wrong!... Check messages above this line..."
			fi
			is_vol_rep_enabled=$(echo $tmp_vol | awk {'print $7'})
			vol_name=$(echo $tmp_vol | awk {'print $4'})
			vol_id=$(echo $tmp_vol | awk {'print $2'})
			if [[ "$is_vol_rep_enabled" != "true" ]]
			then
				fail=1
				vol_not_rep_enabled[$index]=$vol_name
				vol_id_not_rep_enabled[$index]=$vol_id
				index=$((index + 1))
			fi
		done
		all_good=1
		if [ $fail -eq 1 ]
		then
			echoscreen ""
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Create $vg_flag_echo $vg_name can not continue because the following volumes are not replication enabled" "1"	
			for i in ${vol_not_rep_enabled[@]}
			do
				echoscreen "$i" "1"
			done
			read -p "Do you want to enable replication on these volumes (Y/N) ? " enable_rep
			if [[ "$enable_rep" == "Y" ]] || [[ "$enable_rep" == "y" ]]
			then
				echoscreen ""
				echoscreen "OK, let's try enable the replication on the volumes..." "1"
				echoscreen ""
				index=0
				for i in ${vol_not_rep_enabled[@]}
				do
					echoscreen "Enabling replication on volume $i" "1"
#########!!!!!!!!!!!!!!!					/usr/local/bin/ibmcloud pi vol act ${vol_id_not_rep_enabled[$index]} --replication-enabled=True
					index=$((index + 1))
					ret=$?
					if [ $ret -ne 0 ]
					then
						abort "`date +%Y-%m-%d_%H:%M:%S` -     FAILED - Oops something went wrong!... Check messages above this line..."
					fi
					echoscreen ""
				done
				fail=0
				all_good=0
				echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Now waiting one minute for the volumes to update..." "1"
				sleep 60
			fi
		fi
	done
	if [ $fail -eq 1 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - If you still want to create a $vg_flag_echo, please enable replication on the volumes listed above!..."
	fi
	echoscreen ""
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - All good with the volumes, now creating $vg_flag_echo $vg_name" "1"
#########!!!!!!!!!!!!!	/usr/local/bin/ibmcloud pi vg cr $vg_flag $vg_name --member-volume-ids "$volumes_to_GRS"
	ret=$?
	if [ $ret -ne 0 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` -     FAILED - Oops something went wrong!... Check messages above this line..."
	fi
	vgcsg_ready=""
	while [[ "$vgcsg_ready" != "available" ]]
	do
		sleep 5
########!!!!!!!!!!!		vgcsg_ready=$(/usr/local/bin/ibmcloud pi vg ls | grep -w $vg_name | awk {'print $5'})
		ret=$?
		if [ $ret -ne 0 ]
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` -     FAILED - Oops something went wrong!... Check messages above this line..."
		fi
		if [[ "$vgcsg_ready" == "available" ]]
		then
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - $vg_flag_echo $vg_name created!... Done!" "1"
		else
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - $vg_flag_echo $vg_name still $vgcsg_ready" "1"
		fi
		if [[ "$vgcsg_ready" == "error" ]]
		then
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - $vg_flag_echo $vg_name still $vgcsg_ready" "1"
			abort "`date +%Y-%m-%d_%H:%M:%S` -     FAILED - Oops something went wrong!... Check messages above this line..."
		fi
	done
#########!!!!!!!!!	vg_id=$(/usr/local/bin/ibmcloud pi vg ls | grep -w $vg_name | awk {'print $1'})
	ret=$?
	if [ $ret -ne 0 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` -     FAILED - Oops something went wrong!... Check messages above this line..."
	fi
	copy_sts="inconsistent_copying"	
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Checking state of the Consistency Group, please wait..." "1"
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Copy Status: $copy_sts" "1"
	error=0
	while [[ "$copy_sts" == "inconsistent_copying" ]] || [[ "$copy_sts" == "updating" ]]
	do
		if [ $error -eq 5 ]
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` -     FAILED - Oops something went wrong with the VG Creation... Check in IBM Cloud CLI the possibles reasons."
		fi
		sleep 40
##########!!!!!!!!!!!!!		copy_sts=$(/usr/local/bin/ibmcloud pi vg sd $vg_id | grep -w "State:" | awk {'print $2'})
		#ret=$?
		if [[ $copy_sts == "" ]]
		then
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` -     FAILED - Oops something went wrong!... Check messages above this line... Retrying..."
			error=$((error+1))
		fi
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Percentage by Volumes:"
##########!!!!!!!!!!!!!!		/usr/local/bin/ibmcloud pi vg rcr $vg_id | grep rcrel | awk {'print $1" "$4" "$11"%"'}
		# ret=$?
		# if [ $ret -ne 0 ]
		# then
			# abort "`date +%Y-%m-%d_%H:%M:%S` -     FAILED - Oops something went wrong!... Check messages above this line..."
		# fi
		if [[ "$copy_sts" == "consistent_copying" ]]
		then
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Copy Status: $copy_sts" "1"
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - $vg_flag_echo $vg_name ready to be onboarded in the DR site!" "1"
		fi
	done
}
####  END:FUNCTION  Create Volume Group  ####

####  START:FUNCTION  Onboarding auxiliary Volumes  ####
onboard_aux_vol() {
# ./bluexport_api.sh -onboard LPAR_NAME
	test=0
	flagj=1
	vsi_id_bluexscrt
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Starting onboarding volumes for LPAR $vsi" "1"
	echoscreen ""
#	cloud_login
	check_locally_VSI_exists
###########!!!!!!!!	volumes_to_GRS=$(/usr/local/bin/ibmcloud pi ins vol ls $vsi_id | tail -n +2 | awk {'print $1'} | sed -z 's/\n/,/g' | sed 's/.$//')
	ret=$?
	if [ $ret -ne 0 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` -     FAILED - Oops something went wrong!... Check messages above this line..."
	fi
##########!!!!!!!!!!	aux_volumes_to_onboard=$(/usr/local/bin/ibmcloud pi ins vol ls $vsi_id --json | grep -w '"auxVolumeName":' | awk {'print $2'} | sed -z 's/\"//g'| sed -z 's/,//g')
	index=0
	for i in $aux_volumes_to_onboard
	do
		aux_volumes[$index]=$i
		index=$((index + 1))
	done
###########!!!!!!!!!!!!!	volume_name_to_onboard=$(/usr/local/bin/ibmcloud pi ins vol ls $vsi_id --json | grep -w '"name":' | awk {'print $2'} | sed -z 's/\"//g'| sed -z 's/,//g')
	index=0
	for i in $volume_name_to_onboard
	do
		volume_name[$index]=$i
		index=$((index + 1))
	done
	index=0
	for volume in ${aux_volumes[@]}
	do
		if [[ "$volume" == "" ]]
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` - Onboarding can not continue because volume $volume_name[$index] do not have an auxiliary volume!..."
		fi
		index=$((index + 1))
	done
	aux_vol_to_onboard=$(echo ${aux_volumes[@]}| sed 's/ /,/g')
#############!!!!!!!!!	/usr/local/bin/ibmcloud pi ws tg $target_ws_crn
########!!!!!!!!!!!!!!	/usr/local/bin/ibmcloud pi vol on cr --auxiliary-volumes $aux_vol_to_onboard --source-crn $vsi_ws_id
	ret=$?
	if [ $ret -ne 0 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` -     FAILED - Oops something went wrong!... Check messages above this line..."
	fi
#########!!!!!!!!!!!!	# Testar o status do onboard com o onboard_id=$(/usr/local/bin/ibmcloud pi vol on ls | grep ${aux_volumes[0]} | awk {'print $1'})
#######!!!!!!!!!!	# onboard_status=$(/usr/local/bin/ibmcloud pi vol on ls | grep $onboard_id | awk {'print $2'})
	# onboard_status=""
	#while true
	#do
	#	onboard_previous_status=$onboard_status
#########!!!!!!!!!!!!!!!	#	onboard_status=$(/usr/local/bin/ibmcloud pi vol on ls | grep $onboard_id | awk {'print $2'})
	#	if [[ "$onboard_status" != "$onboard_previous_status" ]]
	#	then
	#		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Onboard Request Status is $onboard_status !" "1"
	#	elif [[ "$onboard_status" == "SUCCESS" ]]
	#	then
	#		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Onboard Request done!" "1"
	#		break
	#	fi
	#done
}
####  END:FUNCTION  Onboarding auxiliary Volumes  ####

####  START:FUNCTION  Stop Volume Group  ####
stop_vg() {
	abort "`date +%Y-%m-%d_%H:%M:%S` - Under construction!!"
}
####  END:FUNCTION  Stop Volume Group  ####

####  START:FUNCTION  Start Volume Group  ####
start_vg() {
	abort "`date +%Y-%m-%d_%H:%M:%S` - Under construction!!"
}
####  END:FUNCTION  Start Volume Group  ####

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
		echoscreen "Flag -j selected, but Arguments Missing!! Syntax: bluexport.api -j VSI_NAME IMAGE_NAME"
		abort "`date +%Y-%m-%d_%H:%M:%S` - Flag -j selected, but Arguments Missing!! Syntax: bluexport.api -j VSI_NAME IMAGE_NAME"
	fi
	if [ $# -gt 3 ]
	then
		echoscreen "Flag -j selected, but too many arguments!! Syntax: bluexport.api -j VSI_NAME IMAGE_NAME"
		abort "`date +%Y-%m-%d_%H:%M:%S` - Flag -j selected, but too many arguments!! Syntax: bluexport.api -j VSI_NAME IMAGE_NAME"
	fi
#	vsi="${2,,}"
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
		abort "`date +%Y-%m-%d_%H:%M:%S` - Arguments Missing!! Syntax: bluexport.api $1 VSI_NAME IMAGE_NAME EXPORT_LOCATION [daily|weekly|monthly|single]"
	fi
	if [ $# -gt 5 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport.api $1 VSI_NAME IMAGE_NAME EXPORT_LOCATION [daily|weekly|monthly|single]"
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
#	vsi="${2,,}"
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
		abort "`date +%Y-%m-%d_%H:%M:%S` - Arguments Missing!! Syntax: bluexport.api $1 EXCLUDE_NAME VSI_NAME IMAGE_NAME EXPORT_LOCATION [daily|weekly|monthly|single]"
	fi
	if [ $# -gt 6 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport.api $1 EXCLUDE_NAME VSI_NAME IMAGE_NAME EXPORT_LOCATION [daily|weekly|monthly|single]"
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
#	vsi="${3,,}"
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
	# Argument validation
	if [ $# -lt 4 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments missing! Syntax: bluexport.api $1 VSI_NAME VOLUMES_NAME TIER_TO_CHANGE_TO"
	fi
	if [ $# -gt 4 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments! Syntax: bluexport.api $1 VSI_NAME VOLUMES_NAME TIER_TO_CHANGE_TO"
	fi
	# Volume name patterns (space-separated list in $3)
	IFS=' ' read -r -a volchtier_names <<< "$3"
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Common name of volumes to change to tier $tier: ${volchtier_names[*]}" "1"
#	vsi="${2,,}"
	vsi=$2
	vsi_id_bluexscrt
	check_locally_VSI_exists
	# Build JSON array with volume name patterns for jq
	vol_patterns_json=$(printf '%s\n' "${volchtier_names[@]}" | jq -R . | jq -s .)
	# Get attached volumes for this VSI via API and filter by name patterns
	ins_vol_ls | jq -r --argjson patterns "$vol_patterns_json" '.volumes[]? | select([ $patterns[] as $p | (.name | contains($p)) ] | any) | "\(.volumeID) \(.name)"' > "$volumes_file" 2>>"$log_file"
	# Extract IDs (comma-separated) and names (space-separated)
	volumes=$(awk '{print $1}' "$volumes_file" | paste -sd, -)
	volumes_name=$(awk '{print $2}' "$volumes_file" | tr '\n' ' ')
	vchtier
    ;;

  -insvchtier)
	tier="tier$3"
	test=0
	flagj=1
	# Argument validation
	if [ $# -lt 3 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments missing! Syntax: bluexport.api $1 VSI_NAME TIER_TO_CHANGE_TO"
	fi
	if [ $# -gt 3 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments! Syntax: bluexport.api $1 VSI_NAME TIER_TO_CHANGE_TO"
	fi
#	vsi="${2,,}"
	vsi=$2
	vsi_id_bluexscrt
	check_locally_VSI_exists
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Changing ALL volumes of VSI $vsi_cloud_name to tier $tier..." "1"
	# List ALL volumes attached to this VSI
	ins_vol_ls | jq -r '.volumes[]? | "\(.volumeID) \(.name)"' > "$volumes_file" 2>>"$log_file"
	volumes=$(awk '{print $1}' "$volumes_file" | paste -sd, -)
	volumes_name=$(awk '{print $2}' "$volumes_file" | tr '\n' ' ')
	vchtier
    ;;


  -chscrt)
	if [ $# -lt 2 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Arguments Missing!! Syntax: bluexport.api $1 bluexscrt_file_name - Use the full path ex: /home/user/bluexscrt_new"
	fi
	if [ $# -gt 2 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport.api $1 bluexscrt_file_name - Use the full path ex: /home/user/bluexscrt_new"
	fi
	new_scrt=$2
	jq --arg new "$new_scrt" '.bluexscrt = $new' "$conf_file" > "$conf_file.tmp" && mv "$conf_file.tmp" "$conf_file"
	abort "`date +%Y-%m-%d_%H:%M:%S` - Secret file changed to $new_scrt !"
    ;;

  -viewscrt)
    if [ $# -gt 1 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport.api $1"
	fi
	scrt_in_use=$(jq -r '.bluexscrt' "$conf_file")
	abort "`date +%Y-%m-%d_%H:%M:%S` - Secret file in use is $scrt_in_use"
    ;;

  -snapcr)
	if [ $# -lt 5 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Arguments Missing!! Syntax: bluexport.api $1 LPAR_NAME SNAPSHOT_NAME 0|\"DESCRIPTION\" 0|[Comma separated Volumes name list to snap]"
	fi
	if [ $# -gt 5 ] 
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport.api $1 LPAR_NAME SNAPSHOT_NAME 0|\"DESCRIPTION\" 0|[Comma separated Volumes name list to snap]"
	fi
#	vsi="${2,,}"
	vsi=$2
	vsi_id_bluexscrt
	test=0
	snap_name=$3
##########!!!!!!!!!!!	snap_name_exists=$(/usr/local/bin/ibmcloud pi ins snap ls | grep -w $snap_name)
	if [[ "$snap_name_exists" != "" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Already exists one Snapshot with name $snap_name, please choose a diferent name or use flag -snapupd to change the name."
	fi
	description=$4
	if [ -n "$description" ] && [ "$description" -eq "$description" ] 2>/dev/null
	then
		if [ $4 -eq 0 ]
		then
			description=""
		else
			abort "`date +%Y-%m-%d_%H:%M:%S` - Argument DESCRIPTION must be 0 or a phrase inside quotes!! Syntax: bluexport.api $1 LPAR_NAME SNAPSHOT_NAME 0|[\"DESCRIPTION\"] 0|[VOLUMES - Comma separated Volumes name list to snap]"
		fi
	else
		description="--description \""$description"\""
	fi
	volumes_to_snap=$5
	if [ -n "$volumes_to_snap" ] && [ "$volumes_to_snap" -eq "$volumes_to_snap" ] 2>/dev/null
	then
		if [ $5 -eq 0 ]
		then
			flag_volumes=""
			volumes_to_snap=""
			volumes_to_echo="ALL"
		else
			abort "`date +%Y-%m-%d_%H:%M:%S` - Argument VOLUMES must be 0 or comma separated names or IDs!! Syntax: bluexport.api $1 LPAR_NAME SNAPSHOT_NAME 0|[\"DESCRIPTION\"] 0|[VOLUMES - Comma separated Volumes name list to snap]"
		fi
	else
		flag_volumes="--volumes "
		volumes_to_echo=$volumes_to_snap
#		volumes_to_snap="--volumes "$volumes_to_snap
	fi
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - === Starting Snapshot $snap_name of VSI $vsi with volumes: $volumes_to_echo !" "1"
	check_locally_VSI_exists
	do_snap_create
	abort "`date +%Y-%m-%d_%H:%M:%S` - === Successfully finished Snapshot $snap_name of VSI $vsi with volumes: $volumes_to_echo !"
    ;;

  -snapupd)
	if [ $# -lt 5 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Arguments Missing!! Syntax: bluexport.api $1 VSI_NAME SNAPSHOT_NAME 0|[NEW_SNAPSHOT_NAME] 0|[\"DESCRIPTION\"]"
	fi
	if [ $# -gt 5 ] 
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport.api $1 VSI_NAME SNAPSHOT_NAME 0|[NEW_SNAPSHOT_NAME] 0|[\"DESCRIPTION\"]"
	fi
	test=0
	flagj=1
#	vsi="${2,,}"
	vsi=$2
	vsi_id_bluexscrt
	snap_name=$3
	desc=$5
	sname=$4
	if ([ -n "$desc" ] && [ "$desc" -eq "$desc" ] && [ -n "$sname" ] && [ "$sname" -eq "$sname" ])2>/dev/null
	then
		if [ $4 -eq 0 ] && [ $5 -eq 0 ]
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` - You must pass at least one flag, DESCRIPTION or NEW_SNAPSHOT_NAME!..."
		fi
	fi
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - === Starting Snapshot $snap_name Update !" "1"
#	cloud_login
##############!!!!!!	snap_name_exists=$(/usr/local/bin/ibmcloud pi ins snap ls | grep -w $snap_name)
	if [[ "$snap_name_exists" == "" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Snapshot with name $snap_name does not exist, please choose a diferent name or use flag -snapcr to create one."
	fi
	description=$5
	if [ -n "$description" ] && [ "$description" -eq "$description" ] 2>/dev/null
	then
		if [ $5 -eq 0 ]
		then
			description=""
			new_description_echo=""
		else
			abort "`date +%Y-%m-%d_%H:%M:%S` - Argument DESCRIPTION must be 0 or a phrase inside quotes!! Syntax:  bluexport.api $1 VSI_NAME SNAPSHOT_NAME 0|[NEW_SNAPSHOT_NAME] 0|[\"DESCRIPTION\"]"
		fi
	else
		description="--description \""$description"\""
		new_description_echo="with new Description \"$5\""
	fi
	new_snap_name=$4
	if [ -n "$new_snap_name" ] && [ "$new_snap_name" -eq "$new_snap_name" ] 2>/dev/null
	then
		if [ $4 -eq 0 ]
		then
			new_name_echo=""
			new_name="--name \""$snap_name"\""
		else
			abort "`date +%Y-%m-%d_%H:%M:%S` - Argument NEW_SNAPSHOT_NAME must be 0 or a name!! Syntax:  bluexport.api $1 VSI_NAME SNAPSHOT_NAME 0|[NEW_SNAPSHOT_NAME] 0|[\"DESCRIPTION\"]"
		fi
	else
		if [[ "$new_snap_name" == "$snap_name" ]]
		then
			new_name_echo=""
		else
			new_name_echo="with new Name "$new_snap_name
			snap_name_new=$new_snap_name
			new_name="--name \""$new_snap_name"\""
		fi
	fi
	check_locally_VSI_exists
	do_snap_update
	abort "`date +%Y-%m-%d_%H:%M:%S` - === Successfully finished Snapshot $snap_name Update $new_name_echo !"
    ;;

  -snapdel)
        # Validate arguments
        if [ $# -lt 3 ]; then
            abort "$(date +%Y-%m-%d_%H:%M:%S) - Arguments Missing!! Syntax: bluexport.api $1 VSI_NAME SNAPSHOT_NAME"
        fi
        if [ $# -gt 3 ]; then
            abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments!! Syntax: bluexport.api $1 VSI_NAME SNAPSHOT_NAME"
        fi

        test=0
        flagj=1

        # Normalize VSI name to lowercase
        vsi=$2

        # Resolve VSI ID, workspace, CLOUD_INSTANCE_ID, CRN, etc.
        vsi_id_bluexscrt
	check_locally_VSI_exists
	dc_vsi_list
        snap_name="$3"
	do_snap_delete
    ;;

  -snaplsall)
        # Too many arguments?
        if [ $# -gt 1 ]
        then
                abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments!! Syntax: bluexport.api $1"
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
                echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - === Listing snapshots at workspace $full_ws_name :" "1"
                # Resolve region and base_url
                region_api=$(jq -r --arg k "$ws" '.workspaces[$k].crn
                        | capture("power-iaas:(?<region>[^:]+)")
                        | .region
                        | gsub("-"; "_")' "$bluexscrt")
                base_url_var="base_${region_api}"
                base_url="${!base_url_var}"
                # Call API to list snapshots via function snap_ls (API version)
                snaps_json=$(snap_ls 2>>"$log_file")
                # Check if there are snapshots
                if ! echo "$snaps_json" | jq -e '.snapshots | length > 0' >/dev/null 2>&1
                then
                        msg="----------------------- No Snapshots Found -----------------------"
                        echo "$msg" | tee -a "$log_file"
                else
                        # Transform snapshots into TSV to process in bash
                        echo "$snaps_json" | jq -r '
                              .snapshots // [] |
                              .[] |
                              [
                                .name,
                                .creationDate,
                                .lastUpdateDate,
                                .action,
                                .snapshotID,
                                .percentComplete,
                                .status,
                                .statusDetail,
                                .pvmInstanceID,
                                (.volumeSnapshots | tostring)
                              ] | @tsv
                        ' 2>>"$log_file" | \
                        while IFS=$'\t' read -r s_name s_cdate s_udate s_action s_id s_pct s_status s_sdetail s_pvmid s_vols
                        do
                                # Resolve Instance Name from config JSON for this workspace + pvmInstanceID
                                instname=$(jq -r --arg ws "$ws" --arg id "$s_pvmid" '
                                        (.systems // [])
                                        | map(select(.workspace == $ws and .pvmInstanceID == $id))
                                        | if length > 0 then .[0].name else "NOT-IN-CONFIG" end
                                ' "$bluexscrt")

                                {
                                        echo "----------------------- Snapshot Found -----------------------"
                                        echo "Name: $s_name"
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
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Too many arguments!! Syntax: bluexport.api $1"
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

            echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - === Listing Volume Clones at Workspace $full_ws_name :" "1"

            # Resolve region and base_url from CRN
            region_api=$(jq -r --arg k "$ws" '.workspaces[$k].crn
                    | capture("power-iaas:(?<region>[^:]+)")
                    | .region
                    | gsub("-"; "_")' "$bluexscrt")
            base_url_var="base_${region_api}"
            base_url="${!base_url_var}"

            # Call API to list volume clones
            clones_json=$(vol_cl_ls 2>>"$log_file")

            # Check if there are volume clones
            if ! echo "$clones_json" | jq -e '(.volumeClones // .clones // []) | length > 0' >/dev/null 2>&1
            then
                msg="----------------------- No Volume Clones Found -----------------------"
                echo "$msg" | tee -a "$log_file"
            else
                # Pretty formatted output – try to be tolerant to field names
                echo "$clones_json" | jq -r '
                  (.volumeClones // .clones // [])[] |
                  "----------------------- Volume Clone Found -----------------------\n"
                  + "Clone ID: \(.volumeCloneID // .cloneID // \"N/A\")\n"
                  + "Name: \(.name // .cloneName // \"N/A\")\n"
                  + "Source Volume ID: \(.sourceVolumeID // .originVolumeID // \"N/A\")\n"
                  + "Status: \(.status // \"N/A\")\n"
                  + "Percent Complete: \(.percentComplete // .percentageComplete // \"N/A\")\n"
                  + "Creation Date: \(.creationDate // \"N/A\")\n"
                  + "------------------------------------------------------------"
                ' 2>>"$log_file" | tee -a "$log_file"
            fi

            echoscreen "" "1"
        done

        abort "$(date +%Y-%m-%d_%H:%M:%S) - === Finished Listing all Volume Clones in all Workpsaces"
    ;;
#
   -vclone)
	if [ $# -lt 8 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Arguments Missing!! Syntax: bluexport.api $1 VOLUME_CLONE_NAME BASE_NAME LPAR_NAME (Replication)True|False (Rollback)True|False TARGET_STORAGE_TIER ALL|VOLUMES(Comma seperated Volumes name or IDs list to clone)"
	fi
	if [ $# -gt 8 ] 
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport.api $1 VOLUME_CLONE_NAME BASE_NAME LPAR_NAME (Replication)True|False (Rollback)True|False TARGET_STORAGE_TIER ALL|VOLUMES(Comma seperated Volumes name or IDs list to clone)"
	fi
	test=0
	vclone_name=$2
	base_name=$3
	vsi=$4
	vsi_id_bluexscrt
	replication=$5
	rollback=$6
	target_tier=$7
	volumes_to_clone=$8
	if [[ "$replication" != "True" ]] && [[ "$replication" != "False" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Replication value must be True or False...!"
	fi
	if [[ "$rollback" != "True" ]] && [[ "$rollback" != "False" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Rollback value must be True or False...!"
	fi
	if [[ "$target_tier" != "tier0" ]] && [[ "$target_tier" != "tier1" ]] && [[ "$target_tier" != "tier3" ]] && [[ "$target_tier" != "tier5k" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Target Tier must be tier0 or tier1 or tier3 or tier5k...!"
	fi
	vclone_name_exists=$(/usr/local/bin/ibmcloud pi vol cl ls | grep -w $vclone_name)
	if [[ "$vclone_name_exists" != "" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Volume Clone with name $vclone_name already exists, please choose a diferent name!"
	fi
	if [[ "$volumes_to_clone" == "ALL" ]]
	then
		volumes_to_clone=$(/usr/local/bin/ibmcloud pi ins get $vsi_id | grep Volumes | sed -z 's/ //g' | sed -z 's/Volumes//g')
	fi
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - === Starting the 3 processes of Volume Clone $vclone_name" "1"
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - This is the list of volumes that will be cloned: $volumes_to_clone" "1"
	do_volume_clone
	do_volume_clone_start
	do_volume_clone_execute
	abort "`date +%Y-%m-%d_%H:%M:%S` - === Successfully finished -  Volume Clone $vclone_name !"
    ;;

  -vclonedel)
	if [ $# -lt 2 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Arguments Missing!! Syntax: bluexport.api $1 VOLUME_CLONE_NAME"
	fi
	if [ $# -gt 2 ] 
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport.api $1 VOLUME_CLONE_NAME"
	fi
	test=0
	vclone_name=$2
###########!!!!!!!!!!!!!	vclone_name_exists=$(/usr/local/bin/ibmcloud pi vol cl ls | grep -w $vclone_name)
	if [[ "$vclone_name_exists" == "" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Volume Clone with name $vclone_name doesn't exists, please choose a diferent name!"
	fi
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - === Trying to Delete Volume Clone with name $vclone_name" "1"
############!!!!!!!!!!!!!	vclone_id=$(/usr/local/bin/ibmcloud pi vol cl ls | grep -A6 $vclone_name | grep "Volume Clone Request ID:" | awk {'print $5'})
################!!!!!!!!!!!	/usr/local/bin/ibmcloud pi vol cl del $vclone_id
	abort "`date +%Y-%m-%d_%H:%M:%S` - === Successfully Deleted Volume Clone with name $vclone_name !"
    ;;

   -expimg)
	abort "`date +%Y-%m-%d_%H:%M:%S` - Under construction!!"
    ;;

   -createvg)
	if [ $# -gt 4 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport.api $1 LPAR_NAME -vg VG_NAME"
	fi
	if [ $# -lt 4 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Arguments missing!! Syntax: bluexport.api $1 LPAR_NAME -vg VG_NAME"
	fi
	flagvg=$3
	if [[ "$flagvg" == "-vg" ]]
	then
		vg_flag="--volume-group-name"
		vg_flag_echo="Volume Group"
	else
		abort "`date +%Y-%m-%d_%H:%M:%S` - Argument 3 must be -vg"
	fi
#	vsi="${2,,}"
	vsi=$2
	vg_name=$4
	create_vg
	abort "`date +%Y-%m-%d_%H:%M:%S` - === Successfully Create $vg_flag_echo $vg_name !"
    ;;

   -onboard)
	if [ $# -gt 3 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport.api $1 LPAR_NAME SHORT_NAME_TARGET_WS"
	fi
	if [ $# -lt 3 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Arguments missing!! Syntax: bluexport.api $1 LPAR_NAME SHORT_NAME_TARGET_WS"
	fi
#	vsi="${2,,}"
	vsi=$2
	target_short_ws=$3
	target_ws_crn=$(cat $bluexscrt | grep -w $target_short_ws | head -n1 | awk {'print $2'})
	if [[ "$target_ws_crn" == "" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Workspace with Shortname $target_short_ws does not exist in $bluexscrt file... Aborting!..."
	fi
	onboard_aux_vol
	abort "`date +%Y-%m-%d_%H:%M:%S` - === Successfully Onboarded LPAR $vsi !"
    ;;

   -crgrs)
	abort "`date +%Y-%m-%d_%H:%M:%S` - Under construction!!"
    ;;

   -failover)
	abort "`date +%Y-%m-%d_%H:%M:%S` - Under construction!!"
    ;;

   -failback)
	abort "`date +%Y-%m-%d_%H:%M:%S` - Under construction!!"
    ;;

   -v | --version)
    if [ $# -gt 1 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport.api -v | --version"
	fi
    echoscreen ""
	echoscreen "  ### bluexport by Ricardo Martins - Blue Chip Portugal - 2023-2025"
	abort "`date +%Y-%m-%d_%H:%M:%S` - Version: $Version"
    ;;

    *)
	if [ -t 1 ]
	then
		help
	fi
	abort "`date +%Y-%m-%d_%H:%M:%S` - Flag -a or -x Missing or invalid Flag!"
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
