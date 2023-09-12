#!/usr/bin/env python
# -*- coding: utf-8

# Analyse resting state functional connectivity in subject's space

# Author: Sandrine Bédard

import os
import logging
import argparse
import sys
import numpy as np
import nilearn
import nibabel as nib
import matplotlib.pyplot as plt
from nilearn.maskers import NiftiLabelsMasker
from nilearn.connectome import ConnectivityMeasure
from nilearn import plotting
from nilearn import image
from nilearn.signal import butterworth
from scipy.ndimage import center_of_mass

from nilearn import datasets


FNAME_LOG = 'log_stats.txt'

# Initialize logging
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)  # default: logging.DEBUG, logging.INFO
hdlr = logging.StreamHandler(sys.stdout)
logging.root.addHandler(hdlr)


def get_parser():
    parser = argparse.ArgumentParser(description="Create correlation matrix for one subject")
    parser.add_argument("-i",
                        required=True,
                        type=str,
                        help="Input image (retsing state bold) cleaned to compute connectivity")

    parser.add_argument("-path-rois",
                        required=True,
                        help="Path to rois.")

    parser.add_argument("-low-freq",
                        type=float,
                        required=False,
                        default=0.010,
                        help='Low frequency for bandpass filtering.')

    parser.add_argument("-high-freq",
                        type=float,
                        required=False,
                        default=0.13,
                        help='High frequency for bandpass filtering.')

    parser.add_argument("-TR",
                        type=float,
                        required=False,
                        default=3,
                        help='TR of images')

    parser.add_argument("-o",
                        type=str,
                        required=False,
                        help="Name of connectivity matrix.")
    return parser


ROIS_DICT = {
    'PAM50_atlas_30_level_4.nii.gz': 'lv_4',
    'PAM50_atlas_31_level_4.nii.gz': 'rv_4',
    'PAM50_atlas_34_level_4.nii.gz': 'ld_4',
    'PAM50_atlas_35_level_4.nii.gz': 'rd_4',
    'PAM50_atlas_30_level_5.nii.gz': 'lv_5',
    'PAM50_atlas_31_level_5.nii.gz': 'rv_5',
    'PAM50_atlas_34_level_5.nii.gz': 'ld_5',
    'PAM50_atlas_35_level_5.nii.gz': 'rd_5',
    'PAM50_atlas_30_level_6.nii.gz': 'lv_6',
    'PAM50_atlas_31_level_6.nii.gz': 'rv_6',
    'PAM50_atlas_34_level_6.nii.gz': 'ld_6',
    'PAM50_atlas_35_level_6.nii.gz': 'rd_6',
#    'PAM50_atlas_30_level_7.nii.gz': 'lv_7',
#    'PAM50_atlas_31_level_7.nii.gz': 'rv_7',
#    'PAM50_atlas_34_level_7.nii.gz': 'ld_7',
#    'PAM50_atlas_35_level_7.nii.gz': 'rd_7'
}


def save_Nifti1(data, original_image, filename):
    empty_header = nib.Nifti1Header()
    image = nib.Nifti1Image(data, original_image.affine, empty_header)
    nib.save(image, filename)


def main():

    args = get_parser().parse_args()
    # Get input argments
    fname_bold = args.i
    image_bold = image.load_img(fname_bold)
    path_rois = args.path_rois
    low_freq = args.low_freq
    high_freq = args.high_freq
    fname_out = args.o

    # TODO: add spatial smoothing if in native space
    print('Loading rois')
    atlas = image.load_img(path_rois + '/*.nii.gz', wildcards=True)
    atlas = image.math_img('np.sum(img, axis=-1, keepdims=True)', img=atlas)
    print('atals SC')
    print(atlas)
    #bg_img = os.path.join(args.PAM50, 'data', 'PAM50','template', 'PAM50_t2.nii.gz')
    #plotting.plot_roi(atlas, image_bold_mean)
    #nilearn.plotting.show()

    labels = [label for label in ROIS_DICT.values()]
    logger.info('Masking...')
    masker = NiftiLabelsMasker(labels_img=atlas,
                               labels=labels,
                               standardize="zscore_sample",
                               high_pass=low_freq,
                               low_pass=high_freq,
                               t_r=3,
                               verbose=5)

    logger.info('Fit transform')
    time_series = masker.fit_transform(image_bold)
    print(time_series.shape)
    print('\nconnectivity measures')
    correlation_measure = ConnectivityMeasure(kind="correlation")

    correlation_matrix = correlation_measure.fit_transform([time_series])
    correlation_matrix = correlation_matrix[0]
    # Plot the correlation matrix
    # Mask the main diagonal for visualization:
    np.fill_diagonal(correlation_matrix, 0)
    # matrices are ordered for block-like representation
    print(labels)
    print(correlation_matrix)
    display = plotting.plot_matrix(
        correlation_matrix,
        figure=(10, 8),
        labels=labels,
#        vmax=0.8,
#        vmin=-0.8,
        reorder=False,
    )
    nilearn.plotting.show()
    display.figure.savefig(fname_out.split('.')[0] + '.png',dpi=300,)
    # Save correlation matrix
    np.savetxt(fname_out, correlation_matrix, delimiter=",")


if __name__ == "__main__":
    main()
