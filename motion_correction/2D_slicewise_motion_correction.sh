#!/bin/bash
# 
#
# Created by Megan McAndrews and Kenneth Weber on 5/18/2016.
# Please cite:
#	Weber II KA, Chen Y, Wang X, Kahnt T, Parrish TB. Lateralization of Cervical Spinal Cord Activity During an Isometric Upper Extremity Motor Task. NeuroImage 2016;125:233-243.
#	Jenkinson, M., Bannister, P., Brady, M., Smith, S., 2002. Improved optimization for the robust and accurate linear registration and motion correction of brain images. Neuroimage 17, 825-841.
#	Jenkinson, M., Beckmann, C.F., Behrens, T.E., Woolrich, M.W., Smith, S.M., 2012. FSL. Neuroimage 62, 782-790.
#	Cohen-Adad, J., et al. (2009). Slice-by-slice motion correction in spinal cord fMRI: SliceCorr. Proceedings of the 17th Annual Meeting of the International Society for Magnetic Resonance in Medicine, Honolulu, USA 
#	Weber II, K. A., et al. (2014). Choice of Motion Correction Method Affects Spinal Cord fMRI Results. 20th Annual Meeting of  the Organization for Human Brain Mapping, Hamburg, Germany.


function usage()
{
cat << EOF

DESCRIPTION
  Perform 2D slicewise registration of the 4D time series input image to the reference image using the reference weighting mask image.
  Outputs include the motion corrected image time series, the motion corrected mean image, the motion corrected TSNR image, and a compressed folder containing the transformation matrices.
  Requires that FSL is installed. This was last updated using FSL Version 5.0.
  
USAGE
  `basename ${0}` -i <input> -r <reference> -m <mask> -o <output>

MANDATORY ARGUMENTS
  -i <input>                   Input image
  -r <reference>               Reference image
  -m <mask>                    Reference weighting mask image (Mask must cover all slices)
  -o <output>                  Output filename prefix

EOF
}

if [ ! ${#@} -gt 0 ]; then
    usage `basename ${0}`
    exit 1
fi

#Initialization of variables

scriptname=${0}
input=
reference=
mask=
output=
while getopts “hi:r:m:o:” OPTION
do
	case $OPTION in
	 h)
			usage
			exit 1
			;;
         i)
		 	input=$OPTARG
         		;;
	 r)
	                reference=$OPTARG
	                ;;
         m)
			mask=$OPTARG
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

if [[ -z ${input} ]]; then
	 echo "ERROR: Input not specified. Exit program."
     exit 1
fi
if [[ -z ${reference} ]]; then
     echo "ERROR: Reference not specified. Exit program."
     exit 1
fi
if [[ -z ${mask} ]]; then
    echo "ERROR: Mask not specified. Exit program."
    exit 1
fi
if [[ -z ${output} ]]; then
    echo "ERROR: Output not specified. Exit program."
    exit 1
fi

# Check if the input files exist and are readable

if [[ ! -a ${input} ]]; then
     echo "ERROR: ${input} does not exist or is not readable. Exit program."
     exit 1
fi
if [[ ! -a ${reference} ]]; then
     echo "ERROR: ${reference} does not exist or is not readable. Exit program."
     exit 1
fi
if [[ ! -a ${mask} ]]; then
    echo "ERROR: ${mask} does not exist or is not readable. Exit program."
    exit 1
fi

# Check extensions of the input files

if [[ ${input} != *.nii.gz ]] && [[ ${input} != *.nii ]] && [[ ${input} != *.img ]] && [[ ${input} != *.img.gz ]]; then
	 echo "ERROR: ${input} does not have .nii.gz, .nii, .img, or .img.gz extension. Exit program."
	 exit 1
fi
if [[ ${reference} != *.nii.gz ]] && [[ ${reference} != *.nii ]] && [[ ${reference} != *.img ]] && [[ ${reference} != *.img.gz ]]; then
	 echo "ERROR: ${reference} does not have .nii.gz, .nii, .img, or .img.gz extension. Exit program."
	 exit 1
fi
if [[ ${mask} != *.nii.gz ]] && [[ ${mask} != *.nii ]] && [[ ${mask} != *.img ]] && [[ ${mask} != *.img.gz ]]; then
	 echo "ERROR: ${maskt} does not have .nii.gz, .nii, .img, or .img.gz extension. Exit program."
	 exit 1
fi

#Remove extension from files

input=`remove_ext ${input}`
reference=`remove_ext ${reference}`
mask=`remove_ext ${mask}`

# Check if the dimensions of files are the same

xdimi=`fslval ${input} dim1`
xdimr=`fslval ${reference} dim1`
xdimm=`fslval ${mask} dim1`
ydimi=`fslval ${input} dim2`
ydimr=`fslval ${reference} dim2`
ydimm=`fslval ${mask} dim2`
zdimi=`fslval ${input} dim3`
zdimr=`fslval ${reference} dim3`
zdimm=`fslval ${mask} dim3`
tr=`fslval ${input} pixdim4` # Calculate TR or sampling period for time series

if (( "${xdimi}" != "${xdimm}" )) || (( "${xdimr}" != "${xdimm}" )) || (( "${ydimi}" != "${ydimm}" )) || (( "${ydimr}" != "${ydimm}" )) || (( "${zdimi}" != "${zdimm}" )) || (( "${zdimr}" != "${zdimm}" )); then
    echo "ERROR: Dimensions of files do not match. Exit program."
    exit 1
fi

# Check the $FSLOUTPUTTYPE and assign the extension extension

if [ ${FSLOUTPUTTYPE} == 'NIFTI_GZ' ]; then
  file_ext=nii.gz
elif [ ${FSLOUTPUTTYPE} == 'NIFTI' ]; then
  file_ext=nii
elif [ ${FSLOUTPUTTYPE} == 'NIFTI_PAIR_GZ' ]; then
  file_ext=img.gz
elif [ ${FSLOUTPUTTYPE} == 'NIFTI_PAIR' ]; then
  file_ext=img
elif [ ${FSLOUTPUTTYPE} == 'ANALYZE_GZ' ]; then
  file_ext=img.gz
elif [ ${FSLOUTPUTTYPE} == 'ANALYZE' ]; then
  file_ext=img
else
    echo "ERROR: ${FSLOUTPUTTYPE} is not supported. Exit program."
    exit 1
fi

# Move input files to temporary folder and enter temporary folder

tmp_folder=`mktemp -u tmp.XXXXXXXXXX`
mkdir ${tmp_folder}
imcp ${input} ${reference} ${mask} ./${tmp_folder}
cd ${tmp_folder}

#Remove path from input files

input=$(basename ${input})
reference=$(basename ${reference})
mask=$(basename ${mask})

# Check if mask has any empty slices before running motion correction

fslsplit ${mask} mask_slice -z ## split ${mask} into slices
last_slice=$(echo "scale=0; $zdimi-1" | bc) #get top z slice number with 0 being first slice in z direction

for ((i=0; i<=$last_slice; i++)) ; do ##for loop for slices
  slice_number="$(printf "%04d" ${i})"
  min=`fslstats mask_slice${slice_number} -R | cut -d " " -f1`
  max=`fslstats mask_slice${slice_number} -R | cut -d " " -f2`
  if [ $(echo "${min} < 0" | bc) == 1 ] || [ $(echo "${max} <= 0" | bc) == 1 ] || [ $(echo "${min} >= ${max}" | bc ) == 1 ]; then # Needed to use the bc command to compare integer to floating point variable
    echo "ERROR: Mask has empty slices. Exit program."
    cd ..
    rm -rf ${tmp_folder}
    exit 1
  fi
done

# Perform motion correction

tdimi=`fslval ${input} dim4` #Get the number of volumes
last_volume=$(echo "scale=0; $tdimi-1" | bc) #Find index of last volume

fslsplit ${reference} ref_slice -z ## split ${reference} into slices 

fslsplit ${input} vol -t # Split ${input} into volumes
for ((i=0; i<=$last_volume; i++)); do 
  vol="$(printf "vol%04d" ${i})"
  fslsplit ${vol} ${vol}_slice -z # Split each volume of input into slices
done

for ((i=0; i<=$last_slice; i++)) ; do #For loop for slices
  slice="$(printf "slice%04d" ${i})"
  for ((j=0; j<=$last_volume; j++)); do  #Performs FLIRT for each volume of the slice specified by ${vol} and ${slice}  
    vol="$(printf "vol%04d" ${j})"
    flirt -in ${vol}_${slice} -ref ref_${slice} -out ${vol}_${slice}_mcf -omat ${vol}_${slice}_mcf.mat -bins 256 -cost normcorr -nosearch -2D -refweight mask_${slice} -interp spline
    echo "flirt -in ${vol}_${slice} -ref ref_${slice} -out ${vol}_${slice}_mcf -omat ${vol}_${slice}_mcf.mat -bins 256 -cost normcorr -nosearch -2D -refweight mask_${slice} -interp spline"
  done
  v="vol????_${slice}_mcf.${file_ext}"
  fslmerge -tr merge_${slice} $v $tr #Merge motion corrected volumes of the ${slice_number} slice together
done

v="merge_slice????.${file_ext}"
fslmerge -z ${output} $v #Merge the slices together
v="vol0???_slice????_mcf.mat"
mkdir ${output}_mat #Save the .mat files for later use
mv $v ./${output}_mat/
tar -czf ${output}_mat.tar.gz ./${output}_mat

#Compute mean and TSNR images
fslmaths ${output} -Tmean ${output}_mean
fslmaths ${output} -Tstd ${output}_std
fslmaths ${output}_mean -div ${output}_std ${output}_tsnr

#Copy files to parent directory
cp ${output}_mat.tar.gz ../
imcp ${output} ${output}_mean ${output}_tsnr ../

#Move up to parent directory
cd ..

#Delete temporary folder

rm -rf ${tmp_folder}

echo "Run the following to view the results:"
echo "fslview ${output} ${output}_mean ${output}_tsnr -l render3 &"

exit 0
