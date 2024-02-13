#!/bin/bash
#
# Analayses spinal cord data for the K23 Cervical Radiculopathy project
#
# Usage:
#     sct_run_batch -c <PATH_TO_REPO>/etc/config_process_data.json  # TODO
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
# Authors: Sandrine Bédard and Kenneth Weber
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
  local subfolder="$4"
  # Update global variable with segmentation file name
  FILESEG="${file}_seg"
  FILESEGMANUAL="${PATH_DERIVATIVES}/${SUBJECT}/${subfolder}/${FILESEG}.nii.gz"
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
#<<comment
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
        segment_if_does_not_exist ${file_t2w} 't2' 'deepseg' 'anat'
        file_t2_seg="${file_t2w}_seg"

        # Vertebral labeling 
        label_if_does_not_exist ${file_t2w} ${file_t2w}_seg
        file_t2_labels="${file_t2w}_seg_labeled"
        file_t2_labels_discs="${file_t2w}_seg_labeled_discs"

        # Extract dics 3 to 8 for registration to template (C1 to T1-T2)
        sct_label_utils -i ${file_t2_labels_discs}.nii.gz -keep 1,2,3,4,5,6,7,8,9 -o ${file_t2_labels_discs}_1to9.nii.gz
        file_t2_labels_discs="${file_t2w}_seg_labeled_discs_1to9"

        # Compute CSA perlevel
        sct_process_segmentation -i ${file_t2_seg}.nii.gz -vertfile ${file_t2_labels}.nii.gz -vert 2:8 -perlevel 1 -o ${PATH_RESULTS}/t2w_shape_perlevel.csv -append 1
        # Compute CSA in PAM50 anatomical space perslice
        sct_process_segmentation -i ${file_t2_seg}.nii.gz -vertfile ${file_t2_labels}.nii.gz -perslice 1 -normalize-PAM50 1 -v 2 -o ${PATH_RESULTS}/t2w_shape_PAM50.csv -append 1
        
        # Register T2w image to PAM50 template using all discs (C2-C3 to C7-T1)
        sct_register_to_template -i ${file_t2w}.nii.gz -s ${file_t2_seg}.nii.gz -ldisc ${file_t2_labels_discs}.nii.gz -c t2 -qc ${PATH_QC} -qc-subject ${SUBJECT}
        
        # Warp template to T2w image (to get right left hemicord)
        sct_warp_template -d ${file_t2w}.nii.gz -w warp_template2anat.nii.gz
        
        # Create left hemicord
        sct_maths -i label/atlas/PAM50_atlas_00.nii.gz -add label/atlas/PAM50_atlas_02.nii.gz label/atlas/PAM50_atlas_04.nii.gz label/atlas/PAM50_atlas_06.nii.gz label/atlas/PAM50_atlas_08.nii.gz label/atlas/PAM50_atlas_10.nii.gz label/atlas/PAM50_atlas_12.nii.gz label/atlas/PAM50_atlas_14.nii.gz label/atlas/PAM50_atlas_16.nii.gz label/atlas/PAM50_atlas_18.nii.gz label/atlas/PAM50_atlas_20.nii.gz label/atlas/PAM50_atlas_22.nii.gz label/atlas/PAM50_atlas_24.nii.gz label/atlas/PAM50_atlas_26.nii.gz label/atlas/PAM50_atlas_28.nii.gz label/atlas/PAM50_atlas_30.nii.gz label/atlas/PAM50_atlas_32.nii.gz label/atlas/PAM50_atlas_34.nii.gz -o PAM50_atlas_left_hemi_cord.nii.gz
        # Create right hemicord
        sct_maths -i label/atlas/PAM50_atlas_01.nii.gz -add label/atlas/PAM50_atlas_03.nii.gz label/atlas/PAM50_atlas_05.nii.gz label/atlas/PAM50_atlas_07.nii.gz label/atlas/PAM50_atlas_09.nii.gz label/atlas/PAM50_atlas_11.nii.gz label/atlas/PAM50_atlas_13.nii.gz label/atlas/PAM50_atlas_15.nii.gz label/atlas/PAM50_atlas_17.nii.gz label/atlas/PAM50_atlas_19.nii.gz label/atlas/PAM50_atlas_21.nii.gz label/atlas/PAM50_atlas_23.nii.gz label/atlas/PAM50_atlas_25.nii.gz label/atlas/PAM50_atlas_27.nii.gz label/atlas/PAM50_atlas_29.nii.gz label/atlas/PAM50_atlas_31.nii.gz label/atlas/PAM50_atlas_33.nii.gz label/atlas/PAM50_atlas_35.nii.gz -o PAM50_atlas_right_hemi_cord.nii.gz
        # Binarize both masks
        sct_maths -i PAM50_atlas_right_hemi_cord.nii.gz -bin 0.5 -o PAM50_atlas_right_hemi_cord_bin.nii.gz
        sct_maths -i PAM50_atlas_left_hemi_cord.nii.gz -bin 0.5 -o PAM50_atlas_left_hemi_cord_bin.nii.gz
        
        # Create right and left hemicord masks of T2w
        python3 $PATH_SCRIPTS/create_right_left_seg_mask.py -seg ${file_t2_seg}.nii.gz -PAM50-R PAM50_atlas_right_hemi_cord_bin.nii.gz -PAM50-L PAM50_atlas_left_hemi_cord_bin.nii.gz
        
        # QC report 
        sct_qc -i ${file_t2w}.nii.gz -p sct_deepseg_sc -qc ${PATH_QC} -s ${file_t2_seg}_right.nii.gz -qc-subject ${SUBJECT}
        sct_qc -i ${file_t2w}.nii.gz -p sct_deepseg_sc -qc ${PATH_QC} -s ${file_t2_seg}_left.nii.gz -qc-subject ${SUBJECT}

        # Compute Right CSA
        # Compute CSA perlevel
        sct_process_segmentation -i ${file_t2_seg}_right.nii.gz -vertfile ${file_t2_labels}.nii.gz -vert 2:8 -perlevel 1 -o ${PATH_RESULTS}/t2w_shape_right_perlevel.csv -append 1
        # Compute CSA in PAM50 anatomical space perslice
        sct_process_segmentation -i ${file_t2_seg}_right.nii.gz -vertfile ${file_t2_labels}.nii.gz -perslice 1 -normalize-PAM50 1 -v 2 -o ${PATH_RESULTS}/t2w_shape_right_PAM50.csv -append 1
        # Compute Left CSA
        # Compute CSA perlevel
        sct_process_segmentation -i ${file_t2_seg}_left.nii.gz -vertfile ${file_t2_labels}.nii.gz -vert 2:8 -perlevel 1 -o ${PATH_RESULTS}/t2w_shape_left_perlevel.csv -append 1
        # Compute CSA in PAM50 anatomical space perslice
        sct_process_segmentation -i ${file_t2_seg}_left.nii.gz -vertfile ${file_t2_labels}.nii.gz -perslice 1 -normalize-PAM50 1 -v 2 -o ${PATH_RESULTS}/t2w_shape_left_PAM50.csv -append 1
        

        # Compute Right Left symmetry with dice score:
        mkdir -p ${PATH_DATA_PROCESSED}/${SUBJECT}/anat/T2w/dice_RL
        cp ${file_t2w}.nii.gz ${PATH_DATA_PROCESSED}/${SUBJECT}/anat/T2w/dice_RL
        cp ${file_t2_seg}.nii.gz ${PATH_DATA_PROCESSED}/${SUBJECT}/anat/T2w/dice_RL
        cp ${file_t2_labels_discs}.nii.gz ${PATH_DATA_PROCESSED}/${SUBJECT}/anat/T2w/dice_RL
        cd dice_RL
        sct_register_to_template -i ${file_t2w}.nii.gz -s ${file_t2_seg}.nii.gz -ldisc ${file_t2_labels_discs}.nii.gz -param step=1,type=imseg,algo=centermassrot,metric=MeanSquares,iter=10,smooth=0,gradStep=0.5,slicewise=0,smoothWarpXY=2,pca_eigenratio_th=1.6 -qc ${PATH_QC} -qc-subject ${SUBJECT}
        sct_apply_transfo -i ${file_t2_seg}.nii.gz -d anat2template.nii.gz -w warp_anat2template.nii.gz -o ${file_t2_seg}_reg.nii.gz -x nn
        python $PATH_SCRIPTS/compute_dice_rl.py -seg ${file_t2_seg}_reg.nii.gz -vertfile $SCT_DIR/data/PAM50/template/PAM50_levels.nii.gz -levels 3 4 5 6 -fname-out ${PATH_RESULTS}/dice_RL.csv -subject ${SUBJECT} -session ${SES}
        cd ..
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
        segment_if_does_not_exist ${file_t2star} 't2s' 'deepseg' 'anat'
        file_t2star_seg="${file_t2star}_seg"

        # Spinal cord GM segmentation
        segment_gm_if_does_not_exist ${file_t2star}
        #sct_deepseg_gm -i ${file_t2star}.nii.gz -qc ${PATH_QC} -qc-subject ${SUBJECT}
        file_t2star_gmseg="${file_t2star}_gmseg"
        
        # Get WM segmentation by subtracting SC cord segmentation with GM segmentation
        sct_maths -i ${file_t2star_seg}.nii.gz -sub ${file_t2star_gmseg}.nii.gz -o ${file_t2star}_wmseg.nii.gz
        file_t2star_wmseg="${file_t2star}_wmseg"

        # Register PAM50 T2s template to T2star using the WM segmentation
        sct_register_multimodal -i ${SCT_DIR}/data/PAM50/template/PAM50_t2s.nii.gz -iseg ${SCT_DIR}/data/PAM50/template/PAM50_wm.nii.gz -d ${file_t2star}.nii.gz -dseg ${file_t2star_wmseg}.nii.gz -param step=1,type=seg,algo=centermass:step=2,type=seg,algo=bsplinesyn,slicewise=1,iter=10:step=3,type=im,algo=syn,slicewise=1,iter=1,metric=CC -initwarp ../T2w/warp_template2anat.nii.gz -initwarpinv ../T2w/warp_anat2template.nii.gz -qc ${PATH_QC} -qc-subject ${SUBJECT}
        
        # Bring PAM50 template to T2star space
        sct_warp_template -d ${file_t2star}.nii.gz -w warp_PAM50_t2s2${file_t2star}.nii.gz -qc ${PATH_QC} -qc-subject ${SUBJECT}

        # Get vertebral coverage
        python $PATH_SCRIPTS/utils/get_vertebral_coverage.py -vertfile ./label/template/PAM50_levels.nii.gz -subject ${SUBJECT} -o ${PATH_RESULTS}/vert_coverage_t2star.csv
        
        # Compute GM CSA (perlevel)
        sct_process_segmentation -i ${file_t2star_gmseg}.nii.gz -vert 2:8 -angle-corr 0 -perlevel 1 -vertfile ./label/template/PAM50_levels.nii.gz -o ${PATH_RESULTS}/t2star_gm_csa.csv -append 1
        

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
        segment_if_does_not_exist ${file_mton} 't2' 'deepseg' 'anat'
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
        




        # Resgister PAM50 t2w template to MTon
        sct_register_multimodal -i ${SCT_DIR}/data/PAM50/template/PAM50_t2.nii.gz -iseg ${SCT_DIR}/data/PAM50/template/PAM50_cord.nii.gz -d ${file_mton}.nii.gz -dseg ${file_mton_seg}.nii.gz -param step=1,type=seg,algo=centermass:step=2,type=seg,algo=bsplinesyn,metric=MeanSquares,slicewise=1,iter=3:step=3,type=im,algo=syn,metric=CC,iter=1,slicewise=1 -initwarp ../T2star/warp_PAM50_t2s2${file_t2star}.nii.gz -initwarpinv ../T2star/warp_${file_t2star}2PAM50_t2s.nii.gz -qc ${PATH_QC} -qc-subject ${SUBJECT}

        # Warp template to MTon space
        sct_warp_template -d ${file_mton}.nii.gz -w warp_PAM50_t22${file_mton}.nii.gz -qc ${PATH_QC} -qc-subject ${SUBJECT}
        
        # Warp to template for potential group analysis
        # TODO check to add same croping as done for func
        # Warp MTR to PAM50 template
        sct_apply_transfo -i mtr.nii.gz -d ${SCT_DIR}/data/PAM50/template/PAM50_t2.nii.gz -w warp_${file_mton}2PAM50_t2.nii.gz -o mtr2template.nii.gz -x linear

        # Warp MTsat to PAM50 template
        sct_apply_transfo -i mtsat.nii.gz -d ${SCT_DIR}/data/PAM50/template/PAM50_t2.nii.gz -w warp_${file_mton}2PAM50_t2.nii.gz -o mtsat2template.nii.gz -x linear

        # Warp MTsat to PAM50 template
        sct_apply_transfo -i t1map.nii.gz -d ${SCT_DIR}/data/PAM50/template/PAM50_t2.nii.gz -w warp_${file_mton}2PAM50_t2.nii.gz -o t1map2template.nii.gz -x linear

        # Get vertebral coverage
        python $PATH_SCRIPTS/utils/get_vertebral_coverage.py -vertfile ./label/template/PAM50_levels.nii.gz -subject ${SUBJECT} -o ${PATH_RESULTS}/vert_coverage_mton.csv
        
        # Compute metrics in subject space:
        # Create subdir for DTI results
        mkdir -p $PATH_RESULTS/mts/
        
        # MTR
        #####################
        # Right corticospinal
        sct_extract_metric -i mtr.nii.gz -l 5,23 -combine 1 -vert 3:6  -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/mts/mtr_in_corticospinal_right.csv
        # Left corticospinal
        sct_extract_metric -i mtr.nii.gz -l 4,22 -combine 1 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/mts/mtr_in_corticospinal_left.csv
        # Corticospinal
        sct_extract_metric -i mtr.nii.gz -l 4,5,22,23 -combine 1 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/mts/mtr_in_corticospinal.csv
        
        # Right dorsal column
        sct_extract_metric -i mtr.nii.gz -l 1,3 -combine 1 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/mts/mtr_in_dorsalcolumn_right.csv
        # Left dorsal column
        sct_extract_metric -i mtr.nii.gz -l 0,2 -combine 1 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/mts/mtr_in_dorsalcolumn_left.csv
        # dorsal column
        sct_extract_metric -i mtr.nii.gz -l 53 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/mts/mtr_in_dorsalcolumn.csv

        # Right spinal lemniscus
        sct_extract_metric -i mtr.nii.gz -l 13 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/mts/mtr_in_lemniscus_right.csv
        # Left spinal lemniscus
        sct_extract_metric -i mtr.nii.gz -l 12 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/mts/mtr_in_lemniscus_left.csv
        # spinal lemniscus
        sct_extract_metric -i mtr.nii.gz -l 12,13 -combine 1 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/mts/mtr_in_lemniscus.csv

        # MTsat
        #####################
        # Right corticospinal
        sct_extract_metric -i mtsat.nii.gz -l 5,23 -combine 1 -vert 3:6  -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/mts/mtsat_in_corticospinal_right.csv
        # Left corticospinal
        sct_extract_metric -i mtsat.nii.gz -l 4,22 -combine 1 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/mts/mtsat_in_corticospinal_left.csv
        # Corticospinal
        sct_extract_metric -i mtsat.nii.gz -l 4,5,22,23 -combine 1 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/mts/mtsat_in_corticospinal.csv
        
        # Right dorsal column
        sct_extract_metric -i mtsat.nii.gz -l 1,3 -combine 1 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/mts/mtsat_in_dorsalcolumn_right.csv
        # Left dorsal column
        sct_extract_metric -i mtsat.nii.gz -l 0,2 -combine 1 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/mts/mtsat_in_dorsalcolumn_left.csv
        # dorsal column
        sct_extract_metric -i mtsat.nii.gz -l 53 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/mts/mtsat_in_dorsalcolumn.csv

        # Right spinal lemniscus
        sct_extract_metric -i mtsat.nii.gz -l 13 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/mts/mtsat_in_lemniscus_right.csv
        # Left spinal lemniscus
        sct_extract_metric -i mtsat.nii.gz -l 12 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/mts/mtsat_in_lemniscus_left.csv
        # spinal lemniscus
        sct_extract_metric -i mtsat.nii.gz -l 12,13 -combine 1 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/mts/mtsat_in_lemniscus.csv

        # T1map
        #####################
        # Right corticospinal
        sct_extract_metric -i t1map.nii.gz -l 5,23 -combine 1 -vert 3:6  -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/mts/t1map_in_corticospinal_right.csv
        # Left corticospinal
        sct_extract_metric -i t1map.nii.gz -l 4,22 -combine 1 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/mts/t1map_in_corticospinal_left.csv
        # Corticospinal
        sct_extract_metric -i t1map.nii.gz -l 4,5,22,23 -combine 1 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/mts/t1map_in_corticospinal.csv
        
        # Right dorsal column
        sct_extract_metric -i t1map.nii.gz -l 1,3 -combine 1 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/mts/t1map_in_dorsalcolumn_right.csv
        # Left dorsal column
        sct_extract_metric -i t1map.nii.gz -l 0,2 -combine 1 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/mts/t1map_in_dorsalcolumn_left.csv
        # dorsal column
        sct_extract_metric -i t1map.nii.gz -l 53 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/mts/t1map_in_dorsalcolumn.csv

        # Right spinal lemniscus
        sct_extract_metric -i t1map.nii.gz -l 13 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/mts/t1map_in_lemniscus_right.csv
        # Left spinal lemniscus
        sct_extract_metric -i t1map.nii.gz -l 12 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/mts/t1map_in_lemniscus_left.csv
        # spinal lemniscus
        sct_extract_metric -i t1map.nii.gz -l 12,13 -combine 1 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/mts/t1map_in_lemniscus.csv


        # ALL WM
        ####################
        sct_extract_metric -i mtr.nii.gz -l 51 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/mts/mtr_in_wm.csv
        sct_extract_metric -i mtsat.nii.gz -l 51 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/mts/mtsat_in_wm.csv
        sct_extract_metric -i t1map.nii.gz -l 51 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/mts/t1map_in_wm.csv

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
        segment_if_does_not_exist ${file_dwi}_dwi_mean 'dwi' 'deepseg' 'dwi'

        # Create mask arround the spinal cord
        sct_create_mask -i ${file_dwi}_dwi_mean.nii.gz -p centerline,${file_dwi}_dwi_mean_seg.nii.gz -size 35mm -o ${file_dwi}_dwi_mean_mask.nii.gz

        # Motion correction
        sct_dmri_moco -i ${file_dwi}.nii.gz -bvec ${file_bvec} -m ${file_dwi}_dwi_mean_mask.nii.gz -x spline -qc ${PATH_QC} -qc-subject ${SUBJECT} -qc-seg ${file_dwi}_dwi_mean_seg.nii.gz
        file_dwi=${file_dwi}_moco
        file_dwi_mean=${file_dwi}_dwi_mean

        # Segment spinal cord (only if it does not exist)
        segment_if_does_not_exist ${file_dwi_mean} 'dwi' 'deepseg' 'dwi'
        file_dwi_seg=${file_dwi_mean}_seg

        # Register PAM50 T1w to dwi
        sct_register_multimodal -i ${SCT_DIR}/data/PAM50/template/PAM50_t1.nii.gz -iseg ${SCT_DIR}/data/PAM50/template/PAM50_cord.nii.gz -d ${file_dwi_mean}.nii.gz -dseg ${file_dwi_seg}.nii.gz -param step=1,type=seg,algo=centermass:step=2,type=seg,algo=bsplinesyn,metric=MeanSquares,slicewise=1,iter=3:step=3,type=im,algo=syn,metric=CC,iter=3,slicewise=1 -initwarp ../anat/T2star/warp_PAM50_t2s2${file_t2star}.nii.gz -initwarpinv ../anat/T2star/warp_${file_t2star}2PAM50_t2s.nii.gz -qc ${PATH_QC} -qc-subject ${SUBJECT}
        sct_warp_template -d ${file_dwi_mean}.nii.gz -w warp_PAM50_t12${file_dwi_mean}.nii.gz -qc ${PATH_QC} -qc-subject ${SUBJECT}

        # Get vertebral coverage
        python $PATH_SCRIPTS/utils/get_vertebral_coverage.py -vertfile ./label/template/PAM50_levels.nii.gz -subject ${SUBJECT} -o ${PATH_RESULTS}/vert_coverage_dwi.csv

        # Create mask around the spinal cord (for faster computing)
        sct_maths -i ${file_dwi_seg}.nii.gz -dilate 1 -shape ball -o ${file_dwi_seg}_dil.nii.gz

        # Compute DTI
        sct_dmri_compute_dti -i ${file_dwi}.nii.gz -bvec ${file_bvec} -bval ${file_bval} -method standard -m ${file_dwi_seg}_dil.nii.gz -evecs 1
        
        # Compute metrics in subject space:
        # Create subdir for DTI results
        mkdir -p $PATH_RESULTS/dwi/
        # FA
        #####################
        # Right corticospinal
        sct_extract_metric -i dti_FA.nii.gz -l 5,23 -combine 1 -vert 3:6  -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/dwi/fa_in_corticospinal_right.csv
        # Left corticospinal
        sct_extract_metric -i dti_FA.nii.gz -l 4,22 -combine 1 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/dwi/fa_in_corticospinal_left.csv
        # Corticospinal
        sct_extract_metric -i dti_FA.nii.gz -l 4,5,22,23 -combine 1 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/dwi/fa_in_corticospinal.csv
        
        # Right dorsal column
        sct_extract_metric -i dti_FA.nii.gz -l 1,3 -combine 1 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/dwi/fa_in_dorsalcolumn_right.csv
        # Left dorsal column
        sct_extract_metric -i dti_FA.nii.gz -l 0,2 -combine 1 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/dwi/fa_in_dorsalcolumn_left.csv
        # dorsal column
        sct_extract_metric -i dti_FA.nii.gz -l 53 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/dwi/fa_in_dorsalcolumn.csv

        # Right spinal lemniscus
        sct_extract_metric -i dti_FA.nii.gz -l 13 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/dwi/fa_in_lemniscus_right.csv
        # Left spinal lemniscus
        sct_extract_metric -i dti_FA.nii.gz -l 12 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/dwi/fa_in_lemniscus_left.csv
        # spinal lemniscus
        sct_extract_metric -i dti_FA.nii.gz -l 12,13 -combine 1 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/dwi/fa_in_lemniscus.csv

        # MD
        #####################
        # Right corticospinal
        sct_extract_metric -i dti_MD.nii.gz -l 5,23 -combine 1 -vert 3:6  -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/dwi/md_in_corticospinal_right.csv
        # Left corticospinal
        sct_extract_metric -i dti_MD.nii.gz -l 4,22 -combine 1 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/dwi/md_in_corticospinal_left.csv
        # Corticospinal
        sct_extract_metric -i dti_MD.nii.gz -l 4,5,22,23 -combine 1 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/dwi/md_in_corticospinal.csv
        
        # Right dorsal column
        sct_extract_metric -i dti_MD.nii.gz -l 1,3 -combine 1 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/dwi/md_in_dorsalcolumn_right.csv
        # Left dorsal column
        sct_extract_metric -i dti_MD.nii.gz -l 0,2 -combine 1 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/dwi/md_in_dorsalcolumn_left.csv
        # dorsal column
        sct_extract_metric -i dti_MD.nii.gz -l 53 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/dwi/md_in_dorsalcolumn.csv

        # Right spinal lemniscus
        sct_extract_metric -i dti_MD.nii.gz -l 13 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/dwi/md_in_lemniscus_right.csv
        # Left spinal lemniscus
        sct_extract_metric -i dti_MD.nii.gz -l 12 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/dwi/md_in_lemniscus_left.csv
        # spinal lemniscus
        sct_extract_metric -i dti_MD.nii.gz -l 12,13 -combine 1 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/dwi/md_in_lemniscus.csv

        # RD
        #####################
        # Right corticospinal
        sct_extract_metric -i dti_RD.nii.gz -l 5,23 -combine 1 -vert 3:6  -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/dwi/rd_in_corticospinal_right.csv
        # Left corticospinal
        sct_extract_metric -i dti_RD.nii.gz -l 4,22 -combine 1 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/dwi/rd_in_corticospinal_left.csv
        # Corticospinal
        sct_extract_metric -i dti_RD.nii.gz -l 4,5,22,23 -combine 1 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/dwi/rd_in_corticospinal.csv
        
        # Right dorsal column
        sct_extract_metric -i dti_RD.nii.gz -l 1,3 -combine 1 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz  -append 1 -o $PATH_RESULTS/dwi/rd_in_dorsalcolumn_right.csv
        # Left dorsal column
        sct_extract_metric -i dti_RD.nii.gz -l 0,2 -combine 1 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/dwi/rd_in_dorsalcolumn_left.csv
        # dorsal column
        sct_extract_metric -i dti_RD.nii.gz -l 53 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/dwi/rd_in_dorsalcolumn.csv

        # Right spinal lemniscus
        sct_extract_metric -i dti_RD.nii.gz -l 13 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/dwi/rd_in_lemniscus_right.csv
        # Left spinal lemniscus
        sct_extract_metric -i dti_RD.nii.gz -l 12 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/dwi/rd_in_lemniscus_left.csv
        # spinal lemniscus
        sct_extract_metric -i dti_RD.nii.gz -l 12,13 -combine 1 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/dwi/rd_in_lemniscus.csv

        # ALL WM
        ####################
        # TODO: add right left
        sct_extract_metric -i dti_FA.nii.gz -l 51 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/dwi/fa_in_wm.csv
        sct_extract_metric -i dti_MD.nii.gz -l 51 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/dwi/md_in_wm.csv
        sct_extract_metric -i dti_RD.nii.gz -l 51 -vert 3:6 -method map -f label/atlas -vertfile label/template/PAM50_levels.nii.gz -append 1 -o $PATH_RESULTS/dwi/rd_in_wm.csv
        
        # Warp all DTI results to PAM50 space
        # TODO check to add same croping as done for func
        sct_apply_transfo -i dti_FA.nii.gz -d ${SCT_DIR}/data/PAM50/template/PAM50_t1.nii.gz -w warp_${file_dwi_mean}2PAM50_t1.nii.gz -o dti_FA2template.nii.gz -x linear
        sct_apply_transfo -i dti_MD.nii.gz -d ${SCT_DIR}/data/PAM50/template/PAM50_t1.nii.gz -w warp_${file_dwi_mean}2PAM50_t1.nii.gz -o dti_MD2template.nii.gz -x linear
        sct_apply_transfo -i dti_RD.nii.gz -d ${SCT_DIR}/data/PAM50/template/PAM50_t1.nii.gz -w warp_${file_dwi_mean}2PAM50_t1.nii.gz -o dti_RD2template.nii.gz -x linear


    else
        echo "Skipping dwi"
    fi
#comment
    file_t2star=${file}_T2star  # TO REMOVE WHEN NO COMMENTS

    # -------------------------------------------------------------------------
    # FUNC
    # -------------------------------------------------------------------------
    cd ../func
    file_task_rest_bold="${file}_task-rest_bold"
    file_task_rest_physio="${file}_task-rest_physio"
    # Check if func files exists
    if [[ -f ${file_task_rest_bold}.nii.gz ]];then

        # Cut slices 0 and 1 for sub-HC022_ses-baselinespinalcord
        if [[ $file_task_rest_bold == *"sub-HC022_ses-baselinespinalcord"* ]];then
          sct_crop_image -i ${file_task_rest_bold}.nii.gz -zmin 2  
          mv ${file_task_rest_bold}_crop.nii.gz ${file_task_rest_bold}.nii.gz
        fi
        # Compute mean image
        sct_maths -i ${file_task_rest_bold}.nii.gz -mean t -o ${file_task_rest_bold}_mean.nii.gz
        file_task_rest_bold_mean="${file_task_rest_bold}_mean"
        
        # Create mask if doesn't exist:
        FILE_MASK="${PATH_DERIVATIVES}/${SUBJECT}/func/${file_task_rest_bold_mean}_mask.nii.gz"
        echo
        echo "Looking for manual spinal mask: $FILE_MASK"
        if [[ -e $FILE_MASK ]]; then
          echo "Found! Using manual segmentation."
          rsync -avzh $FILE_MASK "${file_task_rest_bold_mean}_mask.nii.gz"
        else
          # Segment the spinal cord
          segment_if_does_not_exist ${file_task_rest_bold_mean} 't2s' 'propseg' 'func'
          # Create a spinal canal mask
          sct_maths -i ${file_task_rest_bold_mean}_seg.nii.gz -add ${file_task_rest_bold_mean}_CSF_seg.nii.gz -o ${file_task_rest_bold_mean}_SC_canal_seg.nii.gz
          # Dilate the spinal canal mask
          # check dilating
          sct_maths -i ${file_task_rest_bold_mean}_SC_canal_seg.nii.gz -dilate 5 -shape disk -o ${file_task_rest_bold_mean}_mask.nii.gz -dim 2
          # Dilate the mask more for sub-CR008-ses-baselinespinalcord
          if [[ $file_task_rest_bold == *"CR008_ses-baselinespinalcord"* ]];then
              sct_maths -i ${file_task_rest_bold_mean}_SC_canal_seg.nii.gz -dilate 10 -shape disk -o ${file_task_rest_bold_mean}_mask.nii.gz -dim 2
          fi
          # Qc of Spinal canal segmentation
          sct_qc -i ${file_task_rest_bold_mean}.nii.gz -p sct_deepseg_sc -qc ${PATH_QC} -s ${file_task_rest_bold_mean}_SC_canal_seg.nii.gz -qc-subject ${SUBJECT}
        fi
        # Qc of mask
        sct_qc -i ${file_task_rest_bold_mean}.nii.gz -p sct_deepseg_sc -qc ${PATH_QC} -s ${file_task_rest_bold_mean}_mask.nii.gz -qc-subject ${SUBJECT}

       
        # Convert GE physio data to FSL format
        #python3 $PATH_SCRIPTS/pnm/create_FSL_physio_text_file.py -i ${file_task_rest_physio}.tsv -TR 3.0 -number-of-volumes 245

        # Run FSL physio
        # Run popp to get physio_rep.txt
        FILE_PHYSIO_CARD="${PATH_DERIVATIVES}/${SUBJECT}/func/${file_task_rest_physio}_peak.txt"
        echo
        echo "Looking for manual peak detection: $FILE_PHYSIO_CARD"
        if [[ -e $FILE_PHYSIO_CARD ]]; then
          echo "Found! Using manual segmentation."
          rsync -avzh $FILE_PHYSIO_CARD "${file_task_rest_physio}_peak.txt"
        else
          echo "No manual physio file found in the derivatives. Please run detect_peak_batch.sh before running spinal cord preprocessing."
        fi
    	  popp -i ${file_task_rest_physio}_peak.txt -o ./physio -s 100 --tr=3.0 --smoothcard=0.1 --smoothresp=0.1 --resp=2 --cardiac=5 --trigger=3 -v --pulseox_trigger
        # Run PNM using manual peak detections in derivatives
        pnm_evs -i ${file_task_rest_bold}.nii.gz -c physio_card.txt -r physio_resp.txt -o physio_ --tr=3.0 --oc=4 --or=4 --multc=2 --multr=2 --sliceorder=interleaved_up --slicedir=z
        mkdir -p PNM
    	  mv physio* ./PNM/
        mv ${file_task_rest_physio}_peak.txt ./PNM/

        # --------------------
        # 2D Motion correction
        # --------------------
#<<comment
        # Step 1 of 2D motion correction using mid volume
        # Select mid volume
        fslroi ${file_task_rest_bold} ${file_task_rest_bold}_mc1_ref 125 1
        # Apply motion correction
        ${PATH_SCRIPTS}/motion_correction/2D_slicewise_motion_correction.sh -i ${file_task_rest_bold}.nii.gz -r ${file_task_rest_bold}_mc1_ref.nii.gz -m ${file_task_rest_bold_mean}_mask.nii.gz -o mc1
        

        # Step 2 of 2D motion correction using mean of mc1 as ref
        # Segment the spinal cord
        segment_if_does_not_exist mc1_mean 't2s' 'propseg' 'func'
        # Create a spinal canal mask
        sct_maths -i mc1_mean_seg.nii.gz -add mc1_mean_CSF_seg.nii.gz -o mc1_mean_SC_canal_seg.nii.gz
        # Dilate the spinal canal mask
        # check dilating
        sct_maths -i mc1_mean_SC_canal_seg.nii.gz -dilate 5 -shape disk -o mc1_mask.nii.gz -dim 2
        # Qc of Spinal canal segmentation
        sct_qc -i mc1_mean.nii.gz -p sct_deepseg_sc -qc ${PATH_QC} -s mc1_mean_SC_canal_seg.nii.gz -qc-subject ${SUBJECT}
        # Qc of mask
        sct_qc -i  mc1_mean.nii.gz -p sct_deepseg_sc -qc ${PATH_QC} -s mc1_mask.nii.gz -qc-subject ${SUBJECT}

        # Apply motion correction step 2
        ${PATH_SCRIPTS}/motion_correction/2D_slicewise_motion_correction.sh -i mc1.nii.gz -r mc1_mean.nii.gz -m mc1_mask.nii.gz -o mc2

        mv mc2.nii.gz ${file_task_rest_bold}_mc2.nii.gz
        mv mc2_mean.nii.gz ${file_task_rest_bold}_mc2_mean.nii.gz
        mv mc2_tsnr.nii.gz ${file_task_rest_bold}_mc2_tsnr.nii.gz
        mv mc2_mat.tar.gz ${file_task_rest_bold}_mc2_mat.tar.gz

        # Move motion regressors to .PNM
        mv Rz.nii.gz ./PNM
        mv Tx.nii.gz ./PNM
        mv Ty.nii.gz ./PNM

        # Create spinal cord mask and spinal canal mask
        file_task_rest_bold_mc2=${file_task_rest_bold}_mc2
        file_task_rest_bold_mc2_mean=${file_task_rest_bold}_mc2_mean

        FILE_SPINAL_CANAL_SEG="${PATH_DERIVATIVES}/${SUBJECT}/func/${file_task_rest_bold_mc2_mean}_SC_canal_seg.nii.gz"
        echo
        echo "Looking for manual spinal canal segmentation: $FILE_SPINAL_CANAL_SEG"
        if [[ -e $FILE_SPINAL_CANAL_SEG ]]; then
          echo "Found! Using manual segmentation."
          rsync -avzh $FILE_SPINAL_CANAL_SEG "${file_task_rest_bold_mc2_mean}_SC_canal_seg.nii.gz"
        else
          echo "No manual spinal canal segmentation found in the derivatives. Running automatic segmentation."
          segment_if_does_not_exist ${file_task_rest_bold_mc2_mean} 't2s' 'propseg' 'anat'
          sct_maths -i ${file_task_rest_bold_mc2_mean}_seg.nii.gz -add ${file_task_rest_bold_mc2_mean}_CSF_seg.nii.gz -o ${file_task_rest_bold_mc2_mean}_SC_canal_seg.nii.gz

        fi

        # Qc of Spinal canal segmentation
        sct_qc -i ${file_task_rest_bold_mc2_mean}.nii.gz -p sct_deepseg_sc -qc ${PATH_QC} -s ${file_task_rest_bold_mc2_mean}_SC_canal_seg.nii.gz -qc-subject ${SUBJECT}

        # Create segmentation using sct_deepseg_sc
        segment_if_does_not_exist ${file_task_rest_bold_mc2_mean} 't2s' 'deepseg' 'func'
        file_task_rest_bold_mc2_mean_seg="${file_task_rest_bold_mc2_mean}_seg"

        sct_qc -i ${file_task_rest_bold_mc2}.nii.gz -p sct_fmri_moco -qc ${PATH_QC} -s ${file_task_rest_bold_mc2_mean_seg}.nii.gz -d  ${file_task_rest_bold}.nii.gz -qc-subject ${SUBJECT}
        
        # Register to template
        sct_register_multimodal -i ${SCT_DIR}/data/PAM50/template/PAM50_t2.nii.gz -iseg ${SCT_DIR}/data/PAM50/template/PAM50_cord.nii.gz -d ${file_task_rest_bold_mc2_mean}.nii.gz -dseg ${file_task_rest_bold_mc2_mean_seg}.nii.gz -param step=1,type=seg,algo=centermass:step=2,type=seg,algo=bsplinesyn,metric=MeanSquares,slicewise=1,iter=3:step=3,type=im,algo=syn,metric=CC,iter=1,slicewise=1 -initwarp ../anat/T2star/warp_PAM50_t2s2${file_t2star}.nii.gz -initwarpinv ../anat/T2star/warp_${file_t2star}2PAM50_t2s.nii.gz -qc ${PATH_QC} -qc-subject ${SUBJECT}
        # TODO: test out: step=1,type=seg,algo=centermassrot:step=2,type=seg,algo=bsplinesyn,slicewise=1,iter=3:step=3,type=im,algo=syn,slicewise=1,iter=1,metric=CC
        # Add -s 1 to warp spinal template too
        sct_warp_template -d ${file_task_rest_bold_mc2_mean}.nii.gz -w warp_PAM50_t22${file_task_rest_bold_mc2_mean}.nii.gz -qc ${PATH_QC} -qc-subject ${SUBJECT}
        
        # Create binarized version of ROIs
        # TODO

        # Get vertebral coverage
        python $PATH_SCRIPTS/utils/get_vertebral_coverage.py -vertfile ./label/template/PAM50_levels.nii.gz -subject ${SUBJECT} -o ${PATH_RESULTS}/vert_coverage_func.csv

        # Create CSF regressor
        file_task_rest_bold_mc2=${file_task_rest_bold}_mc2  # to remove
        # Create CSF mask form spinal cord seg and spinal canal seg
        fslmaths ${file_task_rest_bold_mc2}_mean_seg -binv temp_mask
        fslmaths ${file_task_rest_bold_mc2}_mean_SC_canal_seg -mul temp_mask ${file_task_rest_bold_mc2}_csf_mask
        rm temp_mask.nii.gz
        ${PATH_SCRIPTS}/utils/create_slicewise_regressor_from_mask.sh -i ${file_task_rest_bold_mc2}.nii.gz -m ${file_task_rest_bold_mc2}_csf_mask.nii.gz -o csf_regressor
        mv ${file_task_rest_bold_mc2}_csf_regressor.nii.gz ./PNM

        # Create WM regressor
        fslmaths ./label/template/PAM50_wm.nii.gz -thr 0.9 -bin ${file_task_rest_bold_mc2}_wm_mask
        ${PATH_SCRIPTS}/utils/create_slicewise_regressor_from_mask.sh -i ${file_task_rest_bold_mc2}.nii.gz -m ${file_task_rest_bold_mc2}_wm_mask.nii.gz -o wm_regressor
        mv ${file_task_rest_bold_mc2}_wm_regressor.nii.gz ./PNM
        
        cp ${PATH_SCRIPTS}/utils/denoise_no_resp.fsf ./
        export PATH_DATA_PROCESSED SUBJECT file_task_rest_bold
        envsubst < "denoise_no_resp.fsf" > "denoise_no_resp_${file}.fsf"
        feat denoise_no_resp_${file}.fsf

        # Create denoised image
        fslmaths ./${file_task_rest_bold_mc2}_pnm.feat/stats/res4d.nii.gz -add ./${file_task_rest_bold_mc2}_pnm.feat/mean_func.nii.gz ${file_task_rest_bold_mc2}_pnm
        tr=`fslval ${file_task_rest_bold_mc2} pixdim4` # Get TR of volumes
        fslsplit ${file_task_rest_bold_mc2}_pnm vol -t
        v=vol????.nii.gz
        fslmerge -tr ${file_task_rest_bold_mc2}_pnm ${v} ${tr}
        rm $v

        file_task_rest_bold_mc2_mean_seg=${file_task_rest_bold_mc2}_mean_seg # to remove
        file_task_rest_bold_mc2_mean=${file_task_rest_bold_mc2}_mean # to remove
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
            sct_apply_transfo -i ${vol}.nii.gz -d ${SCT_DIR}/data/PAM50/template/PAM50_t2.nii.gz -w warp_${file_task_rest_bold_mc2_mean}2PAM50_t2.nii.gz -o ${vol}2template.nii.gz -x spline
            fslmaths ${vol}2template.nii.gz -mul ${SCT_DIR}/data/PAM50/template/PAM50_cord.nii.gz ${vol}2template.nii.gz
            fslroi ${vol}2template.nii.gz ${vol}2template.nii.gz 32 75 34 75 691 263
        done
        v="vol????2template.nii.gz"
        fslmerge -tr ${file_task_rest_bold_mc2}_pnm_stc2template $v $tr # Merge warped volumes together
        rm $v
        v=vol????.nii.gz
        rm $v

        #Remove outside voxels based on spinal cord mask z limits
        sct_apply_transfo -i ${file_task_rest_bold_mc2_mean_seg}.nii.gz -d ${SCT_DIR}/data/PAM50/template/PAM50_t2.nii.gz -w warp_${file_task_rest_bold_mc2_mean}2PAM50_t2.nii.gz -o ${file_task_rest_bold_mc2_mean_seg}2template.nii.gz -x nn
        fslroi ${file_task_rest_bold_mc2_mean_seg}2template.nii.gz ${file_task_rest_bold_mc2_mean_seg}2template.nii.gz 32 75 34 75 691 263
        fslmaths ${file_task_rest_bold_mc2_mean_seg}2template.nii.gz -kernel 2 -dilD -dilD -dilD -dilD -dilD temp_mask
        fslmaths ${file_task_rest_bold_mc2}_pnm_stc2template -mul temp_mask ${file_task_rest_bold_mc2}_pnm_stc2template
        rm temp_mask.nii.gz
        
        # TODO: here or later
        # Bandpass temporal filtering (see fslmath)
        # nilearn check bandpass filter could be done here
        # spatial smoothing --> if in template space

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

