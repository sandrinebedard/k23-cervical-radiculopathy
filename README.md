# k23-cervical-radiculopathy
Analysis pipeline on Cervical Radiculopathy MRI project

## Data

## Analysis pipeline
### Dependencies

* SCT v6.0
* FSL 

### Spinal cord preprocessing

Launch preprocessing:

~~~
sct_run_batch -path-data <k23_cervical_radiculopathy/data/sourcedata/> -jobs 2 -path-output <PATH_OUT> -script preprocess_data_spinalcord.sh
~~~


Example of command:

~~~
sct_run_batch -path-data /home/sbedard/mackeylab/PROJECTS/K23_Cervical_Radiculopathy/data/BIDS/sourcedata/ -jobs 10 -path-output /home/sbedard/sc_analysis_test_2023-08-14-all -script preprocess_data_spinalcord.sh -exclude-list [ ses-baselinebrain ses-followupbrain ]
~~~


### Quality control and Manual correction

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
