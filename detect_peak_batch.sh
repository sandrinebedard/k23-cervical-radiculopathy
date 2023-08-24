#!/bin/bash
#
# Detect cardiac peaks from physio data for the K23 Cervical Radiculopathy project
#
# Usage:
#     sct_run_batch 
#
# The following global variables are retrieved from the caller sct_run_batch
# but could be overwritten by uncommenting the lines below:
# PATH_DATA_PROCESSED="~/data_processed"
# PATH_RESULTS="~/results"
# PATH_LOG="~/log"
# PATH_QC="~/qc"
#
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
# Get path derivatives
path_source=$(dirname $PATH_DATA)
PATH_DERIVATIVES="${path_source}/derivatives/labels"

# Get path of script repository
PATH_SCRIPTS=$PWD

# Retrieve input params and other params
SUBJECT=$1
# Retrieve author name for json sidecar
NAME_RATER_1=$2
NAME_RATER_2=$3
NAME_RATER="$NAME_RATER_1 $NAME_RATER_2"
echo 'Raters name' $NAME_RATER

# get starting time:
start=`date +%s`


# SCRIPT STARTS HERE
# ==============================================================================
# Go to folder where data will be copied and processed
cd $PATH_DATA_PROCESSED

# Copy func images
# Note: we use '/./' in order to include the sub-folder 'ses-0X'
rsync -Ravzh $PATH_DATA/./$SUBJECT/func .

cd ${SUBJECT}/func

# Define variables
# We do a substitution '/' --> '_' in case there is a subfolder 'ses-0X/'
file="${SUBJECT//[\/]/_}"

# Get session
SES=$(basename "$SUBJECT")

file_task_rest_physio="${file}_task-rest_physio"
# Check if physio files exists
if [[ -f ${file_task_rest_physio}.tsv ]];then

    # Convert physio file to FSL format
    python3 ${PATH_SCRIPTS}/pnm/create_FSL_physio_text_file.py -i ${file_task_rest_physio}.tsv -TR 3.0 -number-of-volumes 245
    # Detect cardiac peaks, visual check, save timepoints.
    python3 ${PATH_SCRIPTS}/pnm/detect_peak_pnm.py -i ${file_task_rest_physio}.txt -exclude-resp -o ${file_task_rest_physio}_peak.txt -min-peak-dist 68 # TO CHANGE IF DOESN'T WORK

    # Create a derivatives diretory in data_processed to physio file with peaks
    mkdir -p $PATH_DATA_PROCESSED/derivatives/labels/${SUBJECT}/func
    # Copy the cardiac peaks file to derivatives
    rsync -avzh $PATH_DATA_PROCESSED/${SUBJECT}/func/${file_task_rest_physio}_peak.txt $PATH_DATA_PROCESSED/derivatives/labels/${SUBJECT}/func/${file_task_rest_physio}_peak.txt
    # Create a json side card
    python3 ${PATH_SCRIPTS}/utils/create_json.py -fname ${file_task_rest_physio}_peak.json -name-rater "${NAME_RATER}"
    # Copy json sidecar to derivatives
    rsync -avzh $PATH_DATA_PROCESSED/${SUBJECT}/func/${file_task_rest_physio}_peak.json $PATH_DATA_PROCESSED/derivatives/labels/${SUBJECT}/func/${file_task_rest_physio}_peak.json

else
    echo "${file_task_rest_physio}.tsv does not exists. Exiting"
fi


# Verify presence of output files and write log file if error
# ------------------------------------------------------------------------------
FILES_TO_CHECK=(
  "$PATH_DATA_PROCESSED/derivatives/labels/${SUBJECT}/func/${file_task_rest_physio}_peak.json" 
  "$PATH_DATA_PROCESSED/derivatives/labels/${SUBJECT}/func/${file_task_rest_physio}_peak.txt"
)
pwd
for file in ${FILES_TO_CHECK[@]}; do
  if [[ ! -e $file ]]; then
    echo "${SUBJECT}/anat/${file} does not exist" >> $PATH_LOG/_error_check_output_files.log
  fi
done


# Display useful info for the log
end=`date +%s`
runtime=$((end-start))
echo
echo "~~~"
echo "SCT version: `sct_version`"
echo "Ran on:      `uname -nsr`"
echo "Duration:    $(($runtime / 3600))hrs $((($runtime / 60) % 60))min $(($runtime % 60))sec"
echo "~~~"
