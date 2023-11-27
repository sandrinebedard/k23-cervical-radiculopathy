#!/usr/bin/env python
# -*- coding: utf-8

# Analyse resting state functional connectivity in subject's space for all subjects

# Author: Sandrine Bédard
# TODO: create a log file with input name

# Example of command:
# python analyse_rs_all.py -i-folder /mnt/p/Mackeylab/Individual_Folders/Sandrine/func_analysis_2023-10-13-thr05-v2/results/ -path-out /mnt/c/Users/sb199/Projet3_data/k23_cervical_radiculopathy/func_results_all_2023-10-17-thr05-template -exclude /mnt/c/Users/sb199/k23-cervical-radiculopathy/exclude.yml -template

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
    parser.add_argument("-path-out",
                        required=True,
                        type=str,
                        help="Path to save results")
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
            df = pd.read_csv(os.path.join(path_results, file), header=None, names=LABELS)
            # Apply Fisher transform
            df_F = df.apply(np.arctanh, axis=0)
            list_corr_HC.append(df_F)
    for file in list_CR:
        subject = file.split('_')[0]
        if subject not in exclude:
            df = pd.read_csv(os.path.join(path_results, file), header=None, names=LABELS)
            # Apply Fisher transform
            df_F = df.apply(np.arctanh, axis=0)
            list_corr_CR.append(df_F)
    df_corr_HC = pd.concat(list_corr_HC)
    df_corr_CR = pd.concat(list_corr_CR)

    return df_corr_HC, df_corr_CR  # TODO : to check df_corr_HC.abs(), df_corr_CR.abs() 


LABELS = ['LV_5', 'RV_5', 'LD_5', 'RD_5',
          'LV_6', 'RV_6', 'LD_6', 'RD_6',
          'LV_7', 'RV_7', 'LD_7', 'RD_7']


LABELS_grouped = ['LV', 'RV', 'LD', 'RD']


def generate_corr_plot(df_mean, group, labels,  vmin=None, vmax=None, fname=None):  # vmin=-0.02, vmax=0.06
    sns.set_theme(style="white")
    plt.figure(figsize=(10,7))
    # find the largest number in mean while discounting Inf, useful for plot colourbars later on
    print(np.nanmax(df_mean[df_mean != np.inf]))
    # find the smallest number in mean while discounting -Inf, useful for plot colourbars later on
    print(np.nanmin(df_mean[df_mean != -np.inf]))

    mask = np.triu(np.ones_like(df_mean, dtype=bool))
    # draw a heatmap with the mask and correct aspect ratio
    sns.heatmap(df_mean, mask=mask, cmap=sns.diverging_palette(220, 20, as_cmap=True), vmax=vmax, vmin=vmin, center=0.0,
                square=True, linewidths=.5, xticklabels=labels, yticklabels=labels, 
                annot=True, fmt=".2f",
                cbar_kws={"shrink": .6, "label": "Z-transformed Pearson R"}).set(xlabel="Seed Region", ylabel="Seed Region")
    plt.title(f'Connectivity {group}')
    plt.yticks(rotation=0)
    plt.xticks(rotation=90)
    plt.savefig(fname+ '.png',dpi=300,)

 

def compute_t_test(df):
    # TODO: change to have one subject per row and column = connection
    t_list_A = []
    p_list_A = []
    print(df)
    data_split =np.dstack(np.vsplit(df.to_numpy(),23)) # TODO remove hard code
    print(data_split.shape)
    # run a one-sample t-test for each connection
    # for index, row in df.iterrows():
    #     t_test_A = stats.ttest_1samp(row, 0)

    #     t_list_A.append(t_test_A[0])
    #     p_list_A.append(t_test_A[1])

    # df_t_A = pd.DataFrame(data=t_list_A, index = df.index, columns = ["t"])
    # df_p_A = pd.DataFrame(data=p_list_A, index = df.index, columns = ["p"])

    # # use FDR to correct for multiple comparisons
    # p_list_fdr_A = fdrcorrection(p_list_A, alpha = 0.05)

    # df_true_false_A = pd.DataFrame(data=p_list_fdr_A[0], index=df_p_A.index, columns=["TrueFalse"])
    # df_fdr_A = pd.DataFrame(data=p_list_fdr_A[1], index=df_p_A.index, columns=["fdr"])

    # matrix_fdr_A = df_fdr_A.unstack(level = -1)
    #print(matrix_fdr_A)


def main():
    args = get_parser().parse_args()
    # Get input argments
    path_results = args.i_folder
    template = args.template
    output_folder = args.path_out
    # Create output folder if does not exist.
    if not os.path.exists(output_folder):
        os.mkdir(output_folder)
    os.chdir(output_folder)

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

    # FOR HC
    ##########################
   # print(df_HC)  # TODO: save in csv file
    # Get p-value
    compute_t_test(df_HC)
    df_HC_row = df_HC.groupby(df_HC.index)
    df_HC_mean = df_HC_row.mean()  # calculate mean across subjects for each connection
    print(df_HC_mean)
    np.savetxt('corr_matrix_all_HC_perlevel.csv', df_HC_mean, delimiter=",")

    # Compute mean across all levels
    df_HC_mean_levels = pd.DataFrame()
    df_HC_mean_levels['LV'] = df_HC_mean[['LV_5', 'LV_6', 'LV_7']].mean(axis=1) #.iloc[[0,4,8]]
    df_HC_mean_levels['RV'] = df_HC_mean[['RV_5', 'RV_6', 'RV_7']].mean(axis=1)#.iloc[[1,5,9]]
    df_HC_mean_levels['RD'] = df_HC_mean[['RD_5', 'RD_6', 'RD_7']].mean(axis=1) #.iloc[[2,6,10]]
    df_HC_mean_levels['LD'] = df_HC_mean[['LD_5', 'LD_6', 'LD_7']].mean(axis=1)#.iloc[[3,7,11]]
    df_HC_mean_levels.iloc[[0]] = df_HC_mean_levels.iloc[[0,4,8]].mean()
    df_HC_mean_levels.iloc[[1]] = df_HC_mean_levels.iloc[[1,5,9]].mean()
    df_HC_mean_levels.iloc[[2]] = df_HC_mean_levels.iloc[[2,6,10]].mean()
    df_HC_mean_levels.iloc[[3]] = df_HC_mean_levels.iloc[[3,7,11]].mean()
    df_HC_mean_levels = df_HC_mean_levels[0:4]
    #df_HC_mean_levels_combined = df_HC_mean_levels.groupby(df_HC_mean_levels.index).mean()
    print(df_HC_mean_levels)
    np.savetxt('corr_matrix_all_HC.csv', df_HC_mean_levels, delimiter=",")


    # Corr plot for seperate level
    generate_corr_plot(df_HC_mean, group='HC', labels=LABELS, vmax=0.3, vmin=0, fname='corr_plot_all_HC_perlevel')
    generate_corr_plot(df_HC_mean_levels, group='HC - MEAN', labels=LABELS_grouped, vmin=0, vmax=0.2, fname='corr_plot_all_HC')

   # generate_corr_plot(df_HC_mean_levels, group='HC - MEAN', labels=LABELS_grouped)


    # FOR CR PATIENTS
    ################################
    print('\n CR PATIENTS')
    df_CR_row = df_CR.groupby(df_CR.index)
    df_CR_mean = df_CR_row.mean()  # calculate mean across subjects for each connection
    print(df_CR_mean)  # TODO: save in csv file
    np.savetxt('corr_matrix_all_CR_perlevel.csv', df_CR_mean, delimiter=",")

    generate_corr_plot(df_CR_mean, group='CR', labels=LABELS, vmax=0.3, vmin=0, fname='corr_plot_all_CR_perlevel')

    df_CR_mean_levels = pd.DataFrame()
    df_CR_mean_levels['LV'] = df_CR_mean[['LV_5', 'LV_6', 'LV_7']].mean(axis=1) #.iloc[[0,4,8]]
    df_CR_mean_levels['RV'] = df_CR_mean[['RV_5', 'RV_6', 'RV_7']].mean(axis=1)#.iloc[[1,5,9]]
    df_CR_mean_levels['RD'] = df_CR_mean[['RD_5', 'RD_6', 'RD_7']].mean(axis=1) #.iloc[[2,6,10]]
    df_CR_mean_levels['LD'] = df_HC_mean[['LD_5', 'LD_6', 'LD_7']].mean(axis=1)#.iloc[[3,7,11]]
    df_CR_mean_levels.iloc[[0]] = df_CR_mean_levels.iloc[[0,4,8]].mean()
    df_CR_mean_levels.iloc[[1]] = df_CR_mean_levels.iloc[[1,5,9]].mean()
    df_CR_mean_levels.iloc[[2]] = df_CR_mean_levels.iloc[[2,6,10]].mean()
    df_CR_mean_levels.iloc[[3]] = df_CR_mean_levels.iloc[[3,7,11]].mean()
    df_CR_mean_levels = df_CR_mean_levels[0:4]
    #df_HC_mean_levels_combined = df_HC_mean_levels.groupby(df_HC_mean_levels.index).mean()
    print(df_CR_mean_levels)
    np.savetxt('corr_matrix_all_CR.csv', df_CR_mean_levels, delimiter=",")

    generate_corr_plot(df_CR_mean_levels, group='CR - MEAN', labels=LABELS_grouped, vmin=0, vmax=0.2, fname='corr_plot_all_CR')



    plt.show()

if __name__ == "__main__":
    main()
