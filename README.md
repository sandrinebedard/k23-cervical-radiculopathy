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
