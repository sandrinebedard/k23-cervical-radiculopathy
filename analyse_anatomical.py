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
import yaml

FNAME_LOG = 'log_stats.txt'

# Initialize logging
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)  # default: logging.DEBUG, logging.INFO
hdlr = logging.StreamHandler(sys.stdout)
logging.root.addHandler(hdlr)


METRICS = ['MEAN(area)', 'MEAN(diameter_AP)', 'MEAN(diameter_RL)', 'MEAN(eccentricity)',
           'MEAN(solidity)']


METRICS_TO_YLIM = {
    'MEAN(diameter_AP)': (4, 9.3),
    'MEAN(area)': (30, 95),
    'MEAN(diameter_RL)': (8.5, 14.5),
    'MEAN(eccentricity)': (0.6, 0.95),
    'MEAN(solidity)': (0.912, 0.999),
}


METRIC_TO_AXIS = {
    'MEAN(diameter_AP)': 'AP Diameter [mm]',
    'MEAN(area)': 'Cross-Sectional Area [mm²]',
    'MEAN(diameter_RL)': 'Transverse Diameter [mm]',
    'MEAN(eccentricity)': 'Eccentricity [a.u.]',
    'MEAN(solidity)': 'Solidity [%]',
}


PALETTE = {
    'sex': {'M': 'blue', 'F': 'red'},
    'group': {'HC': 'green', 'CR': 'blue'}
    }

LABELS_FONT_SIZE = 14
TICKS_FONT_SIZE = 12


def get_parser():
    parser = argparse.ArgumentParser()
    parser.add_argument("-i-folder",
                        required=True,
                        type=str,
                        help="Results folder of spinal cord preprocessing")
    parser.add_argument("-session",
                        required=True,
                        choices=['ses-baselinespinalcord','ses-followupspinalcord'],
                        default='ses-baselinespinalcord',
                        help="Session to analyse")
    parser.add_argument("-o-folder",
                        type=str,
                        required=True,
                        help="Folder to right results")
    parser.add_argument("-exclude-list",
                        required=False,
                        type=str,
                        help="Subjects to exclude form analysis")
    return parser


#def create_exclude_list():


def format_pvalue(p_value, alpha=0.001, decimal_places=3, include_space=True, include_equal=True):
    """
    Format p-value.
    If the p-value is lower than alpha, format it to "<0.001", otherwise, round it to three decimals

    :param p_value: input p-value as a float
    :param alpha: significance level
    :param decimal_places: number of decimal places the p-value will be rounded
    :param include_space: include space or not (e.g., ' = 0.06')
    :param include_equal: include equal sign ('=') to the p-value (e.g., '=0.06') or not (e.g., '0.06')
    :return: p_value: the formatted p-value (e.g., '<0.05') as a str
    """
    if include_space:
        space = ' '
    else:
        space = ''

    # If the p-value is lower than alpha, return '<alpha' (e.g., <0.001)
    if p_value < alpha:
        p_value = space + "<" + space + str(alpha)
    # If the p-value is greater than alpha, round it number of decimals specified by decimal_places
    else:
        if include_equal:
            p_value = space + '=' + space + str(round(p_value, decimal_places))
        else:
            p_value = space + str(round(p_value, decimal_places))

    return p_value


def compare_metrics_across_group(df, perlevel=False, metric_chosen=False):
    """
    Compute Wilcoxon rank-sum tests between males and females for each metric.
    """

    print("")

    for metric in METRICS:
        print(f"\n{metric}")
        
        if perlevel:
            slices_HC = df[df['group'] == 'HC'].groupby(['VertLevel'])[metric].mean()
            slices_HC_STD = df[df['group'] == 'HC'].groupby(['VertLevel'])[metric].std()
            slices_CR = df[df['group'] == 'CR'].groupby(['VertLevel'])[metric].mean()
            slices_CR_STD = df[df['group'] == 'CR'].groupby(['VertLevel'])[metric].std()
            logger.info(f'Mean {metric} for HC: {slices_HC}')
            logger.info(f'STD {metric} for HC: {slices_HC_STD}')
            logger.info(f'Mean {metric} for CR: {slices_CR}')
            logger.info(f'STD {metric} for CR: {slices_CR_STD}')
        else:

            # Get mean values for each slice
            slices_HC = df[df['group'] == 'HC'].groupby(['Slice (I->S)'])[metric].mean()
            slices_CR = df[df['group'] == 'CR'].groupby(['Slice (I->S)'])[metric].mean()

        # Run normality test
        stat, pval = stats.shapiro(slices_HC)
        print(f'Normality test HC: p-value{format_pvalue(pval)}')
        stat, pval = stats.shapiro(slices_CR)
        print(f'Normality test CR: p-value{format_pvalue(pval)}')
        # Run Wilcoxon rank-sum test (groups are independent)
        stat, pval = stats.ranksums(x=slices_HC, y=slices_CR)
        print(f'{metric}: Wilcoxon rank-sum test between HC and CR: p-value{format_pvalue(pval)}')
        if metric_chosen:
           break

def get_vert_indices(df):
    """
    Get indices of slices corresponding to mid-vertebrae
    Args:
        df (pd.dataFrame): dataframe with CSA values
    Returns:
        vert (pd.Series): vertebrae levels across slices
        ind_vert (np.array): indices of slices corresponding to the beginning of each level (=intervertebral disc)
        ind_vert_mid (np.array): indices of slices corresponding to mid-levels
    """
    # Get vert levels for one certain subject
    vert = df[df['participant_id'] == 'sub-CR001_ses-baselinespinalcord']['VertLevel']
    # Get indexes of where array changes value
    ind_vert = vert.diff()[vert.diff() != 0].index.values
    # Get the beginning of C1
    ind_vert = np.append(ind_vert, vert.index.values[-1])
    ind_vert_mid = []
    # Get indexes of mid-vertebrae
    for i in range(len(ind_vert)-1):
        ind_vert_mid.append(int(ind_vert[i:i+2].mean()))

    return vert, ind_vert, ind_vert_mid


def read_t2w_pam50(fname, suffix='_T2w_seg.nii.gz', session=None, exclude_list=None):
    data = pd.read_csv(fname)
    # Filter with session first
    data['participant_id'] = (data['Filename'].str.split('/').str[-1]).str.replace(suffix, '')
    data['session'] = data['participant_id'].str.split('_').str[-1]
    data['group'] = data['participant_id'].str.split('_').str[-2].str.split('-').str[-1].str[0:2]
    #print('Subjects', np.unique(data['participant_id'].to_list()))
    # Drop subjects with id
    if exclude_list:
        for subject in exclude_list:
            sub = (subject+'_'+ session)
            logger.info(f'dropping {sub}')
            data = data.drop(data[data['participant_id'] == sub].index, axis=0)

    return data.loc[data['session'] == session]


def get_number_subjects(df, session):

    list_subject = np.unique(df['participant_id'].to_list())
    list_session = [subject for subject in list_subject if session in subject]
    nb_subjects_session = len(list_session)
    nb_subject_CR = len([subject for subject in list_session if 'CR' in subject])
   # print([subject for subject in list_session if 'CR' in subject])

    nb_subject_HC = len([subject for subject in list_session if 'HC' in subject])
   # print([subject for subject in list_session if 'HC' in subject])
    logger.info(f'Total number of subject for {session}: {nb_subjects_session}')
    logger.info(f'With CR = {nb_subject_CR} and HC = {nb_subject_HC}')


def create_lineplot(df, hue, path_out, filename=None):
    """
    Create lineplot for individual metrics per vertebral levels.
    Note: we are ploting slices not levels to avoid averaging across levels.
    Args:
        df (pd.dataFrame): dataframe with metric values
        hue (str): column name of the dataframe to use for grouping; if None, no grouping is applied
        path_out (str): path to output directory
        show_cv (bool): if True, include coefficient of variation for each vertebral level to the plot
    """

    #mpl.rcParams['font.family'] = 'Arial'

    fig, axes = plt.subplots(1, 5, figsize=(25, 4))
    axs = axes.ravel()

    # Loop across metrics
    for index, metric in enumerate(METRICS):
        # Note: we are ploting slices not levels to avoid averaging across levels
        if hue == 'sex' or hue=='group':
            sns.lineplot(ax=axs[index], x="Slice (I->S)", y=metric, data=df, errorbar='sd', hue=hue, linewidth=2,
                         palette=PALETTE[hue])
            if index == 0:
                axs[index].legend(loc='upper right', fontsize=TICKS_FONT_SIZE)
            else:
                axs[index].get_legend().remove()
        else:
            sns.lineplot(ax=axs[index], x="Slice (I->S)", y=metric, data=df, errorbar='sd', hue=hue, linewidth=2)

        axs[index].set_ylim(METRICS_TO_YLIM[metric][0], METRICS_TO_YLIM[metric][1])
        ymin, ymax = axs[index].get_ylim()

        # Add labels
        axs[index].set_ylabel(METRIC_TO_AXIS[metric], fontsize=LABELS_FONT_SIZE)
        axs[index].set_xlabel('Axial Slice #', fontsize=LABELS_FONT_SIZE)
        # Increase xticks and yticks font size
        axs[index].tick_params(axis='both', which='major', labelsize=TICKS_FONT_SIZE)

        # Remove spines
        axs[index].spines['right'].set_visible(False)
        axs[index].spines['left'].set_visible(False)
        axs[index].spines['top'].set_visible(False)
        axs[index].spines['bottom'].set_visible(True)

        # Get indices of slices corresponding vertebral levels
        vert, ind_vert, ind_vert_mid = get_vert_indices(df)
        # Insert a vertical line for each intervertebral disc
        for idx, x in enumerate(ind_vert[1:-1]):
            axs[index].axvline(df.loc[x, 'Slice (I->S)'], color='black', linestyle='--', alpha=0.5, zorder=0)
        # Insert a text label for each vertebral level
        for idx, x in enumerate(ind_vert_mid, 0):
            # Deal with T1 label (C8 -> T1)
            if vert[x] > 7:
                level = 'T' + str(vert[x] - 7)
                axs[index].text(df.loc[ind_vert_mid[idx], 'Slice (I->S)'], ymin, level, horizontalalignment='center',
                                verticalalignment='bottom', color='black', fontsize=TICKS_FONT_SIZE)
            else:
                level = 'C' + str(vert[x])
                axs[index].text(df.loc[ind_vert_mid[idx], 'Slice (I->S)'], ymin, level, horizontalalignment='center',
                                verticalalignment='bottom', color='black', fontsize=TICKS_FONT_SIZE)

        # Invert x-axis
        axs[index].invert_xaxis()
        # Add only horizontal grid lines
        axs[index].yaxis.grid(True)
        # Move grid to background (i.e. behind other elements)
        axs[index].set_axisbelow(True)

    # Save figure
    if hue:
        filename = 'lineplot_per' + hue + '.png'
    else:
        filename = 'lineplot.png'
    path_filename = os.path.join(path_out, filename)
    plt.savefig(path_filename, dpi=300, bbox_inches='tight')
    print('Figure saved: ' + path_filename)


def main():

    args = get_parser().parse_args()
    # Get input argments
    input_folder = args.i_folder
    if args.exclude_list:
        exclude_list = args.exclude_list
    else: 
        exclude_list = None

        # Create a list with subjects to exclude if input .yml config file is passed
    if args.exclude_list is not None:
        # Check if input yml file exists
        if os.path.isfile(args.exclude_list):
            fname_yml = args.exclude_list
        else:
            sys.exit("ERROR: Input yml file {} does not exist or path is wrong.".format(args.exclude))
        with open(fname_yml, 'r') as stream:
            try:
                exclude = list(yaml.safe_load(stream))
            except yaml.YAMLError as exc:
                logger.error(exc)
    else:
        exclude = []
    print(exclude)

    session = args.session
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


    # TODO: Create an exlclude list

    # Analyse T2w perslice
    logger.info('\nAnalysing T2w CSA perslice in PAM50 anatomical dimension')
    filename = os.path.join(input_folder, "t2w_shape_PAM50.csv")
    df_t2_pam50 = read_t2w_pam50(filename, session=session, exclude_list=exclude)
    get_number_subjects(df_t2_pam50, session)

    # Keep only VertLevel from C2 to T1
    df_t2_pam50 = df_t2_pam50[df_t2_pam50['VertLevel'] <= 8]
   # df_t2_pam50 = df_t2_pam50[df_t2_pam50['VertLevel'] > 1]
    create_lineplot(df_t2_pam50, 'group', output_folder)
    compare_metrics_across_group(df_t2_pam50)

    # Load T2w perlevel
    logger.info('\nAnalysing T2w CSA perlevel')
    filename = os.path.join(input_folder, "t2w_shape_perlevel.csv")
    df_t2_perlevel = read_t2w_pam50(filename, session=session, exclude_list=exclude)
    # # Keep only VertLevel from C2 to T1
    df_t2_perlevel = df_t2_perlevel[df_t2_perlevel['VertLevel'] <= 8]
    df_t2_perlevel = df_t2_perlevel[df_t2_perlevel['VertLevel'] > 1]
    compare_metrics_across_group(df_t2_perlevel, perlevel=True)

    # Load T2star
    logger.info('\nAnalysing GM CSA')
    filename = os.path.join(input_folder, "t2star_gm_csa.csv")
    df_t2star_gm = read_t2w_pam50(filename, suffix='_T2star_gmseg.nii.gz', session=session, exclude_list=exclude)
    df_t2star_gm = df_t2_perlevel[df_t2_perlevel['VertLevel'] <= 6]  # Values chosen following the coverage 
    df_t2star_gm = df_t2_perlevel[df_t2_perlevel['VertLevel'] > 2]  # Values chosen following the coverage 
    compare_metrics_across_group(df_t2star_gm, perlevel=True, metric_chosen=True)


# Test perslice CSA

    # Analyse T2w perslice
    logger.info('\nAnalysing T2w CSA right perslice in PAM50 anatomical dimension')
    filename = os.path.join(input_folder, "t2w_shape_right_PAM50.csv")
    df_t2_pam50_right = read_t2w_pam50(filename, suffix='_T2w_seg_right.nii.gz', session=session, exclude_list=exclude)
    get_number_subjects(df_t2_pam50_right, session)

    # Keep only VertLevel from C2 to T1
    df_t2_pam50_right = df_t2_pam50_right[df_t2_pam50_right['VertLevel'] <= 8]
    compare_metrics_across_group(df_t2_pam50_right)


    # Load T2w perlevel
    logger.info('\nAnalysing T2w CSA right perlevel')
    filename = os.path.join(input_folder, "t2w_shape_right_perlevel.csv")
    df_t2_right_perlevel = read_t2w_pam50(filename, suffix='_T2w_seg_right.nii.gz', session=session, exclude_list=exclude)
    df_t2_right_perlevel = df_t2_right_perlevel[df_t2_right_perlevel['VertLevel'] <= 8]
    df_t2_right_perlevel = df_t2_right_perlevel[df_t2_right_perlevel['VertLevel'] > 1]
    compare_metrics_across_group(df_t2_right_perlevel, perlevel=True, metric_chosen=True)



if __name__ == "__main__":
    main()