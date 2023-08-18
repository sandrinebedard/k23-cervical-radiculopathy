#!/usr/bin/env python
# -*- coding: utf-8
# Create FSL physio.txt file
#
# For usage, type: python create_FSL_physio_text_file.py -h


# Authors: Sandrine Bédard 


import argparse
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from matplotlib.backend_bases import PickEvent
from scipy.signal import butter, lfilter, find_peaks



def get_parser():
    parser = argparse.ArgumentParser(
        description="Peak detection for cardiac and respiratory data with GUI to add or remove peaks")  # Maybe in GE format and call, or add a flag
    parser.add_argument('-i', required=True, type=str,
                        help="filename for pfile.physio")
    parser.add_argument('-exclude-resp', action='store_true',
                        help="To put 0 values in respiratory data")

    return parser



def create_gui(idx_peaks , peak_values, data_filt, time, data_name):
    # Initialize data
    data = {'x': list(time[idx_peaks]), 'y': list(peak_values)}
    # Create a scatter plot
    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(20,10))
    ax1.set_title(f'{data_name} data filtered with bandpass with peak detection \n Click on middle click to add points and right click to remove')
   # plt.subplot(111)
    ax1.plot(time, data_filt)
    scatter, = ax1.plot(data['x'], data['y'], marker="o", linestyle="", picker=True)
    ax1.set_xlabel('Time')
    ax1.set_ylim(0, max(data_filt)*1.5)
    ax1.set_xlim(min(time) - 5, max(time) + 5)

    # Function to add data points
    # TODO check add to select closest time to peak
    def onpick(event: PickEvent):
            x, y = event.xdata, event.ydata
            if event.button == 2:  # Middle click to add a point
                # Find correct x data
                closest_x = min(time, key=lambda x_time: abs(x_time - x))
                print(f'Adding data x = {closest_x}, y = {y}')
                data['x'].append(closest_x)
                data['y'].append(y)
            # Update the scatter plot
            scatter.set_data(data['x'], data['y'])
            plt.draw()

    # Function to remove data point
    def onpick_remove(event: PickEvent):
         # Check if the event is on a scatter point
        if event.artist == scatter:
            ind = event.ind[0]  # Get the index of the clicked point
            if event.mouseevent.button == 3:  # Right-click to remove point
                if ind < len(data['x']):
                    del data['x'][ind]
                    del data['y'][ind]
                    print('Removing data x = {}, y = {}'.format(data['x'][ind], data['y'][ind]))
                    print(len(data['x']))
            # Update the scatter plot
            scatter.set_data(data['x'], data['y'])
            plt.draw()


    # Connect the pick event handler
    fig.canvas.mpl_connect('pick_event', onpick_remove)
    fig.canvas.mpl_connect('button_press_event', onpick)
    
    # Plot peak diff
    ax2 = plt.subplot(212)
    ax2.set_xlabel('Time (s)')
    ax2.set_xlim(min(time) - 5, max(time) + 5)

    peak_diff = np.diff(idx_peaks)
    ax2.set_title('Difference between peaks')
    ax2.plot(time[idx_peaks][1::], peak_diff)
    plt.show()
    return data['x']


def main():

    parser = get_parser()
    args = parser.parse_args()
    fname = args.i
    columns = ['Time', 'Respiratory data', 'Scanner Triggers', 'Cardiac Data']
    df_physio = pd.read_csv(fname, sep="\t", header=None)

    # fetch cardiac data and time
    data_cardiac = np.array(df_physio[3].to_list())
    time = np.array(df_physio[0].to_list())

    # Bandpass data cardio
    fcutlow = 0.5   # low cut frequency in Hz
    fcuthigh = 2   # high cut frequency in Hz
    b_filt, a_filt = butter(1, [fcutlow/(100/2), fcuthigh/(100/2)], 'bandpass')
    data_cardiac_bd = lfilter(b_filt, a_filt, data_cardiac)

    # Select a minimum peak distance 
    min_peak_dist = 68
    #min_peak_dist = 80

    # Find peak indexes
    idx_peaks = find_peaks(data_cardiac_bd, distance=min_peak_dist)[0]
    peaks_values = data_cardiac_bd[idx_peaks]

    # Creat GUI graph to validate peaks
    updated_time = create_gui(idx_peaks, peaks_values, data_cardiac_bd, time, 'Cardiac')

    # Save data time points of cardiac peaks
    data_peaks = pd.DataFrame()
    data_peaks['peak_card']= updated_time  #time[idx_peaks]
    data_peaks.to_csv('physio_card.txt', index=False, header=False, sep="\t")

    # Do the same thing for respiratory data
    if not args.exclude_resp:
        data_resp= np.array(df_physio[1].to_list())
        # Bandpass data resp
        fcutlow = 0.5   # low cut frequency in Hz
        fcuthigh = 2   # high cut frequency in Hz
        b_filt, a_filt = butter(1, [fcutlow/(100/2), fcuthigh/(100/2)], 'bandpass')
        data_resp_bd = lfilter(b_filt, a_filt, data_resp)
        # Select a minimum peak distance
        min_peak_dist = 300
    
        data_resp_bd = data_resp # To remove if want filter
        idx_peaks_resp = find_peaks(data_resp_bd, distance=min_peak_dist)[0]
        peaks_values_resp = data_resp_bd[idx_peaks_resp]

        # Creat GUI graph to validate peaks
        updated_time_resp = create_gui(idx_peaks_resp, peaks_values_resp, data_resp_bd, time, 'Respiratory')

        # Save data time points of cardiac peaks
       # data_peaks = pd.DataFrame()
       # data_peaks['peak_resp']= updated_time_resp  #time[idx_peaks]
       # data_peaks.to_csv('physio_resp.txt', index=False, header=False, sep="\t")
    else:
         print('Creating ')




if __name__ == '__main__':
    main()
