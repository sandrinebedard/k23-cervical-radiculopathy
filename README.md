# k23-cervical-radiculopathy
Analysis pipeline on Cervical Radiculopathy MRI project

## Table of content
* [1.Dependencies](#1dependencies)
* [2.Dataset](#2dataset)
* [3.Analysis pipeline](#3analysis-pipeline)
    * [3.1.Installation](#31installation)
    * [3.2.Spinal cord preprocessing](#32spinal-cord-preprocessing)
    * [3.3.Quality control and Manual correction](#33quality-control-and-manual-correction)
        * [3.3.1.Correct vertebral labeling](#331correct-vertebral-labeling)
## 1.Dependencies

* SCT v6.0
* FSL 6.0
* Python 3.8.12

## 2.Dataset
`MACKEYLAB\Mackeylab\PROJECTS\K23_Cervical_Radiculopathy\data\BIDS\sourcedata`
 
## 3.Analysis pipeline

### 3.1.Installation

1. Create python environement
~~~
conda create --name venv-cr python==3.8.12
~~~
2. Activate environement
~~~
conda activate venv-cr
~~~
3. Install requirements
~~~
pip install -r requirements.txt
~~~

### 3.2.Spinal cord preprocessing

Launch preprocessing:

~~~
sct_run_batch -path-data <k23_cervical_radiculopathy/data/sourcedata/> -jobs 2 -path-output <PATH_OUT> -script preprocess_data_spinalcord.sh
~~~


Example of command:

~~~
sct_run_batch -path-data /home/sbedard/mackeylab/PROJECTS/K23_Cervical_Radiculopathy/data/BIDS/sourcedata/ -jobs 10 -path-output /home/sbedard/sc_analysis_test_2023-08-14-all -script preprocess_data_spinalcord.sh -exclude-list [ ses-baselinebrain ses-followupbrain ]
~~~


### 3.3.Quality control and Manual correction

After running the analysis, check your Quality Control (QC) report by opening the file `./qc/index.html`. 

If segmentation or labeling issues are noticed while checking the QC report, proceed to manual correction using the procedure below:

1. In the QC report, search for `deepseg` or `sct_label_vertebrae` to only display results of spinal cord segmentation or vertebral labeling, respectively.
2. Review the spinal cord segmentation and vertebral labeling.
3. Click on the <kbd>F</kbd> key to indicate if the segmentation/labeling is OK ✅, needs manual correction ❌ or if the data is not usable ⚠️ (artifact). Two .yml lists, one for manual corrections and one for the unusable data, will automatically be generated. 
4. Download the lists by clicking on <kbd>Download QC Fails</kbd> and on <kbd>Download QC Artifacts</kbd>. 
5. Use [manual-correction](https://github.com/spinalcordtoolbox/manual-correction) repository to correct the spinal cord segmentation and vertebral labeling.

Ensure to validate the following images:
- T2w spinal cord segmentation
- T2w vertebral labeling
- T2star spinal cord segmentation
- T2star gray matter segmentation
- MTon spinal cord segmentation
- DWI mean moco segmentation
 TODO: add func

#### 3.3.1.Correct vertebral labeling
Run the following command:

~~~
 python manual_correction.py -config /mnt/c/Users/sb199/Projet3_data/k23_cervical_radiculopathy/qc_fail/qc_fail_disc.yml  -path-img /mnt/p/Mackeylab/Individual_Folders/Sandrine/sc_analysis_test_2023-08-14-all-v3/data_processed/ -suffix-files-label _labels-disc-manual -path-out /mnt/c/Users/sb199/Projet3_data/k23_cervical_radiculopathy/derivatives/labels
~~~
