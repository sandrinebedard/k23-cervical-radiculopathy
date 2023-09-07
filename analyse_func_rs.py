#!/usr/bin/env python
# -*- coding: utf-8

# Analyses results of anatomical data

# Author: Sandrine Bédard

import os
import logging
import argparse
import sys
import numpy as np
import pandas as pd
import matplotlib as mpl
import matplotlib.pyplot as plt
import seaborn as sns
from datetime import datetime
import scipy.stats as stats
import nilearn
from nilearn.maskers import NiftiMasker
from nilearn.maskers import NiftiMapsMasker
from nilearn.maskers import NiftiLabelsMasker
from nilearn.connectome import ConnectivityMeasure
from nilearn import plotting
from nilearn import image

from nilearn import datasets


FNAME_LOG = 'log_stats.txt'

# Initialize logging
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)  # default: logging.DEBUG, logging.INFO
hdlr = logging.StreamHandler(sys.stdout)
logging.root.addHandler(hdlr)


def get_parser():
    parser = argparse.ArgumentParser()
    parser.add_argument("-i-folder",
                        required=True,
                        type=str,
                        help="data_processed folder for spinal cord preprocessing")
    parser.add_argument("-session",
                        required=True,
                        choices=['baselinespinalcord','followupspinalcord'],
                        default='baseline',
                        help="Session to analyse")
    parser.add_argument("-o-folder",
                        type=str,
                        required=True,
                        help="Folder to right results")
    parser.add_argument("-PAM50",
                        required=False,
                        help="PAM50 data dir")
    parser.add_argument("-exclude-list",
                        required=False,
                        type=str,
                        help="Subjects to exclude form analysis")
    parser.add_argument("-subject",
                        required=False,
                        help="Subject to analyse")
    return parser

ROIS_DICT = {
    'PAM50_atlas_30_bin.nii.gz': 'left ventral horn',
    'PAM50_atlas_31_bin.nii.gz': 'right ventral horn',
    'PAM50_atlas_34_bin.nii.gz': 'left dorsal horn',
    'PAM50_atlas_35_bin.nii.gz': 'right dorsal horn'
}

ROIS = [
    'PAM50_atlas_30_bin.nii.gz',
    'PAM50_atlas_31_bin.nii.gz',
    'PAM50_atlas_34_bin.nii.gz',
    'PAM50_atlas_35_bin.nii.gz'
]

def main():

    args = get_parser().parse_args()
    # Get input argments
    input_folder = args.i_folder
    if args.exclude_list:
        exclude_list = args.exclude_list
    else:
        exclude_list = None
    session = 'ses-'+args.session
    output_folder = args.o_folder
    # Create output folder if does not exist.
    if not os.path.exists(output_folder):
        os.mkdir(output_folder)
    os.chdir(output_folder)

    # Dump log file there
    if os.path.exists(FNAME_LOG):
        os.remove(FNAME_LOG)
    fh = logging.FileHandler(os.path.join(output_folder, FNAME_LOG))
    logging.root.addHandler(fh)

    subject = args.subject
    # sub-CR001_ses-baselinespinalcord_task-rest_bold_mc2_pnm_stc.nii.gz
    fname_bold_clean = os.path.join(input_folder, subject, session, 'func', subject + '_'+session+'_task-rest_bold_mc2_pnm_stc2template.nii.gz' )
    # Load image 
    image_bold_clean = image.load_img(fname_bold_clean)
   # nilearn.plotting.plot_img(image.index_img(image_bold_clean, 0))
    #nilearn.plotting.show()

    dataset = datasets.fetch_atlas_harvard_oxford('cort-maxprob-thr25-2mm')
    atlas_filename = dataset.maps
    # labels = dataset.labels
    print(atlas_filename)
    # data = datasets.fetch_development_fmri(n_subjects=1, reduce_confounds=True)
    # fmri_filenames = data.func[0]
    # reduced_confounds = data.confounds[0]  # This is a preselected set of confounds
    # masker = NiftiLabelsMasker(
    #     labels_img=atlas_filename,
    #     standardize="zscore_sample",
    #     standardize_confounds="zscore_sample",
    #     memory="nilearn_cache",
    #     verbose=5,
    # )
    # time_series = masker.fit_transform(fmri_filenames, confounds=reduced_confounds)
    # print(time_series.shape)


    # from nilearn.connectome import ConnectivityMeasure

    # correlation_measure = ConnectivityMeasure(
    #     kind="correlation"
    # )
    # correlation_matrix = correlation_measure.fit_transform([time_series])[0]

    # # Plot the correlation matrix
    # import numpy as np

    # from nilearn import plotting

    # # Make a large figure
    # # Mask the main diagonal for visualization:
    # np.fill_diagonal(correlation_matrix, 0)
    # # The labels we have start with the background (0), hence we skip the
    # # first label
    # # matrices are ordered for block-like representation
    # plotting.plot_matrix(
    #     correlation_matrix,
    #     figure=(10, 8),
    #     labels=labels[1:],
    #     vmax=0.8,
    #     vmin=-0.8,
    #     title="Confounds",
    #     reorder=True,
    # )
    # nilearn.plotting.show()
    # #plotting.plot_roi(atlas_filename)
    # #nilearn.plotting.show()

    # get PAM50 atlas
    #path_PAM50_atlas = os.path.join(args.PAM50, 'data', 'PAM50', 'atlas')
    path_PAM50_atlas = args.PAM50
    path_rois = [path_PAM50_atlas + '/' + roi for roi in ROIS]
    logger.info('Loading PAM50')
    atlas = image.load_img(path_PAM50_atlas+'/*.nii.gz', wildcards=True)
    print(atlas)
    atlas = image.math_img('np.sum(img, axis=-1, keepdims=True)', img=atlas)
    print(atlas)
    bg_img = os.path.join(args.PAM50, 'data', 'PAM50','template', 'PAM50_t2.nii.gz')
#    plotting.plot_roi(atlas, bg_img)
#    nilearn.plotting.show()
    

    #atlas.get_fdata()[atlas.get_fdata()>=0.5] = 1
    #atlas.get_fdata()[atlas.get_fdata()<0.5] = 0
    #print(atlas.get_fdata())
    labels = [label for label in ROIS_DICT.values()]
    logger.info('Masking...')
    masker = NiftiLabelsMasker(labels_img=atlas, labels=labels, standardize="zscore_sample", verbose=5)
    print(masker)
    logger.info('Fit transform')
    time_series = masker.fit_transform(image_bold_clean)
    #report = masker.generate_report(displayed_maps=[1, 2, 3, 4])
    #report
    logger.info('connectivity measures')
    correlation_measure = ConnectivityMeasure(kind="correlation")
    print(time_series.shape)
    correlation_matrix = correlation_measure.fit_transform([time_series])[0]
    # Plot the correlation matrix

    # Make a large figure
    # Mask the main diagonal for visualization:
    np.fill_diagonal(correlation_matrix, 0)
    # The labels we have start with the background (0), hence we skip the
    # first label
    # matrices are ordered for block-like representation
    print(labels)
    plotting.plot_matrix(
        correlation_matrix,
        figure=(10, 8),
        labels=labels[1:],
        vmax=0.8,
        vmin=-0.8,
        title="Confounds",
        reorder=True,
    )
    nilearn.plotting.show()

if __name__ == "__main__":
    main()

