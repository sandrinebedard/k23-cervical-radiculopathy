#!/usr/bin/env python
# -*- coding: utf-8

# Analyse resting state functional connectivity in subject's space for all subjects

# Author: Sandrine Bédard

import os
import logging
import argparse
import sys
import numpy as np
import nibabel as nib
import pandas as pd
import matplotlib.pyplot as plt
import yaml
import seaborn as sns
from statsmodels.stats.multitest import fdrcorrection
import scipy.stats as stats

FNAME_LOG = 'log_stats.txt'

# Initialize logging
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)  # default: logging.DEBUG, logging.INFO
hdlr = logging.StreamHandler(sys.stdout)
logging.root.addHandler(hdlr)


def get_parser():
    parser = argparse.ArgumentParser(description="Create correlation matrix for one subject")
    parser.add_argument("-i-folder",
                        required=True,
                        type=str,
                        help="Input path with connectivity matrix")
    parser.add_argument("-exclude",
                        required=False,
                        type=str,
                        help="exclude.yml")

    parser.add_argument("-template",
                        action='store_true')
    return parser


def read_csv(path_results, template, exclude):
    list_corr_HC = []
    list_corr_CR = []
    list_files = [file for file in os.listdir(path_results) if '.csv' in file]
    # Get correlation matrix either in template or native space
    if template:
        list_files = [file for file in list_files if 'template' in file]
        print('hello')
    else:
        list_files = [file for file in list_files if 'template' not in file]
    # Remove subject from exlcude list

    # Split HC and CR
    list_HC = [file for file in list_files if 'HC' in file]
    list_CR = [file for file in list_files if 'CR' in file]
    for file in list_HC:
        subject = file.split('_')[0]
        if subject not in exclude:
            df = pd.read_csv(os.path.join(path_results, file), header=None)
            # Apply Fisher transform
            df_F = df.apply(np.arctanh, axis=0)
            list_corr_HC.append(df_F)
    for file in list_CR:
        subject = file.split('_')[0]
        if subject not in exclude:
            df = pd.read_csv(os.path.join(path_results, file), header=None)
            # Apply Fisher transform
            df_F = df.apply(np.arctanh, axis=0)
            list_corr_CR.append(df_F)
    df_corr_HC = pd.concat(list_corr_HC)
    df_corr_CR = pd.concat(list_corr_CR)

    return df_corr_HC, df_corr_CR


LABELS = ['LV_5', 'RV_5', 'LD_5', 'RD_5',
          'LV_6', 'RV_6', 'LD_6', 'RD_6',
          'LV_7', 'RV_7', 'LD_7', 'RD_7']


def generate_corr_plot(df_mean, group, vmin=-0.02, vmax=0.06):
    sns.set_theme(style="white")
    plt.figure()
    # find the largest number in mean while discounting Inf, useful for plot colourbars later on
    print(np.nanmax(df_mean[df_mean != np.inf]))
    # find the smallest number in mean while discounting -Inf, useful for plot colourbars later on
    print(np.nanmin(df_mean[df_mean != -np.inf]))

    mask = np.triu(np.ones_like(df_mean, dtype=bool))
    # draw a heatmap with the mask and correct aspect ratio

    sns.heatmap(df_mean, mask=mask, cmap=sns.diverging_palette(220, 20, as_cmap=True), vmax=vmax, vmin=vmin, center=0.0,
                square=True, linewidths=.5, xticklabels=LABELS, yticklabels=LABELS, cbar_kws={"shrink": .6, "label": "Z-transformed Pearson R"}, fmt='').set(xlabel="Seed Region", ylabel="Seed Region")
    plt.title(f'Connecivity {group}')
    plt.yticks(rotation=0)
    plt.xticks(rotation=90)
 

def compute_t_test(df):
    # TODO: change to have one subject per row and column = connection
    t_list_A = []
    p_list_A = []

    # run a one-sample t-test for each connection
    for index, row in df.iterrows():
        t_test_A = stats.ttest_1samp(row, 0)

        t_list_A.append(t_test_A[0])
        p_list_A.append(t_test_A[1])

    df_t_A = pd.DataFrame(data=t_list_A, index = df.index, columns = ["t"])
    df_p_A = pd.DataFrame(data=p_list_A, index = df.index, columns = ["p"])

    # use FDR to correct for multiple comparisons
    p_list_fdr_A = fdrcorrection(p_list_A, alpha = 0.05)

    df_true_false_A = pd.DataFrame(data=p_list_fdr_A[0], index=df_p_A.index, columns=["TrueFalse"])
    df_fdr_A = pd.DataFrame(data=p_list_fdr_A[1], index=df_p_A.index, columns=["fdr"])

    matrix_fdr_A = df_fdr_A.unstack(level = -1)
    print(matrix_fdr_A)


def main():
    args = get_parser().parse_args()
    # Get input argments
    path_results = args.i_folder
    template = args.template

    # Create a list with subjects to exclude if input .yml config file is passed
    if args.exclude is not None:
        # Check if input yml file exists
        if os.path.isfile(args.exclude):
            fname_yml = args.exclude
        else:
            sys.exit("ERROR: Input yml file {} does not exist or path is wrong.".format(args.exclude))
        with open(fname_yml, 'r') as stream:
            try:
                exclude = list(yaml.safe_load(stream))
            except yaml.YAMLError as exc:
                logger.error(exc)
    else:
        exclude = []
    #print(exclude)
    df_HC, df_CR = read_csv(path_results, template, exclude)
    df_HC_row = df_HC.groupby(df_HC.index)
    df_HC_mean = df_HC_row.mean()  # calculate mean across subjects for each connection
    # Get p-value
    compute_t_test(df_HC_row)
    generate_corr_plot(df_HC_mean, group='HC')
    df_CR_row = df_CR.groupby(df_CR.index)
    df_CR_mean = df_CR_row.mean()  # calculate mean across subjects for each connection
    print(df_CR_mean)
    generate_corr_plot(df_CR_mean, group='CR')
    plt.show()

if __name__ == "__main__":
    main()
