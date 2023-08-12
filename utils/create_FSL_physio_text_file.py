#!/usr/bin/env python
# -*- coding: utf-8
# Plot physio 
#
# For usage, type: python create+FSL_physio_text_file.py -h

#File takes in the pfile.physio (fname) and then outputs text file for physiological noise correction with FSL
#Function was written and tested using FSL 5.0 and MATLAB R2015b. End of
#physiological data used as the end of the output physio file. Start of
#output file equals end - total time (TR * number_of_volumes). This way the
#physiological data from any dummy scans are not included in the output
#file.

# Authors: Sandrine Bédard


import argparse
import numpy as np
import pandas as pd
from scipy.interpolate import interp1d


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


def main():
    parser = get_parser()
    args = parser.parse_args()
    TR = args.TR
    number_of_volumes = args.number_of_volumes
    fname = args.i

    # Initialize variables
    respiration_sampling_rate = 25 # In Hz
    cardiac_sampling_rate = 100 # In Hz
    trigger_width = TR*0.2 # Width of trigger pulse in seconds
    total_time = (TR * number_of_volumes)
    print('total time:', total_time)


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
    respiration_end = np.where(data == -8888)[0][0] -1
    respiration_data = data[respiration_start:respiration_end+1]
    respiration_time_data = np.arange((0-((len(respiration_data)/respiration_sampling_rate)-(total_time))), total_time + 1/respiration_sampling_rate, 1/respiration_sampling_rate)
    respiration_time_data = respiration_time_data[1::]
    #respiration_data_interp = interp1(respiration_time_data,respiration_data,cardiac_time_data,'spline'); %Interpolate respiration data to match total_time data sampling rate
   # f = interpolate.interp1d(respiration_time_data, cardiac_time_data)
    
    respiration_data_interp = np.interp(cardiac_time_data, respiration_time_data, respiration_data)
    print(respiration_data_interp)

    #data_collection_start = 
# data_collection_start = find(((cardiac_time_data.^2)-min(cardiac_time_data.^2)) == 0); %Ran into problems finding 0 cardiac_time_data index in some cases.
#trigger_starts = (0:TR:total_time-TR);
#trigger_data = zeros(size(cardiac_time_data));
#for i=1:length(trigger_starts)
#    trigger_data(floor((data_collection_start+(trigger_starts(i)*cardiac_sampling_rate)+1)):floor((data_collection_start+(trigger_starts(i)+trigger_width)*cardiac_sampling_rate))) = 1;
#end


if __name__ == '__main__':
    main()
