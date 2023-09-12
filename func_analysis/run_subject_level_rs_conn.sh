#!/bin/bash
#

# Authors: Sandrine Bédard

# Uncomment for full verbose
set -x

# Immediately exit if error
set -e -o pipefail

# Exit if user presses CTRL+C (Linux) or CMD+C (OSX)
trap "echo Caught Keyboard Interrupt within script. Exiting now.; exit" INT

# Print retrieved variables from sct_run_batch to the log (to allow easier debug)
echo "Retrieved variables from from the caller sct_run_batch:"
echo "PATH_DATA: ${PATH_DATA}"
echo "PATH_DATA_PROCESSED: ${PATH_DATA_PROCESSED}"
echo "PATH_RESULTS: ${PATH_RESULTS}"
echo "PATH_LOG: ${PATH_LOG}"
echo "PATH_QC: ${PATH_QC}"

# Get path of script repository
PATH_SCRIPTS=$PWD


# Retrieve input params and other params
SUBJECT=$1
PATH_DERIVATIVES=$2

# get starting time:
start=`date +%s`


# SCRIPT STARTS HERE
# ==============================================================================
# Display useful info for the log, such as SCT version, RAM and CPU cores available
sct_check_dependencies -short

# Go to folder where data will be copied and processed
cd $PATH_DATA_PROCESSED

# Copy source images
# Note: we use '/./' in order to include the sub-folder 'ses-0X'
rsync -Ravzh $PATH_DATA/./$SUBJECT/func/*_stc.nii.gz .
rsync -Ravzh $PATH_DATA/./$SUBJECT/func/*_stc2template.nii.gz .

cd ${SUBJECT}/func

# Define variables
# We do a substitution '/' --> '_' in case there is a subfolder 'ses-0X/'
file="${SUBJECT//[\/]/_}"

# Subject level
################

# Get path rois
path_rois="${PATH_DERIVATIVES}/${SUBJECT}/func/rois"

echo
echo "Looking for rois: $path_rois"
if [[ -e $path_rois ]]; then
    echo "Found! Using existing rois"
    mkdir -p ./label/rois
    rsync -avzh $path_rois/ ./label/rois
else
    echo "No existing rois found. Running roi creation"
    # Coping labels
    mkdir -p ./label
    rsync -avzh $PATH_DATA/./$SUBJECT/func/label/ ./label/
    python3 $PATH_SCRIPTS/create_roi.py -label $PWD/label -levels 4 5 6 7 -thr 0.5 -number-slices 1 -o ./label/rois
fi

# Running connectivity analysis
file_bold_clean=${file}_mc2_pnm_stc
python3 $PATH_SCRIPTS/analyse_func_rs.py -i ${file_bold_clean}.nii.gz -path-rois $PWD/label/rois -o $PATH_RESULTS/${file_bold_clean}_connectivity.csv

# Running connectivity analysis in template space
file_bold_clean_template=${file}_mc2_pnm_stc2template
python3 $PATH_SCRIPTS/analyse_func_rs.py -i ${file_bold_clean}.nii.gz -path-rois $PATH_DERIVATIVES/PAM50/func/rois -o $PATH_RESULTS/${file_bold_clean_template}_connectivity.csv



# TODO create derivatives folder and copy rois


# Display useful info for the log
end=`date +%s`
runtime=$((end-start))
echo
echo "~~~"
echo "SCT version: `sct_version`"
echo "Ran on:      `uname -nsr`"
echo "Duration:    $(($runtime / 3600))hrs $((($runtime / 60) % 60))min $(($runtime % 60))sec"
echo "~~~"

