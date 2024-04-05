#!/usr/bin/env python
# -*- coding: utf-8
# Plot physio 
#
# For usage, type: python plot_physio.py -h

# Authors: Sandrine Bédard

import argparse
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt


def get_parser():
    parser = argparse.ArgumentParser(
        description="Plot physio data.")
    parser.add_argument('-i', required=True, type=str,
                        help="Input .txt file.")
    parser.add_argument('-o', required=True, type=str,
                        help="Ouput image.")

    return parser


def main():
    parser = get_parser()
    args = parser.parse_args()
    columns = ['Time', 'Respiratory Data', 'Scanner Triggers', 'Cardiac Data']
    physio_df = pd.read_csv(args.i, sep="\t", header=None, names=columns)
    print(physio_df)

    # Respiratory
    plt.figure(figsize=(50,4))
    ax = plt.subplot(111)
    ax.plot(physio_df['Time'], physio_df['Respiratory Data'], label='Respiratory Data')
    ax.autoscale()
    ax.set_xlim(-35, 750)
    plt.xticks(range(-50, 750, 25))
    ax.legend(loc='center left', bbox_to_anchor=(1, 0.5))
    box = ax.get_position()
    ax.set_position([box.x0, box.y0 + box.height * 0.1,
                    box.width, box.height * 0.9])
    plt.savefig(args.o, dpi=300)  # bbox_inches="tight"
    
    # cardiac
    plt.figure(figsize=(75,4))
    ax = plt.subplot(111)
    ax.plot(physio_df['Time'], physio_df['Cardiac Data'], label='Cardiac Data')
    ax.autoscale()
    plt.xticks(range(-30, 750, 25))
    ax.set_xlim(-35, 750)
    ax.legend(loc='center left', bbox_to_anchor=(1, 0.5))
    box = ax.get_position()
    ax.set_position([box.x0, box.y0 + box.height * 0.1,
                    box.width, box.height * 0.9])
    plt.savefig('cardiac.png', dpi=300)  # bbox_inches="tight"




if __name__ == '__main__':
    main()
