#!/bin/bash
# 
#
# Created by Kenneth Weber on 6/7/2022.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#

function usage()
{
cat << EOF

DESCRIPTION
  Create slicewise regressors from a 4D time series input image using a binary mask image.
  Output is a NIFTI image of slicewise regressors and can be input into FEAT.
  Requires that FSL is installed. This was last updated using FSL Version 6.0.
  
USAGE
  `basename ${0}` -i <input> -m <mask> -o <output>

MANDATORY ARGUMENTS
  -i <input>      		      Input image
  -m <mask>                   Mask image
  -o <output>                 Output filename postfix

EOF
}

if [ ! ${#@} -gt 0 ]; then
    usage `basename ${0}`
    exit 1
fi

#Initialization of variables
scriptname=${0}
input=
mask=
output=

while getopts “hi:m:o:” OPTION
do
	case $OPTION in
	 h)
			usage
			exit 1
			;;
         i)
		 	input=$OPTARG
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
	 echo "ERROR: Input image not specified. Exit program."
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

if [[ ! -a ${mask} ]]; then
    echo "ERROR: ${mask} does not exist or is not readable. Exit program."
    exit 1
fi

# Check extensions of the input files
if [[ ${input} != *.nii.gz ]] && [[ ${input} != *.nii ]] && [[ ${input} != *.img ]] && [[ ${input} != *.img.gz ]]; then
	 echo "ERROR: ${input} does not have .nii.gz, .nii, .img, or .img.gz extension. Exit program."
	 exit 1
fi

if [[ ${mask} != *.nii.gz ]] && [[ ${mask} != *.nii ]] && [[ ${mask} != *.img ]] && [[ ${mask} != *.img.gz ]]; then
	 echo "ERROR: ${maskt} does not have .nii.gz, .nii, .img, or .img.gz extension. Exit program."
	 exit 1
fi

#Remove extension from files
input=`remove_ext ${input}`
mask=`remove_ext ${mask}`


# Check if the dimensions of files are the same
xdimi=`fslval ${input} dim1`
xdimm=`fslval ${mask} dim1`

ydimi=`fslval ${input} dim2`
ydimm=`fslval ${mask} dim2`

zdimi=`fslval ${input} dim3`
zdimm=`fslval ${mask} dim3`

tdimi=`fslval ${input} dim4`
tdimm=`fslval ${mask} dim4`
tr=`fslval ${input} pixdim4` # Calculate TR or sampling period for time series

if (( "${xdimi}" != "${xdimm}" )) || (( "${ydimi}" != "${ydimm}" )) || (( "${zdimi}" != "${zdimm}" )); then
    echo "ERROR: Dimensions of files do not match. Exit program."
    exit 1
fi

if (( "${tdimm}" != 1 )); then
    echo "ERROR: Mask image contains multiple volumes. Exit program."
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
imcp ${input} ${mask} ./${tmp_folder}
cd ${tmp_folder}

#Remove path from input files
input=$(basename ${input})
mask=$(basename ${mask})

fslsplit ${mask} ${mask}_slice -z
fslsplit ${input} ${input}_slice -z

for ((k=0; k<$zdimi; k++)) ; do
	slice_number=$((10000+$k))
	fslstats -t ${input}_slice${slice_number:1:4} -k ${mask}_slice${slice_number:1:4} -m >> ${input}_slice${slice_number:1:4}_mean.txt
	fslascii2img ${input}_slice${slice_number:1:4}_mean.txt 1 1 1 $tdimi 1 1 1 $tr ${input}_slice${slice_number:1:4}_mean
	fslmaths ${input}_slice${slice_number:1:4}_mean -Tmean mean
	fslmaths ${input}_slice${slice_number:1:4}_mean -sub mean ${input}_slice${slice_number:1:4}_mean
	rm mean.nii.gz
	rm ${input}_slice${slice_number:1:4}_mean.txt
done

v="${input}_slice0???_mean.nii.gz"
fslmerge -z ${input}_${output} $v

#Copy files to parent directory
imcp ${input}_${output} ../

#Move up to parent directory
cd ..

#Delete temporary folder

rm -rf ${tmp_folder}

echo "Run the following to view the results:"
echo "fslview_deprecated ${input}_${output} &"

exit 0
