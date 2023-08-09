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
sct_run_batch -path-data ~/mackeylab/PROJECTS/K23_Cervical_Radiculopathy/data/BIDS/sourcedata/ -jobs 2 -path-output ~/sc_analysis_test_2023-08-09 -script preprocess_data_spinalcord.sh -include sub-CR002
~~~
