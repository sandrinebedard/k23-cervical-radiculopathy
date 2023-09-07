# k23-cervical-radiculopathy
Analysis pipeline on Cervical Radiculopathy MRI project

## Table of content
* [1.Dependencies](#1dependencies)
* [2.Dataset](#2dataset)
* [3.Analysis pipeline](#3analysis-pipeline)
    * [3.1.Installation](#31installation)
    * [3.2.Cardiac peak detection and QC](#32cardiac-peak-detection-and-qc)
    * [3.3.Spinal cord preprocessing](#33spinal-cord-preprocessing)
    * [3.4.Quality control and Manual correction](#34quality-control-and-manual-correction)
        * [3.4.1.Correct vertebral labeling](#341correct-vertebral-labeling)
## 1.Dependencies

* SCT v6.0
* FSL 6.0
* Python 3.8.12

## 2.Dataset
`MACKEYLAB\Mackeylab\PROJECTS\K23_Cervical_Radiculopathy\data\BIDS\sourcedata`
The data has the following organization:

~~~
sourcedata
│
├── dataset_description.json
├── participants.json
├── participants.tsv
├── sub-CR001
├── sub-CR002
│   │
│   ├── ses-baselinespinalcord
│   │
│   └──  ses-followupspinalcord
|       ├── anat
│       │  ├── sub-CR002_ses-followupspinalcord_T2w.json
│       │  ├── sub-CR002_ses-followupspinalcord_T2w.nii.gz
│       │  ├── sub-CR002_ses-followupspinalcord_T2star.json
│       │  ├── sub-CR002_ses-followupspinalcord_T2star.nii.gz
│       │  ├── sub-CR002_ses-followupspinalcord_acq-T1w_MTS.json
│       │  ├── sub-CR002_ses-followupspinalcord_acq-T1w_MTS.nii.gz
│       │  ├── sub-CR002_ses-followupspinalcord_acq-MTon_MTS.json
│       │  ├── sub-CR002_ses-followupspinalcord_acq-MTon_MTS.nii.gz
│       │  ├── sub-CR002_ses-followupspinalcord_acq-MToff_MTS.json
│       │  └── sub-CR002_ses-followupspinalcord_acq-MToff_MTS.nii.gz
|       ├── dwi
│       │  ├── sub-CR002_ses-followupspinalcord_dwi.nii.gz
│       │  ├── sub-CR002_ses-followupspinalcord_dwi.json
│       │  ├── sub-CR002_ses-followupspinalcord_dwi.bvec
│       │  └── sub-CR002_ses-followupspinalcord_dwi.bval
│       └── func
│          ├── sub-CR002_ses-followupspinalcord_task-rest_bold.json
│          ├── sub-CR002_ses-followupspinalcord_task-rest_bold.nii.gz
│          └── sub-CR002_ses-followupspinalcord_task-rest_physio.tsv
derivatives
    └── labels
        └── sub-CR002
             ├── ses-baselinespinalcord
             │
             └── ses-followupspinalcord
                 │
                 ├── anat
                 │     ├── sub-CR002_ses-followupspinalcord_T2star_gmseg.nii.gz  <---------- manually-corrected spinal cord gray matter segmentation
                 │     ├── sub-CR002_ses-followupspinalcord_T2star_gmseg.json  <------------ information about origin of segmentation
                 │     ├── sub-CR002_ses-followupspinalcord_T2w_seg.nii.gz  <------- manually-corrected spinal cord segmentation
                 │     ├── sub-CR002_ses-followupspinalcord_T2w_seg.json
                 │     ├── sub-CR002_ses-followupspinalcord_T2w_labels-disc-manual.nii.gz  <------- manual intervertebral discs labels
                 │     └── sub-CR002_ses-followupspinalcord_T2w_labels-disc-manual.json
                 └── func  
                      ├── sub-CR002_ses-followupspinalcord_task-rest_bold_mc2_mean_seg.nii.gz  <------- manually-corrected spinal cord segmentation
                      ├── sub-CR002_ses-followupspinalcord_task-rest_bold_mc2_mean_seg.json                      
                      ├── sub-CR002_ses-followupspinalcord_task-rest_bold_mc2_mean_SC_canal_seg.nii.gz  <---------- manually-corrected spinal canal segmentation
                      ├── sub-CR002_ses-followupspinalcord_task-rest_bold_mc2_mean_SC_canal_seg.nii.gz  <------------ information about origin of segmentation
                      ├── sub-CR002_ses-followupspinalcord_task-rest_physio_peak.json  <------- manual cardiac peak detection added to physio file in FSl format
                      └──sub-CR002_ses-followupspinalcord_task-rest_physio_peak.txt
~~~

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
### 3.2.Cardiac peak detection and QC
~~~
sct_run_batch -jobs 1 -path-data /mnt/p/Mackeylab/PROJECTS/K23_Cervical_Radiculopathy/data/BIDS/sourcedata/ -path-out /mnt/c/Users/sb199/Projet3_data/k23_cervical_radiculopathy/peak_detection_all-2023-08-23 -script detect_peak_batch.sh -script-args "Sandrine Bedard" -exclude-list [ ses-baselinebrain ses-followupbrain ]
~~~
Where:
* `-script-args`: Name of expert rater QCing the cardiac peaks


Copy the derivatives located `PATH_OUT/data_processed/derivatives` to the derivatives of the source data.

### 3.3.Spinal cord preprocessing

Launch preprocessing:

~~~
sct_run_batch -path-data <k23_cervical_radiculopathy/data/sourcedata/> -jobs 2 -path-output <PATH_OUT> -script preprocess_data_spinalcord.sh
~~~


Example of command:

~~~
sct_run_batch -path-data /home/sbedard/mackeylab/PROJECTS/K23_Cervical_Radiculopathy/data/BIDS/sourcedata/ -jobs 10 -path-output /home/sbedard/sc_analysis_test_2023-08-14-all -script preprocess_data_spinalcord.sh -exclude-list [ ses-baselinebrain ses-followupbrain ]
~~~


### 3.4.Quality control and Manual correction

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

#### 3.4.1.Correct vertebral labeling
Run the following command:

~~~
 python manual_correction.py -config /mnt/c/Users/sb199/Projet3_data/k23_cervical_radiculopathy/qc_fail/qc_fail_disc.yml  -path-img /mnt/p/Mackeylab/Individual_Folders/Sandrine/sc_analysis_test_2023-08-14-all-v3/data_processed/ -suffix-files-label _labels-disc-manual -path-out /mnt/c/Users/sb199/Projet3_data/k23_cervical_radiculopathy/derivatives/labels
~~~


## Statistical analysis
~~~
python analyse_anatomical.py -i-folder /mnt/c/Users/sb199/Projet3_data/k23_cervical_radiculopathy/test_csa_2023-08-29-v3/results/ -session baseline -o-folder /mnt/c/Users/sb199/Projet3_data/k23_cervical_radiculopathy/results_2023-08-29
~~~
