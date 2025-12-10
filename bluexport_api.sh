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
	echoscreen "Update snapshot:              ./bluexport_api.sh -snapupd  SNAPSHOT_NAME 0|[NEW_SNAPSHOT_NAME] 0|[DESCRIPTION]"
	echoscreen "Delete snapshot:              ./bluexport_api.sh -snapdel  SNAPSHOT_NAME"
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

snap_cr() {
	curl -sX POST $base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/pvm-instances/$PVM_ID/snapshots -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -d "{$ACTIONS}"
}

snap_del() {
	curl -sX DELETE $base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/snapshots/$SNAP_ID -H "$header_auth" -H "CRN: $CRN" -H "$header_json"
}

snap_upd() {
	curl -sX PUT $base_url/pcloud/v1/cloud-instances/$CLOUD_INSTANCE_ID/snapshots/$SNAP_ID -H "$header_auth" -H "CRN: $CRN" -H "$header_json" -d "{$ACTIONS}"
}
#### END:FUNCTIONS - API Commands ####

#### START:FUNCTIONS - GRS Code Helpers ####
## Helper: check and enable replication on volumes, then wait until all are replicationEnabled=true
chk_vol_rep() {
	echoscreen "" "1"
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Checking and enabling replication on source volumes if needed..." "1"
	echoscreen "" "1"
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
			vol_act 2>>"$log_file" | tee -a "$log_file" >/dev/null
		fi
		printf "."
	done
	echo
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
		if vol_ls | jq -r '.volumes[]? | "\(.name) \(.mirroringState)"' | grep -w "$vol_com_name" | grep inconsistent_copying >/dev/null
		then
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Volumes still in inconsistent_copying. Waiting 60 seconds..." "1"
			sleep 60
		else
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - All volumes are in consistent_copying state." "1"
			break
		fi
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
			if [[ $? -ne 0 ]]
			then
				abort "$(date +%Y-%m-%d_%H:%M:%S) - ERRO: ligação SSH falhou ou deu timeout, abortando..."
			fi


			if [[ -n "$iasp_names" ]]
			then
				for iasp_name in $iasp_names
				do
					echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Flushing Memory to Disk for $iasp_name ..." "1"
					ssh -T -i "$sshkeypath" "$vsi_user@$vsi_ip" "system \"CHGASPACT ASPDEV('$iasp_name') OPTION(*FRCWRT)\"" >> "$log_file" | tee -a "$log_file"
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
	flush_asps
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - == Executing Volume Clone with name $vclone_name ..." "1"
	if [[ -z "$vclone_id" ]]; then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - vclone_id not set before do_volume_clone_execute."
	fi
	VOL_CLONE_ID="$vclone_id"
	# Chamada API para execute
	local resp_ex
	resp_ex=$(vol_cl_ex 2>>"$log_file")
	if [ $? -ne 0 ]; then
		echo "$resp_ex" >>"$log_file"
		abort "$(date +%Y-%m-%d_%H:%M:%S) - FAILED - Error executing Volume Clone $vclone_name (API call failed)."
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
	vsi_ip=$(jq -r --arg name "$vsi" '.systems[] | select(.name == $name) | .ip' "$bluexscrt")
	vsi_id=$(jq -r --arg name "$vsi" '.systems[] | select(.name == $name) | .pvmInstanceID' "$bluexscrt")
	PVM_ID="$vsi_id"
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

####  START:FUNCTION  Main GRS function: create VG in source and onboard aux volumes in target  ####
create_grs() {
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - === Starting GRS configuration between source VSI $source_vsi and target VSI $target_vsi (VG: $vg_name) ===" "1"
	echoscreen "" "1"
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
	volids_api=$(echo "$vol_ids" | sed 's/ /","/g')
	ACTIONS="\"name\": \"$vg_name\", \"volumeIDs\": [\"$volids_api\"]"
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Creating Volume Group $vg_name in source workspace..." "1"
	vg_cr 2>>"$log_file" | tee -a "$log_file" >/dev/null
	# Confirmar ID do VG
	VOLUME_GROUP_ID=$(vg_ls | jq -r --arg vg_name "$vg_name" '.volumeGroups[]? | select(.name == $vg_name) | .id' 2>>"$log_file")
	if [[ -z "$VOLUME_GROUP_ID" || "$VOLUME_GROUP_ID" == "null" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Could not find Volume Group ID for $vg_name after creation."
	fi
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Volume Group $vg_name created with ID $VOLUME_GROUP_ID." "1"
	# 2.6 – Obter nomes dos auxiliary volumes (auxVolumeName)
	auxvol_names=$(vg_rcr | jq -r '.remoteCopyRelationships[]? | .auxVolumeName' 2>>"$log_file")
	if [[ -z "$auxvol_names" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - No auxiliary volumes found in remote-copy relationships for $vg_name. Aborting."
	fi
	auxvolnames=$(echo "$auxvol_names" | tr ' ' ',')
	aux_count=$(echo "$auxvol_names" | wc -w)
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Found $aux_count auxiliary volumes for VG $vg_name." "1"
	# 2.7 – Boot volume aux name (apenas logging)
	bootvol_auxname=$(ins_vol_ls | jq -r '.volumes[]? | "\(.bootable) \(.auxVolumeName) \(.name)"' 2>>"$log_file" \
		| grep "$vol_com_name" | grep true | awk '{print $2}')
	if [[ -n "$bootvol_auxname" ]]
	then
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Boot auxiliary volume: $bootvol_auxname" "1"
	fi
	# 2.8 – Detalhes do VG e RCRs
	vg_sd 2>>"$log_file" | jq -r '"State: \(.state) - Number of Volumes: \(.numOfvols)"' | tee -a "$log_file"
	vg_get 2>>"$log_file" | tee -a "$log_file" >/dev/null
	vg_rcr 2>>"$log_file" | jq -r '.remoteCopyRelationships[]? | "Progress: \(.progress) -- RCR: \(.name) -- Master: \(.masterVolumeName)"' | tee -a "$log_file"
	cgname=$(vg_ls | jq -r --arg vg_name "$vg_name" '.volumeGroups[]? | select(.name == $vg_name) | .consistencyGroupName' 2>>"$log_file")
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
	auxvolnames_api=$(echo "$auxvolnames" | sed 's/,/"},{"auxVolumeName": "/g')

	ACTIONS=$(cat <<EOF
		"Volumes": [
		{
		"auxiliaryVolumes": [
			{
			"auxVolumeName": "$auxvolnames_api"
			}
			],
		"sourceCRN": "$source_ws_crn"
		}
		],
		"description": "$ondesc"
EOF
)
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Starting auxiliary volume onboarding on target workspace for VSI $target_vsi..." "1"
	on_cr 2>>"$log_file" | tee -a "$log_file" >/dev/null
	VOLUME_ONBOARDING_ID=$(on_ls | jq -r --arg desc "$ondesc" '[.onboardings[]? | select(.description == $desc)][-1].id' 2>>"$log_file")
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
	if [ $# -lt 2 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Arguments Missing!! Syntax: bluexport_api.sh $1 bluexscrt_file_name - Use the full path ex: /home/user/bluexscrt_new"
	fi
	if [ $# -gt 2 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport_api.sh $1 bluexscrt_file_name - Use the full path ex: /home/user/bluexscrt_new"
	fi
	new_scrt=$2
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
	replication="$5"
	rollback="$6"
	target_tier="$7"
	volumes_to_clone_arg="$8"
	# Validar replication / rollback
	if [[ "$replication" != "True" && "$replication" != "False" ]]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - Replication value must be True or False...!"
	fi
	if [[ "$rollback" != "True" && "$rollback" != "False" ]]
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
	flagj=1
	if [ $# -lt 2 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Arguments Missing!! Syntax: bluexport_api.sh $1 VOLUME_CLONE_NAME"
	fi
	if [ $# -gt 2 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport_api.sh $1 VOLUME_CLONE_NAME"
	fi
	test=0
	vclone_name=$2
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
		# Workspace human friendly name
		full_ws_name="${wsmap[$ws]}"
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - === Listing volumes clones at workspace $full_ws_name " "1"
		# Resolve region and base_url
		region_api=$(jq -r --arg k "$ws" '.workspaces[$k].crn | capture("power-iaas:(?<region>[^:]+)") | .region | gsub("-"; "_")' "$bluexscrt")
		base_url_var="base_${region_api}"
		base_url="${!base_url_var}"
		vclone_name_exists=$(vol_cl_ls | jq -r --arg vclname "$vclone_name" '.volumesClone[] | select(.name == $vclname) | .name')
		if [[ "$vclone_name_exists" == "" ]]
		then
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Volume Clone with name $vclone_name doesn't exists in Workspace $full_ws_name, moving on to next Workspace!" "1"
			continue
		fi
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - === Trying to Delete Volume Clone with name $vclone_name" "1"
		VOL_CLONE_ID=$(vol_cl_ls | jq -r --arg vclname "$vclone_name" '.volumesClone[] | select(.name == $vclname) | .volumesCloneID')
		vol_cl_del
		abort "`date +%Y-%m-%d_%H:%M:%S` - === Successfully Deleted Volume Clone with name $vclone_name !"
	done
    ;;

   -creategrs)
	# Syntax: bluexport.api -creategrs SOURCE_VSI TARGET_VSI VG_NAME SOURCE_VOLUME_NAMES TARGET_VOLUME_NAMES
	if [ $# -lt 6 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Arguments Missing!! Syntax: bluexport.api $1 SOURCE_VSI TARGET_VSI VG_NAME SOURCE_VOLUME_NAMES TARGET_VOLUME_NAMES"
	fi
	if [ $# -gt 6 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport.api $1 SOURCE_VSI TARGET_VSI VG_NAME SOURCE_VOLUME_NAMES TARGET_VOLUME_NAMES"
	fi
	test=0
	flagj=1    # não precisamos de iASP / flush aqui
	source_vsi=$2
	target_vsi=$3
	vg_name=$4
	vol_com_name=$5        # prefixo/nome comum dos volumes no SOURCE
	tgvol_com_name=$6      # mantido para futura lógica no TARGET (neste momento é apenas guardado)
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Validating source VSI $source_vsi and target VSI $target_vsi in config and in IBM Cloud..." "1"
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
  	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Both VSIs found and validated. Proceeding with GRS creation..." "1"
	create_grs
    ;;

   -v | --version)
    if [ $# -gt 1 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport_api.sh -v | --version"
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
