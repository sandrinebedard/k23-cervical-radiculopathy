#!/bin/bash
# ./run_voxel_based.sh -i /mnt/p/Mackeylab/Individual_Folders/Sandrine/sc_analysis_test_2023-09-07-v4/data_processed/ -m dwi -o ./here

function usage()
{
cat << EOF

DESCRIPTION
  TODO
  
USAGE
  `basename ${0}` -path-data <path-data> -modality <modality> -o <output>

MANDATORY ARGUMENTS
  -i <path-data> Path data processed
  -m <modality>        dwi or mtr
  -o <output>         Path output

EOF
}


if [ ! ${#@} -gt 0 ]; then
    usage `basename ${0}`
    exit 1
fi

# get starting time:
start=`date +%s`

#Initialization of variables

scriptname=${0}
PATH_DATA=
modality=
output=
while getopts “hi:m:o:” OPTION
do
	case $OPTION in
	 h)
			usage
			exit 1
			;;
         i)
		 	PATH_DATA=$OPTARG
         		;;
         m)
			modality=$OPTARG
         		;;
	 o)
	                output=$OPTARG
		        ;;
         ?)
             usage
             exit
             ;;
     esac
done

# Check the parameters

if [[ -z ${PATH_DATA} ]]; then
	 echo "ERROR: Input not specified. Exit program."
     exit 1
fi
if [[ -z ${modality} ]]; then
     echo "ERROR: Reference not specified. Exit program."
     exit 1
fi
if [[ -z ${output} ]]; then
    echo "ERROR: Path output not specified. Exit program."
    exit 1
fi

# Echo all the inputs
echo "PATH DATA: $PATH_DATA"
echo "MODALITY: $modality"
echo "PATH OUTPUT: $output"

# Create path output
mkdir -p ${output}
mkdir -p ${output}/images_pam50_space
path_images_pam50=${output}/images_pam50_space
cd ${output} #${path_images_pam50}

if [ ${modality} == 'dwi' ]; then
  subfolder='dwi'
else
  subfolder='anat/MTS'
fi
# Copy all contrast data and save in output
#rsync -az $PATH_DATA --include="2template.nii.gz" .

# TODO
# Get all dwi images in PAM50 space copy in output
cd ..

PAM50_vertlevels=$SCT_DIR/data/PAM50/template/PAM50_levels.nii.gz
rsync -az ${PAM50_vertlevels} .
PAM50_vertlevels="PAM50_levels"
# Keep only vert levels from 3 to 6.
sct_maths -i ${PAM50_vertlevels}.nii.gz -thr 3 -uthr 6 -o ${PAM50_vertlevels}_3_to_6.nii.gz
# Change values to 1 to create mask.
sct_maths -i ${PAM50_vertlevels}_3_to_6.nii.gz -bin 2 -o ${PAM50_vertlevels}_3_to_6_mask.nii.gz

# Get the WM mask
rsync -az $SCT_DIR/data/PAM50/template/PAM50_wm.nii.gz .
PAM50_wm='PAM50_wm'
# Apply level mask to WM mask
sct_maths -i ${PAM50_wm}.nii.gz -mul ${PAM50_vertlevels}_3_to_6_mask.nii.gz -o PAM50_wm_level_mask.nii.gz

# Loop through subjetcs

# Cut with levels 3 : 6

for file in $PATH_DATA/**/**/$subfolder/*2template.nii.gz; do
  echo "Found file: $file"
  IFS='/' read -ra arrPath <<< "$file"
  #arrPath=(${file//"/"/})
  SUBJECT=${arrPath[-4]}
  SES=${arrPath[-3]}
  echo "$SUBJECT"
  echo "$SES"
  #cp $PATH_DATA/**/**/$subfolder/*2template.nii.gz .

done

# Apply WM mask and level mask
# Create a 4D image with everything
#fslmerge
# TODO exclude subjects
# Run randomize


# Display useful info for the log
end=`date +%s`
runtime=$((end-start))
echo
echo "~~~"
echo "SCT version: `sct_version`"
echo "Ran on:      `uname -nsr`"
echo "Duration:    $(($runtime / 3600))hrs $((($runtime / 60) % 60))min $(($runtime % 60))sec"
echo "~~~"