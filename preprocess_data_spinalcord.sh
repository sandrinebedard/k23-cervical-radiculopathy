#!/bin/bash
#
# Analayses spinal cord data for the K23 Cervical Radiculopathy project
#
# Usage:
#     sct_run_batch -c <PATH_TO_REPO>/etc/config_process_data.json
#
# The following global variables are retrieved from the caller sct_run_batch
# but could be overwritten by uncommenting the lines below:
# PATH_DATA_PROCESSED="~/data_processed"
# PATH_RESULTS="~/results"
# PATH_LOG="~/log"
# PATH_QC="~/qc"
#
#
#
# Manual segmentations or labels should be located under:
# PATH_DATA/derivatives/labels/SUBJECT/ses-0X/anat/
#
#
#
# Authors: Sandrine Bedard and Kenneth Weber
#

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

# CONVENIENCE FUNCTIONS
# ======================================================================================================================
segment_if_does_not_exist() {
  ###
  #  This function checks if a manual spinal cord segmentation file already exists, then:
  #    - If it does, copy it locally.
  #    - If it doesn't, perform automatic spinal cord segmentation
  #  This allows you to add manual segmentations on a subject-by-subject basis without disrupting the pipeline.
  ###
  local file="$1"
  local contrast="$2"
  local segmentation_method="$3"  # deepseg or propseg
  # Update global variable with segmentation file name
  FILESEG="${file}_label-SC_mask"
  FILESEGMANUAL="${PATH_DERIVATIVES}/${SUBJECT}/anat/${FILESEG}-manual.nii.gz"
  echo
  echo "Looking for manual segmentation: $FILESEGMANUAL"
  if [[ -e $FILESEGMANUAL ]]; then
    echo "Found! Using manual segmentation."
    rsync -avzh $FILESEGMANUAL ${FILESEG}.nii.gz
    sct_qc -i ${file}.nii.gz -s ${FILESEG}.nii.gz -p sct_deepseg_sc -qc ${PATH_QC} -qc-subject ${SUBJECT}
    # Rename manual seg to seg name
    mv ${FILESEG}.nii.gz ${file}_seg.nii.gz
  else
    echo "Not found. Proceeding with automatic segmentation."
    # Segment spinal cord
    if [[ $segmentation_method == 'deepseg' ]];then
        sct_deepseg_sc -i ${file}.nii.gz -c ${contrast} -qc ${PATH_QC} -qc-subject ${SUBJECT}
    elif [[ $segmentation_method == 'propseg' ]]; then
        sct_propseg -i ${file}.nii.gz -c ${contrast} -qc ${PATH_QC} -qc-subject ${SUBJECT}
    fi
  fi
}

label_if_does_not_exist(){
  ###
  #  This function checks if a manual labels exists, then:
  #    - If it does, copy it locally and use them to initialize vertebral labeling
  #    - If it doesn't, perform automatic vertebral labeling
  ###
  local file="$1"
  local file_seg="$2"
  # Update global variable with segmentation file name
  FILELABEL="${file}_labels"
  FILELABELMANUAL="${PATH_DERIVATIVES}/${SUBJECT}/anat/${FILELABEL}-manual.nii.gz"
  echo "Looking for manual label: $FILELABELMANUAL"
  if [[ -e $FILELABELMANUAL ]]; then
    echo "Found! Using manual labels."
    rsync -avzh $FILELABELMANUAL ${FILELABEL}.nii.gz
    # Generate labeled segmentation from manual disc labels
    sct_label_vertebrae -i ${file}.nii.gz -s ${file_seg}.nii.gz -discfile ${FILELABEL}.nii.gz -c t2 -qc ${PATH_QC} -qc-subject ${SUBJECT}
  else
    echo "Not found. Proceeding with automatic labeling."
    # Generate vertebral labeling
    sct_label_vertebrae -i ${file}.nii.gz -s ${file_seg}.nii.gz -c t2 -qc ${PATH_QC} -qc-subject ${SUBJECT}
  fi
}

# Retrieve input params and other params
SUBJECT=$1

# get starting time:
start=`date +%s`


# SCRIPT STARTS HERE
# ==============================================================================
# Display useful info for the log, such as SCT version, RAM and CPU cores available
sct_check_dependencies -short

# Go to folder where data will be copied and processed
cd $PATH_DATA_PROCESSED

# Copy BIDS-required files to processed data folder (e.g. list of participants)
if [[ ! -f "participants.tsv" ]]; then
  rsync -avzh $PATH_DATA/participants.tsv .
fi
# Copy list of participants in results folder 
#if [[ ! -f "participants.json" ]]; then
#  rsync -avzh $PATH_DATA/participants.json .
#fi
if [[ ! -f "dataset_description.json" ]]; then
  rsync -avzh $PATH_DATA/dataset_description.json .
fi

# Copy source images
# Note: we use '/./' in order to include the sub-folder 'ses-0X'
rsync -Ravzh $PATH_DATA/./$SUBJECT .

cd ${SUBJECT}/anat

# Define variables
# We do a substitution '/' --> '_' in case there is a subfolder 'ses-0X/'
file="${SUBJECT//[\/]/_}"

# TODO: exclude ses-brain!!!
<<comment
# -------------------------------------------------------------------------
# T2w
# -------------------------------------------------------------------------

# Add suffix corresponding to contrast
file_t2w=${file}_T2w
# Check if T2w image exists
if [[ -f ${file_t2w}.nii.gz ]];then
    # Create directory for T2w results
    mkdir -p ${PATH_DATA_PROCESSED}/${SUBJECT}/anat/T2w
    cp ${file_t2w}.nii.gz ${PATH_DATA_PROCESSED}/${SUBJECT}/anat/T2w
    cd T2w
    
    # Do we reorient?

    # Spinal cord segmentation
    # Note: For T2w images, we use sct_deepseg_sc with 2d kernel. Generally, it works better than sct_propseg and sct_deepseg_sc with 3d kernel.
    segment_if_does_not_exist ${file_t2w} 't2' 'deepseg'
    file_t2_seg="${file_t2w}_seg"

    # Vertebral labeling 
    label_if_does_not_exist ${file_t2w} ${file_t2w}_seg
    file_t2_labels="${file_t2w}_seg_labeled"
    file_t2_labels_discs="${file_t2w}_seg_labeled_discs"

    # Extract dics 3 and 7 for registration to template
    sct_label_utils -i ${file_t2_labels_discs}.nii.gz -keep 3,7 -o ${file_t2_labels_discs}_3_7.nii.gz
    file_t2_labels_discs="${file_t2w}_seg_labeled_discs_3_7"

    # Register T2w image to PAM50 template
    sct_register_to_template -i ${file_t2w}.nii.gz -s ${file_t2_seg}.nii.gz -ldisc ${file_t2_labels_discs}.nii.gz -c t2 -qc ${PATH_QC} -qc-subject ${SUBJECT}
    
    # TODO:
    # - Add CSA computation where?
    cd ..
else
	echo Skipping T2w
fi


# -------------------------------------------------------------------------
# T2star
# -------------------------------------------------------------------------
# Add suffix corresponding to contrast
file_t2star=${file}_T2star
# Check if T2star image exists
if [[ -f ${file_t2star}.nii.gz ]];then
    # Create directory for T2star results
    mkdir -p ${PATH_DATA_PROCESSED}/${SUBJECT}/anat/T2star
    cp ${file_t2star}.nii.gz ${PATH_DATA_PROCESSED}/${SUBJECT}/anat/T2star
    cd T2star

    # Spinal cord segmentation
    segment_if_does_not_exist ${file_t2star} 't2s' 'deepseg'
    file_t2star_seg="${file_t2star}_seg"

    # TODO add function for GM seg to use manual seg
    # Spinal cord GM segmentation
	sct_deepseg_gm -i ${file_t2star}.nii.gz -qc ${PATH_QC} -qc-subject ${SUBJECT}
    file_t2star_gmseg="${file_t2star}_gmseg"
    
    # Get WM segmentation by subtracting SC cord segmentation with GM segmentation
	sct_maths -i ${file_t2star_seg}.nii.gz -sub ${file_t2star_gmseg}.nii.gz -o ${file_t2star}_wmseg.nii.gz
    file_t2star_wmseg="${file_t2star}_wmseg"

    # Register PAM50 T2s template to T2star using the WM segmentation
	sct_register_multimodal -i ${SCT_DIR}/data/PAM50/template/PAM50_t2s.nii.gz -iseg ${SCT_DIR}/data/PAM50/template/PAM50_wm.nii.gz -d ${file_t2star}.nii.gz -dseg ${file_t2star_wmseg}.nii.gz -param step=1,type=seg,algo=rigid:step=2,type=seg,algo=bsplinesyn,slicewise=1,iter=3 -initwarp ../T2w/warp_template2anat.nii.gz -initwarpinv ../T2w/warp_anat2template.nii.gz -qc ${PATH_QC} -qc-subject ${SUBJECT}
	
    # Bring PAM50 template to T2star space
	sct_warp_template -d ${file_t2star}.nii.gz -w warp_PAM50_t2s2${file_t2star}.nii.gz -qc ${PATH_QC} -qc-subject ${SUBJECT}

    # TODO:
    # - add GM CSA measures

    cd ..
else
	echo Skipping T2star
fi


# -------------------------------------------------------------------------
# MTS
# -------------------------------------------------------------------------
# Add suffix corresponding to contrast
file_MTS_t1w="${file}_acq-T1w_MTS"
file_mton="${file}_acq-MTon_MTS"
file_mtoff="${file}_acq-MToff_MTS"

# Check if all MTS images exists
if [[ -e "${file_MTS_t1w}.nii.gz" && -e "${file_mton}.nii.gz" && -e "${file_mtoff}.nii.gz" ]]; then

    # Create directory for MTS results
    mkdir -p ${PATH_DATA_PROCESSED}/${SUBJECT}/anat/MTS
    # Copy files to processing folder
    cp ${file_MTS_t1w}.nii.gz ${PATH_DATA_PROCESSED}/${SUBJECT}/anat/MTS
    cp ${file_MTS_t1w}.json ${PATH_DATA_PROCESSED}/${SUBJECT}/anat/MTS
    cp ${file_mton}.nii.gz ${PATH_DATA_PROCESSED}/${SUBJECT}/anat/MTS
    cp ${file_mton}.json ${PATH_DATA_PROCESSED}/${SUBJECT}/anat/MTS
    cp ${file_mtoff}.nii.gz ${PATH_DATA_PROCESSED}/${SUBJECT}/anat/MTS
    cp ${file_mtoff}.json ${PATH_DATA_PROCESSED}/${SUBJECT}/anat/MTS
    cd MTS

    # Spinal cord segmentation of MT-on contrast
    segment_if_does_not_exist ${file_mton} 't2' 'deepseg'  # TODO test with t2s too
    file_mton_seg="${file_mton}_seg"

    # Create a mask arround the spinal cord to help co-register all MTS contrasts
    sct_create_mask -i ${file_mton}.nii.gz -p centerline,${file_mton_seg}.nii.gz -size 35mm -f cylinder -o ${file_mton}_mask.nii.gz
    file_mton_mask="${file_mton}_mask"
    # Co-register all 3 MTS contrasts
	sct_register_multimodal -i ${file_mtoff}.nii.gz -d ${file_mton}.nii.gz -dseg ${file_mton_seg}.nii.gz -param step=1,type=im,algo=slicereg,metric=CC -m ${file_mton_mask}.nii.gz -x spline -qc ${PATH_QC} -qc-subject ${SUBJECT}
	sct_register_multimodal -i ${file_MTS_t1w}.nii.gz -d ${file_mton}.nii.gz -dseg ${file_mton_seg}.nii.gz -param step=1,type=im,algo=slicereg,metric=CC -m ${file_mton_mask}.nii.gz -x spline -qc ${PATH_QC} -qc-subject ${SUBJECT}

    #Compute mtr. sct_compute_mtr was not working correctly so used fslmaths
	fslmaths ${file_mtoff}_reg -sub ${file_mton} -div ${file_mtoff}_reg -mul 100 mtr
	# TODO test sct_compute_mtr
    sct_compute_mtr -mt0 ${file_mtoff}.nii.gz -mt1 ${file_mton}.nii.gz
    # TODO: could also use t1w MTS and register to T1w template
    # Resgister PAM50 t2star template to MTon
	sct_register_multimodal -i ${SCT_DIR}/data/PAM50/template/PAM50_t2s.nii.gz -iseg ${SCT_DIR}/data/PAM50/template/PAM50_wm.nii.gz -d ${file_mton}.nii.gz -dseg ${file_mton_seg}.nii.gz -param step=1,type=seg,algo=rigid:step=2,type=seg,algo=bsplinesyn,slicewise=1,iter=3 -initwarp ../T2star/warp_PAM50_t2s2${file_t2star}.nii.gz -initwarpinv ../T2star/warp_${file_t2star}2PAM50_t2s.nii.gz -qc ${PATH_QC} -qc-subject ${SUBJECT}
	# Could use MTS_t1w also for registration

    # Warp template to MTon space
	sct_warp_template -d ${file_mton}.nii.gz -w warp_PAM50_t2s2${file_mton}.nii.gz -qc ${PATH_QC} -qc-subject ${SUBJECT}
    
    # TODO
    # Do we want MTsat
    # Do we want to extract metrics at certain levels? regions of interest?
    cd ..
else
  echo "WARNING: MTS dataset is incomplete."
fi

comment

# -------------------------------------------------------------------------
# DWI
# -------------------------------------------------------------------------
cd ../dwi
# Add suffix corresponding to contrast
file_dwi="${file}_dwi"
file_bval=${file_dwi}.bval
file_bvec=${file_dwi}.bvec

file_t2star=${file}_T2star  # TO REMOVE WHEN NO COMMENTS

# Check if all DWI files exists
if [[ -e "${file_dwi}.nii.gz" && -e "${file_bval}" && -e "${file_bvec}" ]]; then

    # ADDED BY ME: separte B0 and DWI???
    sct_dmri_separate_b0_and_dwi -i ${file_dwi}.nii.gz -bvec ${file_bvec}

    # Segment spinal cord
    segment_if_does_not_exist ${file_dwi}_dwi_mean 'dwi' 'deepseg'

    # Create mask arround the spinal cord
    sct_create_mask -i ${file_dwi}_dwi_mean.nii.gz -p centerline,${file_dwi}_dwi_mean_seg.nii.gz -size 35mm -o ${file_dwi}_dwi_mean_mask.nii.gz

    # Motion correction
    sct_dmri_moco -i ${file_dwi}.nii.gz -bvec ${file_bvec} -m ${file_dwi}_dwi_mean_mask.nii.gz -x spline -qc ${PATH_QC} -qc-subject ${SUBJECT} -qc-seg ${file_dwi}_dwi_mean_seg.nii.gz
    file_dwi=${file_dwi}_moco
    file_dwi_mean=${file_dwi}_dwi_mean

    # Segment spinal cord (only if it does not exist)
    segment_if_does_not_exist ${file_dwi_mean} 'dwi' 'deepseg'
    file_dwi_seg=${file_dwi_mean}_seg

    # Register PAM50 T1w to dwi
    sct_register_multimodal -i ${SCT_DIR}/data/PAM50/template/PAM50_t1.nii.gz -iseg ${SCT_DIR}/data/PAM50/template/PAM50_cord.nii.gz -d ${file_dwi_mean}.nii.gz -dseg ${file_dwi_seg}.nii.gz -param step=1,type=seg,algo=centermass:step=2,type=seg,algo=bsplinesyn,slicewise=1,iter=3 -initwarp ../anat/T2star/warp_PAM50_t2s2${file_t2star}.nii.gz -initwarpinv ../anat/T2star/warp_${file_t2star}2PAM50_t2s.nii.gz -qc ${PATH_QC} -qc-subject ${SUBJECT}
    sct_warp_template -d ${file_dwi_mean}.nii.gz -w warp_PAM50_t12${file_dwi_mean}.nii.gz -qc ${PATH_QC} -qc-subject ${SUBJECT}

    ## Create mask around the spinal cord (for faster computing)
    sct_maths -i ${file_dwi_seg}.nii.gz -dilate 1 -shape ball -o ${file_dwi_seg}_dil.nii.gz

    # Compute DTI
    sct_dmri_compute_dti -i ${file_dwi}.nii.gz -bvec ${file_bvec} -bval ${file_bval} -method standard -m ${file_dwi_seg}_dil.nii.gz -evecs 1
    
else
  echo "Skipping dwi"
fi


# -------------------------------------------------------------------------
# FUNC
# -------------------------------------------------------------------------
cd ../func
file_task_rest_bold="${file}_task-rest_bold"
file_task_rest_physio="${file}_task-rest_physio"
# Check if all DWI files exists
if [[ -e "${file_task_rest_bold}.nii.gz" && -e "${file_task_rest_physio}.tsv"]]; then

    # Convert GE physio data to FSL format # TODO change for linux
    cp ${PATH_SCRIPTS}/utils/create_FSL_physio_text_file.m ./
    matlab.exe -nodisplay -nosplash -nodesktop -r "create_FSL_physio_text_file(${file_task_rest_physio},3.0,245)"
    rm create_FSL_physio_text_file.m

    # Run FSL physio
    pnm_stage1 -i ${file_task_rest_physio}.txt -o ./physio -s 100 --tr=3.0 --smoothcard=0.1 --smoothresp=0.1 --resp=2 --cardiac=4 --trigger=3 -v
	popp -i ${file_task_rest_physio}.txt -o ./physio -s 100 --tr=3.0 --smoothcard=0.1 --smoothresp=0.1 --resp=2 --cardiac=4 --trigger=3 -v
	pnm_evs -i ${file_task_rest_bold}.nii.gz -c physio_card.txt -r physio_resp.txt -o physio_ --tr=3.0 --oc=4 --or=4 --multc=2 --multr=2 --sliceorder=interleaved_up --slicedir=z
    
    mkdir PNM
	mv physio* ./PNM/
	mv ${file_task_rest_physio}.txt ./PNM/

    fslroi ${file_task_rest_bold} ${file_task_rest_bold}_mc1_ref 125 1

    # TODO: create mask

    # TODO motion correction

else
  echo "Skipping func"
fi


# Display useful info for the log
end=`date +%s`
runtime=$((end-start))
echo
echo "~~~"
echo "SCT version: `sct_version`"
echo "Ran on:      `uname -nsr`"
echo "Duration:    $(($runtime / 3600))hrs $((($runtime / 60) % 60))min $(($runtime % 60))sec"
echo "~~~"

