#!/usr/bin/env python
# -*- coding: utf-8

# Convert data to template for 

# Author: Sandrine Bédard

import os
import logging
import shutil
import argparse


def get_parser():
    parser = argparse.ArgumentParser()
    parser.add_argument("-path-data",
                        required=True,
                        type=str,
                        help="Path to data_processed")
    parser.add_argument("-path-derivatives",
                        type=str,
                        required=True,
                        help="Folder to derivatives results")

    parser.add_argument("-path-out",
                        type=str,
                        required=True,
                        help="Folder to right results")

    return parser

# TODO:
# - Look at Jan's script to create participants.tsv and etc...
# - Validate dataset name

def main():
    args = get_parser().parse_args()

    path_data = args.path_data
    path_out = args.path_out
    
    DATASET_NAME = 'stanford_rest'
    DATASET_NAME_SHORT = 'stfrdR'
    # Create output folder
    if not os.path.exists(path_out):
        os.mkdir(path_out)
    # Create derivatives
    path_derivatives_out = os.path.join(path_out, 'derivatives')
    if not os.path.exists(path_derivatives_out):
        os.makedirs(path_derivatives_out)
    path_derivatives_out_labels = os.path.join(path_derivatives_out, 'label')
    path_derivatives_out_moco = os.path.join(path_derivatives_out, 'moco')
    if not os.path.exists(path_derivatives_out_labels):
        os.makedirs(path_derivatives_out_labels)
    if not os.path.exists(path_derivatives_out_moco):
        os.makedirs(path_derivatives_out_moco)

    for subject in os.listdir(path_data):
        if "sub" in subject:
            subject_path = os.path.join(path_data, subject)
            # Get subject number
            suffix = subject.split('-')[1]
            fname_old_bold_moco_image = os.path.join(subject_path, 'ses-baselinespinalcord', 'func', subject + '_ses-baselinespinalcord_task-rest_bold_mc2.nii.gz')
            print(fname_old_bold_moco_image)
            fname_old_bold_moco_json = os.path.join(subject_path, 'ses-baselinespinalcord', 'func', subject + '_ses-baselinespinalcord_task-rest_bold.json')
            fname_old_bold_moco_mean = os.path.join(subject_path, 'ses-baselinespinalcord', 'func', subject + '_ses-baselinespinalcord_task-rest_bold_mean.nii.gz')
            # TODO change for derivatives folder instead!!!
            fname_old_bold_moco_mean_seg = os.path.join(subject_path, 'ses-baselinespinalcord', 'func', subject + '_ses-baselinespinalcord_task-rest_bold_mean_seg.nii.gz')
            
            # Create new subject name
            subject_new = 'sub-' + DATASET_NAME + suffix
            print('New suject:', subject_new)
            path_out_subject_labels = os.path.join(path_derivatives_out_labels, subject_new, 'func')
            if not os.path.exists(path_out_subject_labels):
                os.makedirs(path_out_subject_labels)
            path_out_subject_moco = os.path.join(path_derivatives_out_moco, subject_new, 'func')
            if not os.path.exists(path_out_subject_moco):
                os.makedirs(path_out_subject_moco)
            fname_new_bold_moco_image = os.path.join(path_out_subject_moco, subject_new + '_task-rest_desc-moco_bold.nii.gz')
            shutil.copyfile(fname_old_bold_moco_image, fname_new_bold_moco_image)
            fname_new_bold_moco_json = os.path.join(path_out_subject_moco, subject_new + '_task-rest_desc-moco_bold.json')
            shutil.copyfile(fname_old_bold_moco_json, fname_new_bold_moco_json)
            fname_new_bold_moco_mean = os.path.join(path_out_subject_moco, subject_new + '_task-rest_desc-mocomean_bold.nii.gz')
            shutil.copyfile(fname_old_bold_moco_mean, fname_new_bold_moco_mean)
            fname_new_bold_moco_mean_seg = os.path.join(path_out_subject_labels, subject_new + '_task-rest_desc-desc-spinalcord_mask.nii.gz')
            shutil.copyfile(fname_old_bold_moco_mean_seg, fname_new_bold_moco_mean_seg)


if __name__ == "__main__":
    main()