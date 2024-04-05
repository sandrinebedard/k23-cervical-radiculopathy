#!/usr/bin/env python
# -*- coding: utf-8
# Get min and max complete vertebral levels from labeled segmentation
#
# For usage, type: python get_vertebral_coverage -h

# Authors: Sandrine Bédard

import argparse
import csv
import numpy as np
import nibabel as nib
import os


def get_parser():
    parser = argparse.ArgumentParser(
        description="Get the minimum and maximum vertebral level from labeld segmentation and output .csv file.")
    parser.add_argument('-vertfile', required=True, type=str,
                        help="Labeled segmentation .nii.gz file")
    parser.add_argument('-subject', required=True, type=str,
                        help="Subject ID")
    parser.add_argument('-o', required=False, type=str,
                        default='vertebral_coverage.csv',
                        help="Output csv filename.")

    return parser


def main():
    parser = get_parser()
    args = parser.parse_args()

    vertfile = nib.load(args.vertfile)
    subject = args.subject
    fname_out = args.o

    max_complete_level = np.max(vertfile.get_fdata())
    print('Maximum level', max_complete_level)
    min_complete_level = np.min(vertfile.get_fdata()[vertfile.get_fdata()>0])
    print('Minimum level', min_complete_level)
    if not os.path.isfile(fname_out):
        with open(fname_out, 'w') as csvfile:
            header = ['Subject', 'Min VertLevel', 'Max VertLevel']
            writer = csv.DictWriter(csvfile, fieldnames=header)
            writer.writeheader()
    with open(fname_out, 'a') as csvfile:
        spamwriter = csv.writer(csvfile, delimiter=',')
        line = [subject, min_complete_level, max_complete_level]
        spamwriter.writerow(line)


if __name__ == '__main__':
    main()
