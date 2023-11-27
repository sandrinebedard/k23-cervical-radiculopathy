#!/usr/bin/env python
# -*- coding: utf-8
# For usage, type: python create_roi.py -h

# Create rois for resting state functional connectivity analysis. Either for subject's space or for PAM50 space
# To create ROIS for PAM50 space:
# python create_roi.py -label /mnt/c/Users/sb199/spinalcordtoolbox/data/PAM50/ -levels 5 6 7 
# -thr 0.5 -o-folder /mnt/c/Users/sb199/Projet3_data/k23_cervical_radiculopathy/ -number-slices 24

# Author: Sandrine Bédard

import os
import argparse
import logging
import numpy as np
import nibabel as nib
import sys
from scipy.ndimage import center_of_mass


FNAME_LOG = 'roi_info.txt'

ROIS = [
    'PAM50_atlas_30.nii.gz',
    'PAM50_atlas_31.nii.gz',
    'PAM50_atlas_34.nii.gz',
    'PAM50_atlas_35.nii.gz'
]

# Initialize logging
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)  # default: logging.DEBUG, logging.INFO
hdlr = logging.StreamHandler(sys.stdout)
logging.root.addHandler(hdlr)


def get_parser():
    parser = argparse.ArgumentParser(
        description="Create ROIS for functional analysis for right/left dorsal and ventral horns of the spinal cord.")
    parser.add_argument("-label",
                        required=True,
                        type=str,
                        help="Folder with labels with atlas and spinal levels")
    parser.add_argument("-levels",
                        nargs='+',
                        required=True,
                        default=[4, 5, 6, 7],
                        help="Spinal levels to use to create roi")
    parser.add_argument("-number-slices",
                        type=int,
                        required=True,
                        help="Number of slices per roi")
    parser.add_argument("-thr",
                        required=True,
                        type=float,
                        default=0.5,
                        help="Threshold for atlas")
    parser.add_argument("-o-folder",
                        required=True,
                        help="Output folder to write ROIS")
    return parser


def save_Nifti1(data, original_image, filename):
    empty_header = nib.Nifti1Header()
    image = nib.Nifti1Image(data, original_image.affine, empty_header)
    nib.save(image, filename)


def main():

    args = get_parser().parse_args()
    # Get input argments
    path_labels = args.label
    path_spinal_levels = os.path.join(path_labels, 'spinal_levels')
    path_atlas = os.path.join(path_labels, 'atlas')
    levels = args.levels
    thr = args.thr
    # Initialize values for each label
    output_folder = args.o_folder
    # Create output folder if does not exist.
    if not os.path.exists(output_folder):
        os.makedirs(output_folder)

    # Dump log file there
    if os.path.exists(FNAME_LOG):
        os.remove(FNAME_LOG)
    fh = logging.FileHandler(os.path.join(output_folder, FNAME_LOG))
    logging.root.addHandler(fh)

    # number-slices
    nb_slices = args.number_slices

    i = 1
    # Loop through levels
    for level in levels:
        print(f'Creating roi for level {level}')
        img_spinal = nib.load(os.path.join(path_spinal_levels, 'spinal_level_0' + str(level) + '.nii.gz'))
        img_spinal_np = img_spinal.get_fdata()
        img_spinal_np_center = int(center_of_mass(img_spinal_np)[-1])
        for roi in ROIS:
            roi_nib = nib.load(os.path.join(path_atlas, roi))
            roi_np = roi_nib.get_fdata()
            roi_np_mask = np.zeros(roi_np.shape)
            if nb_slices > 1:
                roi_np_mask[:, :, img_spinal_np_center - nb_slices//2: img_spinal_np_center + nb_slices//2] = np.where(roi_np[:, :, img_spinal_np_center - nb_slices//2: img_spinal_np_center + nb_slices//2] > thr, 1, 0)*i
            else:
                roi_np_mask[:, :, img_spinal_np_center] = np.where(roi_np[:, :, img_spinal_np_center] > thr, 1, 0)*i
            fname = roi.split('.')[-3] + '_level_' + str(level) + '.nii.gz'
            print(f'Saving {fname}')
            save_Nifti1(roi_np_mask, roi_nib, os.path.join(output_folder, fname))
            i = i + 1

    # Write information about labels
    logger.info(f'Created from path labels: {path_labels}')
    logger.info(f'Number of slices: {nb_slices}')
    logger.info(f'Threshold: {thr}')
    logger.info(f'Spinal Levels: {levels}')


if __name__ == "__main__":
    main()
