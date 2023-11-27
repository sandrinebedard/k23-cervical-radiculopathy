#!/usr/bin/env python
# -*- coding: utf-8
# Get min and max complete vertebral levels from labeled segmentation
#
# For usage, type: python create_right_left_seg_mask.py -h

# Authors: Sandrine Bédard

import argparse
import numpy as np
import nibabel as nib
from skimage.segmentation import expand_labels


def get_parser():
    parser = argparse.ArgumentParser(
        description="Create Right left segmentation mask from PAM50")
    parser.add_argument('-seg', required=True, type=str,
                        help="Spinal cord segmentation .nii.gz file")
    parser.add_argument('-PAM50-R', required=True, type=str,
                        help="Mask of Right hemicord from warped PAM50 template.")
    parser.add_argument('-PAM50-L', required=False, type=str,
                        help="Mask of Left hemicord from warped PAM50 template.")

    return parser


def save_Nifti1(data, original_image, filename):
    empty_header = nib.Nifti1Header()
    image = nib.Nifti1Image(data, original_image.affine, empty_header)
    nib.save(image, filename)


def main():
    parser = get_parser()
    args = parser.parse_args()

    seg = nib.load(args.seg)
    seg_np = seg.get_fdata()
    pam50_r = nib.load(args.PAM50_R).get_fdata()
    pam50_l = nib.load(args.PAM50_L).get_fdata()
    pam50_r_l = np.zeros(np.shape(seg_np))
    pam50_r_l[np.where(pam50_r > 0)] = 1
    pam50_r_l[np.where(pam50_l > 0)] = 2
    # Dilate mask such as the labels don't overlap
    pam50_r_l_dilated = expand_labels(pam50_r_l, distance=7) # changed to 5 to 7, to validate
    mask_right = np.zeros(np.shape(seg_np))
    mask_right[np.where(pam50_r_l_dilated == 1)] = 1
    mask_left = np.zeros(np.shape(seg_np))
    mask_left[np.where(pam50_r_l_dilated == 2)] = 1
    seg_r = seg_np*mask_right
    seg_l = seg_np*mask_left
    save_Nifti1(seg_r, seg, args.seg.split('.')[0]+'_right.nii.gz')
    save_Nifti1(seg_l, seg, args.seg.split('.')[0]+'_left.nii.gz')


if __name__ == '__main__':
    main()
