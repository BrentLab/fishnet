---
title: Example
layout: home
nav_order: 3
permalink: /example
---

# Example FISHNET run
{: .no_toc }

Small example using maleWC (waist circumference) summary statistics.
{: .fs-6 .fw-300 }

{: .highlight }
This example assumes that you have already installed FISHNET (instructions at [Getting
Started]({% link  getting_started.md %}))

## Table of contents
{: .no_toc .text-delta }
1. TOC
{:toc}

---
If you are on a SLURM HPC that supports singularity, follow [SLURM HPC example](#slurm-hpc-example). Otherwise, follow
[Non-HPC example](#non-hpc-example) to run this example using Docker.

## SLURM HPC example

First, copy the example sbatch script `test/example_maleWC.sbatch` to the parent
FISHNET directory.

<details markdown="block"><summary>test/example_maleWC.sbatch</summary>
    #!/bin/bash

    #SBATCH -J fishnet_example_maleWC
    #SBATCH --mem=4G
    #SBATCH -o ./logs/fishnet_example_maleWC_%J.out

    # load required modules
    eval $(spack load --sh singularityce@3.8.0)
    eval $(spack load --sh nextflow@22.10.4)

    # recommended environmental variables
    export SINGULARITY_CACHEDIR=""
    export NXF_CONDA_CACHEDIR=""
    export TMPDIR=""
    export NXF_TEMP=""

    study="./test/exampleOR/"
    study_random="./test/exampleRR/"
    modules="./test/ker_based/"
    num_permutations=200

    ./fishnet.sh \
        --study $study \
        --study-random $study_random \
        --modules $modules \
        --singularity \
        --conda \
        --conda_env fishnet \
        --num-permutations $num_permutations

</details>

The `study` parameter points to the input study directory. For the example, the
input study is `exampleOR` which contains one `maleWC` trait subdirectory with
the `0-maleWC.csv` file with p-values.

For the `modules` parameter, we provide the three networks modules
discussed in the paper (STRING functional PPI, InWeb physical PPI, and gene
co-expression).

```
pvals
├── exampleOR
│   └── maleWC
│       └── 0-maleWC.csv
└── exampleRR
    └── exampleRR.csv
modules
└── ker_based
    ├── coex.txt
    ├── ppi2.txt
    └── ppi.txt
```
For the sake of efficiency, we are only running 500 permutations for this
example.

Submit the FISHNET job with `sbatch example_maleWC.sbatch` and the logfile
should keep track of the progress:
<details markdown="block"><summary>Log</summary>
    Configs:
    - container run-time: SINGULARITY
    singularity-ce version 3.8.0
    conda 4.11.0
    - nextflow config: ./conf/fishnet_slurm.config
    # Found 1 traits
    > maleWC
    # FOUND 3 module files
    Conda environment fishnet found
    pulling singularity images for nextflow

    ###############
    ### PHASE 1 ###
    ###############

    # STEP 1.1: executing Nextflow MEA pipeline on original run
    # STEP 1.2: compiling permutation results
    # STEP 1.3: executing Nextflow MEA pipeline on random permutations
    # STEP 1.4: compiling permutation results

    ########################
    ### PHASE 1 COMPLETE ###
    ########################

    ###############
    ### PHASE 2 ###
    ###############

    # STEP 2.0: filtering + parsing master_summary.csv files

    ##########################
    ## DEFAULT THRESHOLDING ##
    ##########################

    # STEP 2.1: generating statistics for original run
    RUNNING WITH CONDA ENVIRONMENT (fishnet)
    # STEP 2.2: generating statistics for permutation runs
    RUNNING WITH CONDA ENVIRONMENT (fishnet)
    # STEP 2.3: summarizing statistics
    RUNNING WITH CONDA ENVIRONMENT (fishnet)
    # STEP 2.4: identify MEA-passing genes
    RUNNING WITH CONDA ENVIRONMENT (fishnet)

    ########################
    ### PHASE 2 COMPLETE ###
    ########################

    ### FISHNET COMPLETE ###
</details>

## Non-HPC example

{: .warning }
Note that the non-HPC version runs sequentially and will take
_**substantially longer**_ than the HPC version.

Copy the example script `test/example_malewC_docker.sh` to the FISHNET
directory.

<details markdown="block"><summary>test/example_maleWC_docker.sh</summary>
    study="./data/pvals/exampleOR/"
    study_random="./data/pvals/exampleRR/"
    modules="./data/modules/ker_based/"
    num_permutations=200

    ./fishnet.sh \
        --study $study \
        --study-random $study_random \
        --modules $modules \
        --docker \
        --conda \
        --conda_env fishnet \
        --num-permutations $num_permutations
</details>
Run the script with `./example_maleWC_docker.sh`.


## Output
Once FISHNET has completed, the `results` directory should populate with output
files for the `maleWC` trait within the `exampleOR` study:
<details markdown='block'><summary>Output file structure</summary>
```
results
├── exampleOR
│   ├── GO_summaries
│   ├── masterSummaries
│   ├── master_summary.csv
│   ├── master_summary_exampleOR.csv
│   ├── master_summary_filtered.csv
│   ├── master_summary_filtered_parsed.csv
│   ├── pascalInput
│   ├── pascalOutput
│   ├── results
│   └── summary
└── exampleRR
    ├── GO_summaries
    ├── masterSummaries
    ├── master_summary.csv
    ├── master_summary_exampleRR.csv
    ├── master_summary_filtered.csv
    ├── master_summary_filtered_parsed.csv
    ├── pascalInput
    ├── pascalOutput
    ├── results
    └── summary
```
</details>

The results we're primarily interested in will be under
`results/exampleOR/summary/`:
```
results/exampleOR/summary/
├── 0-maleWC_coex_summary_200_permutations.csv
├── 0-maleWC_ppi2_summary_200_permutations.csv
├── 0-maleWC_ppi_summary_200_permutations.csv
├── ppi_0-maleWC_fishnet_genes_200_permutations_0.05.csv
└── ppi2_0-maleWC_fishnet_genes_200_permutations_0.05.csv
```
Here, we can see that we have found 2 FISHNET genes for `maleWC` in the `ppi`
network and 1 FISHNET gene in the `ppi2` network:
```bash
$ head *fishnet_genes*.csv
==> ppi_0-maleWC_fishnet_genes_200_permutations_0.05.csv <==
Threshold,Network,numNominal,Trait,NumFISHNETGenes,FISHNETGenes
190,ppi,860,0-maleWC,2.0,"['DEFA1', 'DEFA5']"

==> ppi2_0-maleWC_fishnet_genes_200_permutations_0.05.csv <==
Threshold,Network,numNominal,Trait,NumFISHNETGenes,FISHNETGenes
70,ppi2,860,0-maleWC,1.0,['DEFA5']
```
From the master summary file, we can locate the modules that contain these
FISHNET genes
```bash
$ cat master_summary_filtered_parsed.csv
study,trait,network,moduleIndex,isModuleSig,modulePval,moduleBonPval,size
exampleOR,0-maleWC,ppi,179,True,1.2896084813134806e-06,0.0013154006509397,6
exampleOR,0-maleWC,ppi2,278,True,6.0423189972850345e-05,0.0268278963479455,5
```
In the `results/GO_summaries` directory, we can find which GO biological process terms
were enriched in these modules:
```
==> GO_summaries/maleWC/GO_summaries_0-maleWC_ppi2/sig_exampleOR_0-maleWC_ppi2_278.csv <==
"geneSet","description","size","overlap","expect","enrichmentRatio","pValue","FDR","overlapId","userId","database"
"GO:0002385","mucosal immune response",12,3,0.00620876988746605,483.1875,1.14213107860195e-08,4.64305470340709e-05,"1669;1670;1671","DEFA6;DEFA4;DEFA5","geneontology_Biological_Process"
"GO:0002251","organ or tissue specific immune response",14,3,0.00724356486871039,414.160714285714,1.88934067280044e-08,4.64305470340709e-05,"1669;1670;1671","DEFA6;DEFA4;DEFA5","geneontology_Biological_Process"

==> GO_summaries/maleWC/GO_summaries_0-maleWC_ppi/sig_exampleOR_0-maleWC_ppi_179.csv <==
"geneSet","description","size","overlap","expect","enrichmentRatio","pValue","FDR","overlapId","userId","database"
"GO:0002385","mucosal immune response",12,5,0.00513347022587269,974,4.44089209850063e-16,2.43938202970639e-12,"1667;1669;1670;1671;1672","DEFB1;DEFA4;DEFA6;DEFA5;DEFA1","geneontology_Biological_Process"
"GO:0050832","defense response to fungus",24,4,0.0102669404517454,389.6,6.82681688957132e-11,4.68746314680191e-08,"1667;1669;1670;1671","DEFA4;DEFA6;DEFA5;DEFA1","geneontology_Biological_Process"
```
