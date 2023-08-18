#!/usr/bin/env python
# -*- coding: utf-8
# Create FSL physio.txt file 
#
# For usage, type: python create_FSL_physio_text_file.py -h

# File takes in the pfile.physio (fname) and then outputs text file for physiological noise correction with FSL
# Function was written and tested using FSL 5.0 and MATLAB R2015b. End of
# physiological data used as the end of the output physio file. Start of
# output file equals end - total time (TR * number_of_volumes). This way the
# physiological data from any dummy scans are not included in the output file.

# Authors: Sandrine Bédard & Kenneth Weber


import argparse
import numpy as np
import pandas as pd
from math import floor
import matplotlib.pyplot as plt


def get_parser():
    parser = argparse.ArgumentParser(
        description="Plot physio data.")
    parser.add_argument('-i', required=True, type=str,
                        help="filename for pfile.physio")
    parser.add_argument('-TR', required=True, type=float,
                        help="TR in seconds for each volume (i.e., sampling period of volumes)")
    parser.add_argument('-number-of-volumes', required=True, type=int,
                        help="Number of volumes collected")

    return parser


def plot_data(cardiac_time_data, cardiac_data, respiration_data_interp, trigger_data):

    plt.figure()
    # Cardiac data
    ax = plt.subplot(311)
    ax.plot(cardiac_time_data, cardiac_data, linewidth=0.5)
    ax.set_title('Cardiac Data', fontsize=10)
    ax.tick_params(axis='both', which='major', labelsize=7)
    ax.set_xlabel('Time (s) with 0 s = start of first volume', fontsize=7)
    ax.set_ylabel('Amplitude', fontsize=7)
    ax.set_xlim(min(cardiac_time_data), max(cardiac_time_data))
    ax.set_ylim(min(cardiac_data)-(0.10*abs(min(cardiac_data))), max(cardiac_data)+(0.10*abs(max(cardiac_data))))

    # Respiration data
    ax1 = plt.subplot(312)
    ax1.plot(cardiac_time_data, respiration_data_interp, linewidth=0.5)
    ax1.tick_params(axis='both', which='major', labelsize=7)
    ax1.set_title('Respiration Data', fontsize=10)
    ax1.set_xlabel('Time (s) with 0 s = start of first volume', fontsize=7)
    ax1.set_ylabel('Amplitude', fontsize=7)
    ax1.set_xlim(min(cardiac_time_data), max(cardiac_time_data))
    ax1.set_ylim(min(respiration_data_interp)-(0.10*abs(min(respiration_data_interp))), max(respiration_data_interp)+(0.10*abs(max(respiration_data_interp))))

    # Trigger data
    ax2 = plt.subplot(313)
    ax2.plot(cardiac_time_data, trigger_data, linewidth=0.5)
    ax2.set_title('Scanner Triggers', fontsize=10)
    ax2.tick_params(axis='both', which='major', labelsize=7)
    ax2.set_xlabel('Time (s) with 0 s = start of first volume', fontsize=7)
    ax2.set_ylabel('Amplitude', fontsize=7)
    ax2.set_xlim(min(cardiac_time_data), max(cardiac_time_data))
    ax2.set_ylim(min(trigger_data)-(0.10*abs(min(trigger_data))), max(trigger_data)+(0.10*abs(max(trigger_data))))
    plt.tight_layout()
    plt.savefig('physio.png', dpi=600, bbox_inches="tight")


def main():
    parser = get_parser()
    args = parser.parse_args()
    TR = args.TR
    number_of_volumes = args.number_of_volumes
    fname = args.i

    # Initialize variables
    respiration_sampling_rate = 25  # In Hz
    cardiac_sampling_rate = 100  # In Hz
    trigger_width = TR * 0.2  # Width of trigger pulse in seconds
    total_time = (TR * number_of_volumes)

    # Read data
    df_input = pd.read_csv(fname, sep="\t", header=None)
    data = np.array(df_input[0].to_list())
   
    # Create cardiac data
    cardiac_start = np.where(data == -8888)[0][0] + 1
    cardiac_data = data[cardiac_start::]
    cardiac_time_data = np.arange((0-((len(cardiac_data)/cardiac_sampling_rate) - (total_time))), total_time + 1/cardiac_sampling_rate, 1/cardiac_sampling_rate)
    cardiac_time_data = cardiac_time_data[1::]

    # Create respiratory data
    respiration_start = np.where(data == -9999)[0][0] + 1
    respiration_end = np.where(data == -8888)[0][0] - 1
    if np.abs(respiration_start - respiration_end) <= 1:
        print('No respiration data provided. Exiting')  # create with cardiac , check for pnm if no respiratory data
        respiration_data_interp = np.zeros(len(cardiac_time_data))
    else:
        respiration_data = data[respiration_start:respiration_end+1]
        respiration_time_data = np.arange((0-((len(respiration_data)/respiration_sampling_rate)-(total_time))), total_time + 1/respiration_sampling_rate, 1/respiration_sampling_rate)
        respiration_time_data = respiration_time_data[1::]  # remove first element

        respiration_data_interp = np.interp(cardiac_time_data, respiration_time_data, respiration_data)  # Interpolate respiration data

    # Create trigger data
    data_collection_start = np.where((cardiac_time_data**2 - min(cardiac_time_data**2)) == 0)[0][0] # Ran into problems finding 0 cardiac_time_data index in some cases.
    trigger_starts = np.arange(0, total_time, TR)
    trigger_data = np.zeros(np.shape(cardiac_time_data))
    for trigger in trigger_starts:
        trigger_data[floor((data_collection_start+(trigger*cardiac_sampling_rate))):floor((data_collection_start+(trigger+trigger_width)*cardiac_sampling_rate))+1] = 1

    # Create Graph
    #plot_data(cardiac_time_data, cardiac_data, respiration_data_interp, trigger_data)

    respiration_data_interp = np.zeros(len(cardiac_time_data))
    # Save into txt file
    columns_df = ['Time', 'Respiratory Data', 'Scanner Triggers', 'Cardiac Data']
    df_final = pd.DataFrame(columns=columns_df)
    df_final['Time'] = cardiac_time_data
    df_final['Respiratory Data'] = respiration_data_interp
    df_final['Scanner Triggers'] = trigger_data
    df_final['Cardiac Data'] = cardiac_data

    df_final.to_csv(fname.split('.')[0]+'.txt', index=False, header=False, sep="\t")


if __name__ == '__main__':
    main()
