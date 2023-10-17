#!/usr/bin/env python
# -*- coding: utf-8
#
#
# For usage, type: python create_right_left_seg_mask.py -h
#
# Run before:
# reorient to RPI
# sct_register_to_template -i sub-CR034_ses-baselinespinalcord_T2w.nii.gz -s sub-CR034_ses-baselinespinalcord_T2w_seg.nii.gz -ldisc sub-CR034_ses-baselinespinalcord_T2w_seg_labeled_discs_1to9.nii.gz -param step=1,type=imseg,algo=centermassrot,metric=MeanSquares,iter=10,smooth=0,gradStep=0.5,slicewise=0,smoothWarpXY=2,pca_eigenratio_th=1.6 -qc ./qc
#
# sct_apply_transfo -i sub-CR034_ses-baselinespinalcord_T2w_seg.nii.gz -d anat2template.nii.gz -w warp_anat2template.nii.gz -o sub-CR034_ses-baselinespinalcord_T2w_seg_reg.nii.gz -x nn


# Authors: Sandrine Bédard

import argparse
import os
import numpy as np
import nibabel as nib
import csv
from scipy.ndimage import center_of_mass


def get_parser():
    parser = argparse.ArgumentParser(
        description="Create Right left segmentation mask from PAM50")
    parser.add_argument('-seg', required=True, type=str,
                        help="Spinal cord segmentation .nii.gz file")
    parser.add_argument('-vertfile', required=True, type=str,
                        help="Vertebral levels file of PAM50.")
    parser.add_argument("-levels",
                        nargs='+',
                        required=True,  # To change
                        default=[3, 4, 5, 6],
                        help="Vertebral levels to use to compute dice.")
    parser.add_argument("-fname-out",
                        type=str,
                        required=True,  # To change
                        help="Filename to save results")
    parser.add_argument("-subject",
                        type=str,
                        required=True,  # To change
                        help="Subject ID")
    parser.add_argument("-session",
                        type=str,
                        required=True,  # To change
                        help="session: e.g. ses-baselinespinalcord")



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
    vertfile = nib.load(args.vertfile)
    vertfile_np = vertfile.get_fdata()
    levels = args.levels
    fname_out = args.fname_out
    subject = args.subject
    session = args.session
# TODO reorient to RPI!!! --> or allready okay since PAM50 space??

    seg = nib.load(args.seg)
    seg_np = seg.get_fdata()
    X, Y, Z = (seg_np > NEAR_ZERO_THRESHOLD).nonzero()
    Z = np.sort(Z)
    print('Z', Z)
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
    for i in range(seg_np_crop.shape[-1]):
        mask_right[idx_center_of_mass[i]::, :, i] = 1
        mask_left[0:idx_center_of_mass[i]+1, :, i] = 1
    # If reg to template works, should use next commented lines
    #mask_right[70::, :, :] = 1
    #mask_left[0:71,:,:] = 1
    seg_np_crop_r = seg_np_crop*mask_right
    seg_np_crop_l = seg_np_crop*mask_left

    # Put back in original space
    seg_np_r = np.zeros(seg_np.shape)
    seg_np_r[:, :, z_min:z_max+1] = seg_np_crop_r
    seg_np_l = np.zeros(seg_np.shape)
    seg_np_l[:, :, z_min:z_max+1] = seg_np_crop_l

    vert_masked = np.where((vertfile_np > 6), 0, vertfile_np)#.astype(np.int_) 
    vert_masked = np.where((vert_masked < 3), 0, vert_masked)#.astype(np.int_) 
    vert_masked_bin = (vert_masked > 0.5).astype(np.int_)
    X_vert, Y_vert, Z_vert = (vert_masked_bin > NEAR_ZERO_THRESHOLD).nonzero()
    z_vert_min = min(Z_vert)
    z_vert_max = max(Z_vert)
    print(f'Min vert mask: {z_vert_min}, Max: {z_vert_max}')
    # Save nifti files
    seg_np_r = seg_np_r*vert_masked_bin
    seg_np_l = seg_np_l*vert_masked_bin
    save_Nifti1(vert_masked_bin, seg, args.seg.split('.')[0]+'_vertmask.nii.gz')
    save_Nifti1(seg_np_r, seg, args.seg.split('.')[0]+'_right.nii.gz')
    save_Nifti1(seg_np_l, seg, args.seg.split('.')[0]+'_left.nii.gz')

    # Compute dice score between R and L masks:
    dice = compute_dice(seg_np_crop_r[::-1, :, :], seg_np_crop_l)
    print("Dice score", dice)
    # TODO: compute dice slicewise
    dices = []
    slices = []
    level = []
    print(seg_np_crop_l.shape[2])
    for i in range(z_vert_min, z_vert_max + 1):
        dice = compute_dice(seg_np_r[::-1, :, i], seg_np_l[:,:,i])
        dices.append(dice)
        slices.append(i)
        level.append(vertfile_np[70,71,i])
        print(f'Slice {i}; Level {vertfile_np[70,71,i]} dice = {dice}')
        if not os.path.isfile(fname_out):
            with open(fname_out, 'w') as csvfile:
                header = ['Subject', 'Session', 'Slice', 'Level', 'Dice']
                writer = csv.DictWriter(csvfile, fieldnames=header)
                writer.writeheader()
        with open(fname_out, 'a') as csvfile:
            spamwriter = csv.writer(csvfile, delimiter=',')
            line = [subject, session, i, vertfile_np[70,71,i], dice]
            spamwriter.writerow(line)


if __name__ == '__main__':
    main()
