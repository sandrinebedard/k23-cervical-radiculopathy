#!/usr/bin/env python
#
# Script to create a json sidecar for derivatives
#
# For usage, type: python create_json.py -h
#
# Authors: Sandrine Bédard


import json
import argparse
import time


def get_parser():
    parser = argparse.ArgumentParser(
        description="Create json sidecar.") 
    parser.add_argument('-fname', required=True, type=str,
                        help="filename of output json sidecar")
    parser.add_argument('-name-rater', required=True, type=str,
                        help="name of rater to put in json sidecar")
    return parser


def create_json(fname_json, name_rater):
    """
    Create json sidecar with meta information
    :param fname_nifti: str: File name of the nifti image to associate with the json sidecar
    :param name_rater: str: Name of the expert rater
    :return:
    """
    metadata = {'Author': name_rater, 'Date': time.strftime('%Y-%m-%d %H:%M:%S')}
    with open(fname_json, 'w') as outfile:
        json.dump(metadata, outfile, indent=4)
    print(f'Creating {fname_json}')


def main():

    parser = get_parser()
    args = parser.parse_args()
    create_json(args.fname, args.name_rater)


if __name__ == '__main__':
    main()
