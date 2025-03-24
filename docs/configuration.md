---
title: Configuration
layout: home
nav_order: 3
permalink: /configuration
---

# FISHNET configuration
{: .no_toc }

[comment]: # TODO: describe configuration options for FISHNET

FISHNET currently supports platforms with either
[Singularity](https://docs.sylabs.io/guides/3.5/user-guide/introduction.html) or
[Docker](https://docs.docker.com/get-started/). FISHNET supports HPCs using the
SLURM workload manager to submit batch jobs for parallel computing.

FISHENT provides a command line interface (CLI) for execution. 

Simply run `./fishnet.sh` with no options or `./fishnet.sh -h` to see the list
of available top-level options.
1. Table of contents
{:toc}

## Parameters

### Required parameters

#### Trait
`--trait <path/to/input/file.csv>` (**Required**)

#### Network modules
`--modules </path/to/modules/directory/>` (**Required**)

### Optional parameters

#### Permutations
`--num-permutations <integer>`

#### Multiple testing
`--FDR-threshold <float>`

#### Percentile threshold
`--percentile-threshold <float>`

The `--percentile-threshold` parameter is used to ensure that the number of candidate FISHNET genes obtained using original ranks of genes is higher than or equal to those obtained using random permutation of gene ranks for X % of random permutations. X is the percentile-threshold initially set by the users. 

#### Skipping stages
`--skip-stage-1`

`--skip-stage-2`

#### Thresholding methods
`--thresholding-alternative`

#### Container platform
`--singularity`

#### Nextflow config file
The `--nxf-config <path/to/nxf.config>` option can be used to specify a custom
configuration file for running the Nextflow pipelines. If not specified, FISHNET
uses the `./conf/fishent_slurm.config` when the `--singularity` option is used
and `./conf/fishnet.config` otherwise.

See [Nextflow configuration](/configuration#nextflow-configuration) for details
on editing the configuration file.

#### Test run
`--test`

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
