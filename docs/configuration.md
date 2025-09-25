---
title: Configuration
layout: home
nav_order: 3
permalink: /configuration
---

# Configuration
{: .no_toc }

Documentation of parameters and configuration options for FISHNET.
{: .fs-6 .fw-300 }

FISHNET currently supports platforms with either
[Singularity](https://docs.sylabs.io/guides/3.5/user-guide/introduction.html) or
[Docker](https://docs.docker.com/get-started/). FISHNET supports HPCs using the
SLURM workload manager to submit batch jobs for parallel computing.

FISHNET provides a command line interface (CLI) for execution. 

Simply run `./fishnet.sh` with no options or `./fishnet.sh -h` to see the list
of available top-level options.

##  Table of contents
{: .no_toc .text-delta }
1. TOC
{:toc}

---

## Parameters

### Required parameters

#### Study
`--study <path/to/study/directory>` (**Required**)
> Path to directory containing trait subdirectories with input summary
> statistics files e.g.
> ```
./fishnet/data/pvals/dreamGWASORKB/
├── 11D
│   └── 0-11D.csv
├── 11R
│   └── 0-11R.csv
├── 12D1
│   └── 0-12D1.csv
├── 12D2
│   └── 0-12D2.csv
└── 12R
    └── 0-12R.csv
```
>
> FISHNET runs for all traits that are in this directory.
> Summary statistics files must be CSV files with colnames "Genes" and "p_vals".
> Filename must not include any '_', '-', or '.' characters.

#### Network modules
`--modules </path/to/modules/directory/>` (**Required**)
> Path to directory containing network module files e.g.
> ```
data/modules/ker_based/
├── coex.txt
├── ppi2.txt
└── ppi.txt
```

### Optional parameters

#### Random P-values
`--study-random <path/to/random/permutation/study/directory>`
> Path to the directory containing uniformly distributed p-values for random permutations.
> e.g.
> ```
./fishnet/data/pvals/dreamGWASRRKB/
└── dreamGWASRRKB.csv
```

#### Permutations
`--num-permutations <integer>`
> Configures the number of permutations (default: 10)

#### Multiple testing
`--FDR-threshold <float>`
> Specify a custom FDR threshold cutoff (default: 0.05)

#### Percentile threshold
`--percentile-threshold <float>`
> The `--percentile-threshold` parameter is used to ensure that the number of candidate FISHNET genes obtained using original ranks of genes is higher than or equal to those obtained using random permutation of gene ranks for X % of random permutations. X is the percentile-threshold initially set by the users. 

#### Skipping stages
`--skip-stage-1`
> This skips stage 1 of FISHNET.
>
> STAGE 1 runs the module significance analysis and GO
> overrepresentation analysis for the observed and permuted p-values.

`--skip-stage-2`
> This skips stage 2 of FISHNET.
>
> STAGE 2 carries out the iterative thresholding and hypothesis testing for
> identifying FISHNET genes based on the outputs of STAGE 1.

#### Thresholding methods
`--thresholding-alternative`

#### Test run
`--test`
> This runs FISHNET with the default test configurations

### Environmental parameters

#### Container platform
`--singularity`
> Configures containers to run using Singularity (Docker, by default).

#### Nextflow config file
> The `--nxf-config <path/to/nxf.config>` option can be used to specify a custom
> configuration file for running the Nextflow pipelines. If not specified, FISHNET
> defaults to `./conf/fishent_slurm.config` when the `--singularity` option is used
> and `./conf/fishnet.config` otherwise.
> 
> See [Nextflow configuration](/configuration#nextflow-configuration) for details
> on editing the configuration file.

#### Use conda
`--conda`
> This option configures parts of FISHNET to run using a conda environment
> instead of using a Singularity container (much faster).
> 
> Note: only works when using `--singularity` in a SLURM platform.

#### Specify an existing conda environment
`--conda_env <conda_environment_name>`
> Use this option to specify an existing conda environment to use to run
> processes. Just make sure that the environment satisfies the package
> dependencies listed in `conf/fishnet_conda_environment.yml`. After the first
> time running FISHNET with `--conda`, it will
> automatically create a conda environment named `fishnet` for you. You can then
> run `--conda_env fishnet` to load the created environment.


## Nextflow configuration
FISHNET uses Nextflow pipelines for module enrichment analysis. Nextflow enables
scalable and reproducible scientific workflows using software containers and can
be run on different platforms. However, this requires a little bit of
configuration on the user-end to make the best out of your working environment.

By default, FISHNET comes with two preset Nextflow configuration files in the
`conf/` directory:

    conf/
    ├── fishnet.config
    └── fishnet_slurm.config

`fishnet.config` is configured for Nextflow to use Docker for software
containers and `fishnet_slurm.config` is configured for FISHNET to run on a
SLURM HPC using Singularity for software containers. Please refer to the [Nextflow
documentation](https://www.nextflow.io/docs/latest/config.html) for detailed
explanations of the configuration files.
