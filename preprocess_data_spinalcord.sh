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
  FILESEG="${file}_seg"
  FILESEGMANUAL="${PATH_DERIVATIVES}/${SUBJECT}/anat/${FILESEG}.nii.gz"
  echo
  echo "Looking for manual segmentation: $FILESEGMANUAL"
  if [[ -e $FILESEGMANUAL ]]; then
    echo "Found! Using manual segmentation."
    rsync -avzh $FILESEGMANUAL ${FILESEG}.nii.gz
    sct_qc -i ${file}.nii.gz -s ${FILESEG}.nii.gz -p sct_deepseg_sc -qc ${PATH_QC} -qc-subject ${SUBJECT}
    # Rename manual seg to seg name
    #mv ${FILESEG}.nii.gz ${file}_seg.nii.gz
  else
    echo "Not found. Proceeding with automatic segmentation."
    # Segment spinal cord
    if [[ $segmentation_method == 'deepseg' ]];then
        sct_deepseg_sc -i ${file}.nii.gz -c ${contrast} -qc ${PATH_QC} -qc-subject ${SUBJECT}
    elif [[ $segmentation_method == 'propseg' ]]; then
        sct_propseg -i ${file}.nii.gz -c ${contrast} -qc ${PATH_QC} -qc-subject ${SUBJECT} -CSF
    fi
  fi
}


# Check if manual segmentation already exists. If it does, copy it locally. If
# it does not, perform seg.
segment_gm_if_does_not_exist(){
  local file="$1"
  #local contrast="$2"
  # Update global variable with segmentation file name
  FILESEG="${file}_gmseg"
  FILESEGMANUAL="${PATH_DERIVATIVES}/${SUBJECT}/anat/${FILESEG}.nii.gz"
  echo "Looking for manual segmentation: $FILESEGMANUAL"
  if [[ -e $FILESEGMANUAL ]]; then
    echo "Found! Using manual segmentation."
    rsync -avzh $FILESEGMANUAL ${FILESEG}.nii.gz
    sct_qc -i ${file}.nii.gz -s ${FILESEG}.nii.gz -p sct_deepseg_gm -qc ${PATH_QC} -qc-subject ${SUBJECT}
  else
    echo "Not found. Proceeding with automatic segmentation."
    # Segment spinal cord
    sct_deepseg_gm -i ${file}.nii.gz -qc ${PATH_QC} -qc-subject ${SUBJECT}
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
  FILELABEL="${file}_labels-disc"
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

# Get session
SES=$(basename "$SUBJECT")

# Only include spinal cord sessions
if [[ $SES == *"spinalcord"* ]];then
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
        
        # Spinal cord segmentation
        # Note: For T2w images, we use sct_deepseg_sc with 2 kernel. Generally, it works better than sct_propseg and sct_deepseg_sc with 3d kernel.
        segment_if_does_not_exist ${file_t2w} 't2' 'deepseg'
        file_t2_seg="${file_t2w}_seg"

        # Vertebral labeling 
        label_if_does_not_exist ${file_t2w} ${file_t2w}_seg
        file_t2_labels="${file_t2w}_seg_labeled"
        file_t2_labels_discs="${file_t2w}_seg_labeled_discs"

        # Extract dics 3 to 8 for registration to template (C2-C3 to C7-T1)
        sct_label_utils -i ${file_t2_labels_discs}.nii.gz -keep 3,4,5,6,7,8 -o ${file_t2_labels_discs}_3to8.nii.gz
        file_t2_labels_discs="${file_t2w}_seg_labeled_discs_3to8"

        # Register T2w image to PAM50 template using all discs (C2-C3 to C7-T1)
        sct_register_to_template -i ${file_t2w}.nii.gz -s ${file_t2_seg}.nii.gz -ldisc ${file_t2_labels_discs}.nii.gz -c t2 -qc ${PATH_QC} -qc-subject ${SUBJECT}
        
        # TODO:
        # Add CSA computation where?
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
        segment_gm_if_does_not_exist ${file_t2star}
        #sct_deepseg_gm -i ${file_t2star}.nii.gz -qc ${PATH_QC} -qc-subject ${SUBJECT}
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
        segment_if_does_not_exist ${file_mton} 't2' 'deepseg'
        file_mton_seg="${file_mton}_seg"

        # Create a mask arround the spinal cord to help co-register all MTS contrasts
        sct_create_mask -i ${file_mton}.nii.gz -p centerline,${file_mton_seg}.nii.gz -size 35mm -f cylinder -o ${file_mton}_mask.nii.gz
        file_mton_mask="${file_mton}_mask"
        # Co-register all 3 MTS contrasts
        sct_register_multimodal -i ${file_mtoff}.nii.gz -d ${file_mton}.nii.gz -dseg ${file_mton_seg}.nii.gz -param step=1,type=im,algo=slicereg,metric=CC -m ${file_mton_mask}.nii.gz -x spline -qc ${PATH_QC} -qc-subject ${SUBJECT}
        sct_register_multimodal -i ${file_MTS_t1w}.nii.gz -d ${file_mton}.nii.gz -dseg ${file_mton_seg}.nii.gz -param step=1,type=im,algo=slicereg,metric=CC -m ${file_mton_mask}.nii.gz -x spline -qc ${PATH_QC} -qc-subject ${SUBJECT}

        # Compute mtr. sct_compute_mtr was not working correctly so used fslmaths
        fslmaths ${file_mtoff}_reg -sub ${file_mton} -div ${file_mtoff}_reg -mul 100 mtr
        # TODO test sct_compute_mtr
       # sct_compute_mtr -mt0 ${file_mtoff}_reg.nii.gz -mt1 ${file_mton}.nii.gz

        # Compute MTsat
        # Copy json files with _reg suffix
        cp ${file_mtoff}.json ${file_mtoff}_reg.json
        cp ${file_MTS_t1w}.json ${file_MTS_t1w}_reg.json
        sct_compute_mtsat -mt ${file_mton}.nii.gz -pd ${file_mtoff}_reg.nii.gz -t1 ${file_MTS_t1w}_reg.nii.gz
        
        # Resgister PAM50 t2star template to MTon
        sct_register_multimodal -i ${SCT_DIR}/data/PAM50/template/PAM50_t2s.nii.gz -iseg ${SCT_DIR}/data/PAM50/template/PAM50_wm.nii.gz -d ${file_mton}.nii.gz -dseg ${file_mton_seg}.nii.gz -param step=1,type=seg,algo=rigid:step=2,type=seg,algo=bsplinesyn,slicewise=1,iter=3 -initwarp ../T2star/warp_PAM50_t2s2${file_t2star}.nii.gz -initwarpinv ../T2star/warp_${file_t2star}2PAM50_t2s.nii.gz -qc ${PATH_QC} -qc-subject ${SUBJECT}

        # Warp template to MTon space
        sct_warp_template -d ${file_mton}.nii.gz -w warp_PAM50_t2s2${file_mton}.nii.gz -qc ${PATH_QC} -qc-subject ${SUBJECT}
        
        # Warp to template for potential group analysis
        # TODO check to add same croping as done for func
        # Warp MTR to PAM50 template
        sct_apply_transfo -i mtr.nii.gz -d ${SCT_DIR}/data/PAM50/template/PAM50_t2.nii.gz -w warp_${file_mton}2PAM50_t2s.nii.gz -o mtr2template.nii.gz -x linear

        # Warp MTsat to PAM50 template
        sct_apply_transfo -i mtsat.nii.gz -d ${SCT_DIR}/data/PAM50/template/PAM50_t2.nii.gz -w warp_${file_mton}2PAM50_t2s.nii.gz -o mtsat2template.nii.gz -x linear

        # Warp MTsat to PAM50 template
        sct_apply_transfo -i t1map.nii.gz -d ${SCT_DIR}/data/PAM50/template/PAM50_t2.nii.gz -w warp_${file_mton}2PAM50_t2s.nii.gz -o t1map2template.nii.gz -x linear


        # TODO
        # Do we want to extract metrics at certain levels? regions of interest?
        cd ..
    else
    echo "WARNING: MTS dataset is incomplete."
    fi



    # -------------------------------------------------------------------------
    # DWI
    # -------------------------------------------------------------------------
    cd ../dwi
    # Add suffix corresponding to contrast
    file_dwi="${file}_dwi"
    file_bval=${file_dwi}.bval
    file_bvec=${file_dwi}.bvec


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

        # Create mask around the spinal cord (for faster computing)
        sct_maths -i ${file_dwi_seg}.nii.gz -dilate 1 -shape ball -o ${file_dwi_seg}_dil.nii.gz

        # Compute DTI
        sct_dmri_compute_dti -i ${file_dwi}.nii.gz -bvec ${file_bvec} -bval ${file_bval} -method standard -m ${file_dwi_seg}_dil.nii.gz -evecs 1
        
        # Warp all DTI results to PAM50 space
        # TODO check to add same croping as done for func
        sct_apply_transfo -i dti_FA.nii.gz -d ${SCT_DIR}/data/PAM50/template/PAM50_t1.nii.gz -w warp_${file_dwi_mean}2PAM50_t1.nii.gz -o dti_FA2template.nii.gz -x linear
        sct_apply_transfo -i dti_MD.nii.gz -d ${SCT_DIR}/data/PAM50/template/PAM50_t1.nii.gz -w warp_${file_dwi_mean}2PAM50_t1.nii.gz -o dti_MD2template.nii.gz -x linear
        sct_apply_transfo -i dti_RD.nii.gz -d ${SCT_DIR}/data/PAM50/template/PAM50_t1.nii.gz -w warp_${file_dwi_mean}2PAM50_t1.nii.gz -o dti_RD2template.nii.gz -x linear


    else
        echo "Skipping dwi"
    fi
comment
    file_t2star=${file}_T2star  # TO REMOVE WHEN NO COMMENTS

    # -------------------------------------------------------------------------
    # FUNC
    # -------------------------------------------------------------------------
    cd ../func
    file_task_rest_bold="${file}_task-rest_bold"
    file_task_rest_physio="${file}_task-rest_physio"
    # Check if all DWI files exists
    if [[ -f ${file_task_rest_bold}.nii.gz ]];then

        # Compute mean image
        sct_maths -i ${file_task_rest_bold}.nii.gz -mean t -o ${file_task_rest_bold}_mean.nii.gz
        file_task_rest_bold_mean="${file_task_rest_bold}_mean"
        
        # Segment the spinal cord
        segment_if_does_not_exist ${file_task_rest_bold_mean} 't2s' 'propseg'
        # Create a spinal canal mask
        sct_maths -i ${file_task_rest_bold_mean}_seg.nii.gz -add ${file_task_rest_bold_mean}_CSF_seg.nii.gz -o ${file_task_rest_bold_mean}_SC_canal_seg.nii.gz
        # Dilate the spinal canal mask
        # check dilating
        sct_maths -i ${file_task_rest_bold_mean}_SC_canal_seg.nii.gz -dilate 5 -shape disk -o ${file_task_rest_bold_mean}_mask.nii.gz -dim 2
        # Qc of Spinal canal segmentation
        sct_qc -i ${file_task_rest_bold_mean}.nii.gz -p sct_deepseg_sc -qc ${PATH_QC} -s ${file_task_rest_bold_mean}_SC_canal_seg.nii.gz
        # Qc of mask
        sct_qc -i ${file_task_rest_bold_mean}.nii.gz -p sct_deepseg_sc -qc ${PATH_QC} -s ${file_task_rest_bold_mean}_mask.nii.gz

        # Convert GE physio data to FSL format
        python3 $PATH_SCRIPTS/utils/create_FSL_physio_text_file.py -i ${file_task_rest_physio}.tsv -TR 3.0 -number-of-volumes 245

        # Run FSL physio
        # TODO talk to merve for this
        #pnm_stage1 -i ${file_task_rest_physio}.txt -o ./physio -s 100 --tr=3.0 --smoothcard=0.1 --smoothresp=0.1 --resp=2 --cardiac=4 --trigger=3 -v
        # check with merve
    #	popp -i ${file_task_rest_physio}.txt -o ./physio -s 100 --tr=3.0 --smoothcard=0.1 --smoothresp=0.1 --resp=2 --cardiac=4 --trigger=3 -v
        
        popp -i ${file_task_rest_physio}.txt -o ./physio -s 100 --tr=3.0 --smoothcard=0.1 --cardiac=3 --trigger=2 -v
    	pnm_evs -i ${file_task_rest_bold}.nii.gz -c physio_card.txt -o physio_ --tr=3.0 --oc=4 --multc=2 --multr=2 --sliceorder=interleaved_up --slicedir=z
        
        mkdir -p PNM
    	mv physio* ./PNM/
    	mv ${file_task_rest_physio}.txt ./PNM/


        # --------------------
        # 2D Motion correction
        # --------------------

        # Step 1 of 2D motion correction using mid volume
        # Select mid volume
        fslroi ${file_task_rest_bold} ${file_task_rest_bold}_mc1_ref 125 1
        # Apply motion correction
        ${PATH_SCRIPTS}/motion_correction/2D_slicewise_motion_correction.sh -i ${file_task_rest_bold}.nii.gz -r ${file_task_rest_bold}_mc1_ref.nii.gz -m ${file_task_rest_bold_mean}_mask.nii.gz -o mc1
        

        # Step 2 of 2D motion correction using mean of mc1 as ref
        # Segment the spinal cord
        segment_if_does_not_exist mc1_mean 't2s' 'propseg'
        # Create a spinal canal mask
        sct_maths -i mc1_mean_seg.nii.gz -add mc1_mean_CSF_seg.nii.gz -o mc1_mean_SC_canal_seg.nii.gz
        # Dilate the spinal canal mask
        # check dilating
        sct_maths -i mc1_mean_SC_canal_seg.nii.gz -dilate 5 -shape disk -o mc1_mask.nii.gz -dim 2
        # Qc of Spinal canal segmentation
        sct_qc -i mc1_mean.nii.gz -p sct_deepseg_sc -qc ${PATH_QC} -s mc1_mean_SC_canal_seg.nii.gz
        # Qc of mask
        sct_qc -i  mc1_mean.nii.gz -p sct_deepseg_sc -qc ${PATH_QC} -s mc1_mask.nii.gz

        # Apply motion correction step 2
        ${PATH_SCRIPTS}/motion_correction/2D_slicewise_motion_correction.sh -i mc1.nii.gz -r mc1_mean.nii.gz -m mc1_mask.nii.gz -o mc2

        mv mc2.nii.gz ${file_task_rest_bold}_mc2.nii.gz
        mv mc2_mean.nii.gz ${file_task_rest_bold}_mc2_mean.nii.gz
        mv mc2_tsnr.nii.gz ${file_task_rest_bold}_mc2_tsnr.nii.gz
        mv mc2_mat.tar.gz ${file_task_rest_bold}_mc2_mat.tar.gz

        # Create spinal cord mask and spinal canal mask
        file_task_rest_bold_mc2=${file_task_rest_bold}_mc2
        file_task_rest_bold_mc2_mean=${file_task_rest_bold}_mc2_mean

        segment_if_does_not_exist ${file_task_rest_bold_mc2_mean} 't2s' 'propseg'
        sct_maths -i ${file_task_rest_bold_mc2_mean}_seg.nii.gz -add ${file_task_rest_bold_mc2_mean}_CSF_seg.nii.gz -o ${file_task_rest_bold_mc2_mean}_SC_canal_seg.nii.gz

        sct_qc -i ${file_task_rest_bold_mc2}.nii.gz -p sct_fmri_moco -qc ${PATH_QC} -s ${file_task_rest_bold_mc2_mean}_seg.nii.gz -d  ${file_task_rest_bold}.nii.gz

        # Create segmentation using sct_deepseg_sc
        segment_if_does_not_exist ${file_task_rest_bold_mc2_mean} 't2s' 'deepseg'
        file_task_rest_bold_mc2_mean_seg="${file_task_rest_bold_mc2_mean}_seg"
        
        # Register to template
        sct_register_multimodal -i ${SCT_DIR}/data/PAM50/template/PAM50_t2s.nii.gz -iseg ${SCT_DIR}/data/PAM50/template/PAM50_cord.nii.gz -d ${file_task_rest_bold_mc2_mean}.nii.gz -dseg ${file_task_rest_bold_mc2_mean_seg}.nii.gz -param step=1,type=seg,algo=centermass:step=2,type=seg,algo=bsplinesyn,slicewise=1,iter=3 -initwarp ../anat/T2star/warp_PAM50_t2s2${file_t2star}.nii.gz -initwarpinv ../anat/T2star/warp_${file_t2star}2PAM50_t2s.nii.gz
        
        sct_warp_template -d ${file_task_rest_bold_mc2_mean}.nii.gz -w warp_PAM50_t2s2${file_task_rest_bold_mc2_mean}.nii.gz
<<comment
        # Create CSF regressor
	    data=${file_task_rest_bold_mc2}
        fslmaths ${data}_mean_seg -binv temp_mask
        fslmaths ${data}_mean_SC_canal_seg -mul temp_mask ${data}_csf_mask
        rm temp_mask.nii.gz
        fslsplit ${data}_csf_mask ${data}_csf_mask_slice -z
        xdim=`fslval ${data} dim1`
        ydim=`fslval ${data} dim2`
        zdim=`fslval ${data} dim3`
        tdim=`fslval ${data} dim4`
        pixdimx=`fslval ${data} pixdim1`
        pixdimy=`fslval ${data} pixdim2`
        pixdimz=`fslval ${data} pixdim3`
        tr=`fslval ${data} pixdim4`
        fslsplit ${data} ${data}_slice -z
        for ((k=0; k<$zdim; k++)) ; do
            slice_number=$((10000+$k))
            fslstats -t ${data}_slice${slice_number:1:4} -k ${data}_csf_mask_slice${slice_number:1:4} -m >> ${data}_slice${slice_number:1:4}_mean_csf.txt
            fslascii2img ${data}_slice${slice_number:1:4}_mean_csf.txt 1 1 1 $tdim 1 1 1 $tr ${data}_slice${slice_number:1:4}_mean_csf
            fslmaths ${data}_slice${slice_number:1:4}_mean_csf -Tmean mean
            fslmaths ${data}_slice${slice_number:1:4}_mean_csf -sub mean ${data}_slice${slice_number:1:4}_mean_csf
            rm mean.nii.gz
            rm ${data}_slice${slice_number:1:4}_mean_csf.txt
        done
        v="${data}_slice0???_mean_csf.nii.gz"
        fslmerge -z ${data}_csf_regressor $v
        rm $v
        v="${data}_slice0???.nii.gz"
        rm $v
        v="${data}_csf_mask_slice0???.nii.gz"
        rm $v

        mv ${data}_csf_regressor.nii.gz ./PNM

        # Create WM regressor
        data=${file_task_rest_bold_mc2}
        fslmaths ./label/template/PAM50_wm.nii.gz -thr 0.9 -bin ${data}_wm_mask
        fslsplit ${data}_wm_mask ${data}_wm_mask_slice -z
        xdim=`fslval ${data} dim1`
        ydim=`fslval ${data} dim2`
        zdim=`fslval ${data} dim3`
        tdim=`fslval ${data} dim4`
        pixdimx=`fslval ${data} pixdim1`
        pixdimy=`fslval ${data} pixdim2`
        pixdimz=`fslval ${data} pixdim3`
        tr=`fslval ${data} pixdim4`
        fslsplit ${data} ${data}_slice -z
        for ((k=0; k<$zdim; k++)) ; do
            slice_number=$((10000+$k))
            fslstats -t ${data}_slice${slice_number:1:4} -k ${data}_wm_mask_slice${slice_number:1:4} -m >> ${data}_slice${slice_number:1:4}_mean_wm.txt
            fslascii2img ${data}_slice${slice_number:1:4}_mean_wm.txt 1 1 1 $tdim 1 1 1 $tr ${data}_slice${slice_number:1:4}_mean_wm
            fslmaths ${data}_slice${slice_number:1:4}_mean_wm -Tmean mean
            fslmaths ${data}_slice${slice_number:1:4}_mean_wm -sub mean ${data}_slice${slice_number:1:4}_mean_wm
            rm mean.nii.gz
            rm ${data}_slice${slice_number:1:4}_mean_wm.txt
        done
        v="${data}_slice0???_mean_wm.nii.gz"
        fslmerge -z ${data}_wm_regressor $v
        rm $v
        v="${data}_slice0???.nii.gz"
        rm $v
        v="${data}_wm_mask_slice0???.nii.gz"
        rm $v

        mv ${data}_wm_regressor.nii.gz ./PNM


        #Correct PNM regressors for motion
#        cd ./PNM
#        cp  ../${file_task_rest_bold_mc2}_mat.tar.gz mc2_mat.tar.gz
#        # 
#        ${PATH_SCRIPTS}/motion_correction/pnm_ev_3D_correction_for_motion.sh -i ../${file_task_rest_bold_mc2}.nii.gz -p physio_ev -n 32 -f mc2_mat.tar.gz -o 3D
#        rm mc2_mat.tar.gz
       # cd ..
        
        # TODO: check to create slicewise motion regressors ()

        cp ${PATH_SCRIPTS}/utils/denoise.fsf ./
        export analysis_path subject session
        envsubst < "denoise.fsf" > "denoise_${file}.fsf"
        feat denoise_${file}.fsf

        # Create denoised image
        fslmaths ./${file_task_rest_bold_mc2}_pnm.feat/stats/res4d.nii.gz -add ./${file_task_rest_bold_mc2}_pnm.feat/mean_func.nii.gz ${file_task_rest_bold_mc2}_pnm
        tr=`fslval ${file_task_rest_bold_mc2} pixdim4` # Get TR of volumes
        fslsplit ${file_task_rest_bold_mc2}_pnm vol -t
        v=vol????.nii.gz
        fslmerge -tr ${file_task_rest_bold_mc2}_pnm ${v} ${tr}
        rm $v

        # Find motion outliers
        fsl_motion_outliers -i ${file_task_rest_bold_mc2} -m ${file_task_rest_bold_mc2_mean_seg} --dvars --nomoco -o ${file_task_rest_bold_mc2}_dvars_motion_outliers.txt

        # Run slicetiming correction
        tr=`fslval ${file_task_rest_bold_mc2}_pnm pixdim4` #Get TR of volumes
        slicetimer -i ${file_task_rest_bold_mc2}_pnm -o ${file_task_rest_bold_mc2}_pnm_stc -r ${tr} --odd

        # Warp each volume to the template
        fslsplit ${file_task_rest_bold_mc2}_pnm_stc vol -t
        tr=`fslval ${file_task_rest_bold_mc2}_pnm_stc pixdim4` # Get TR of volumes
        tdimi=`fslval ${file_task_rest_bold_mc2}_pnm_stc dim4` # Get the number of volumes
        last_volume=$(echo "scale=0; $tdimi-1" | bc) # Find index of last volume
        for ((k=0; k<=$last_volume; k++));do
            vol="$(printf "vol%04d" ${k})"
            sct_apply_transfo -i ${vol}.nii.gz -d ${SCT_DIR}/data/PAM50/template/PAM50_t2.nii.gz -w warp_${file_task_rest_bold_mc2_mean}2PAM50_t2s.nii.gz -o ${vol}2template.nii.gz -x spline
            fslmaths ${vol}2template.nii.gz -mul ${SCT_DIR}/data/PAM50/template/PAM50_cord.nii.gz ${vol}2template.nii.gz
            fslroi ${vol}2template.nii.gz ${vol}2template.nii.gz 32 75 34 75 691 263
        done
        v="vol????2template.nii.gz"
        fslmerge -tr ${file_task_rest_bold_mc2}_pnm_stc2template $v $tr # Merge warped volumes together
        rm $v
        v=vol????.nii.gz
        rm $v

        #Remove outside voxels based on spinal cord mask z limits
        sct_apply_transfo -i ${file_task_rest_bold_mc2_mean_seg}.nii.gz -d ${SCT_DIR}/data/PAM50/template/PAM50_t2.nii.gz -w warp_${file_task_rest_bold_mc2_mean}2PAM50_t2s.nii.gz -o ${file_task_rest_bold_mc2_mean_seg}2template.nii.gz -x nn
        fslroi ${file_task_rest_bold_mc2_mean_seg}2template.nii.gz ${file_task_rest_bold_mc2_mean_seg}2template.nii.gz 32 75 34 75 691 263
        fslmaths ${file_task_rest_bold_mc2_mean_seg}2template.nii.gz -kernel 2 -dilD -dilD -dilD -dilD -dilD temp_mask
        fslmaths ${file_task_rest_bold_mc2}_pnm_stc2template -mul temp_mask ${file_task_rest_bold_mc2}_pnm_stc2template
        rm temp_mask.nii.gz
        
        # TODO: here or later
        # Bandpass temporal filtering (see fslmath)
        # nilearn check bandpass filter could be done here
        # spatial smoothing --> if in template space
comment
    else
        echo "Skipping func"
    fi
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

