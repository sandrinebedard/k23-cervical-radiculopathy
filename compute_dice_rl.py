#!/usr/bin/env python
# -*- coding: utf-8
# 
#
# For usage, type: python create_right_left_seg_mask.py -h

# Authors: Sandrine Bédard

import argparse
import numpy as np
import nibabel as nib
from scipy.ndimage import center_of_mass


def get_parser():
    parser = argparse.ArgumentParser(
        description="Create Right left segmentation mask from PAM50")
    parser.add_argument('-seg', required=True, type=str,
                        help="Spinal cord segmentation .nii.gz file")
    return parser


def compute_dice(im1, im2, empty_score=np.nan):
    """Computes the Dice coefficient between im1 and im2.
    Compute a soft Dice coefficient between im1 and im2, ie equals twice the sum of the two masks product, divided by
    the sum of each mask sum.
    If both images are empty, then it returns empty_score.

    Args:
        im1 (ndarray): First array.
        im2 (ndarray): Second array.
        empty_score (float): Returned value if both input array are empty.

    Returns:
        float: Dice coefficient.
    """
    im1 = np.asarray(im1)
    im2 = np.asarray(im2)

    if im1.shape != im2.shape:
        raise ValueError("Shape mismatch: im1 and im2 must have the same shape.")

    im_sum = im1.sum() + im2.sum()
    if im_sum == 0:
        return empty_score

    intersection = (im1 * im2).sum()
    return (2. * intersection) / im_sum


def save_Nifti1(data, original_image, filename):
    empty_header = nib.Nifti1Header()
    image = nib.Nifti1Image(data, original_image.affine, empty_header)
    nib.save(image, filename)


NEAR_ZERO_THRESHOLD = 1e-6


def main():
    parser = get_parser()
    args = parser.parse_args()
# TODO reorient to RPI!!!
    seg = nib.load(args.seg)
    seg_np = seg.get_fdata()
    X, Y, Z = (seg_np > NEAR_ZERO_THRESHOLD).nonzero()
    z_min = min(Z)
    z_max = max(Z)
    print(z_min, z_max)
    seg_np_crop = seg_np[:, :, z_min: z_max + 1]
    print(seg_np_crop.shape)
    # Get center of mass of each slice
    idx_center_of_mass = []
    for i in range(seg_np_crop.shape[-1]):
        idx_center_of_mass.append(list(center_of_mass(seg_np_crop[:, :, i]))[0])
    idx_center_of_mass = [int(ele) for ele in idx_center_of_mass]
    # Split mask in R-L
    mask_right = np.zeros(seg_np_crop.shape)
    mask_left = np.zeros(seg_np_crop.shape)
    # If reg to template works, should use next commented lines
    # mask_right[70::, :, :] = 1
    # mask_left[0:71,:,:] = 1
    for i in range(seg_np_crop.shape[-1]):
        mask_right[idx_center_of_mass[i]::, :, i] = 1
        mask_left[0:idx_center_of_mass[i]+1, :, i] = 1
    seg_np_crop_r = seg_np_crop*mask_right
    seg_np_crop_l = seg_np_crop*mask_left

    # Put back in original space
    seg_np_r = np.zeros(seg_np.shape)
    seg_np_r[:, :, z_min:z_max+1] = seg_np_crop_r
    seg_np_l = np.zeros(seg_np.shape)
    seg_np_l[:, :, z_min:z_max+1] = seg_np_crop_l
    # Save nifti files
    save_Nifti1(seg_np_r, seg, args.seg.split('.')[0]+'_right.nii.gz')
    save_Nifti1(seg_np_l, seg, args.seg.split('.')[0]+'_left.nii.gz')

    # Compute dice score between R and L masks:
    dice = compute_dice(seg_np_crop_r[::-1, :, :], seg_np_crop_l)
    print(dice)
    # TODO: compute dice slicewise


if __name__ == '__main__':
    main()
