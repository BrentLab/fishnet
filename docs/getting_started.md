---
title: Getting Started
layout: home
nav_order: 2
permalink: /getting-started
---

# Getting Started
{: .no_toc }

Here we guide you to get started on using FISHNET for your next project.

**Note:** if you use FISHNET in published research, please cite:

[comment]: # TODO: update FISHNET citation
> Acharya et al. (2025) FISHNET citation doi:

## Table of contents
{: .no_toc }

1. TOC
{:toc }

---

## Installation
Clone the FISHENT GitHub repository and `cd` into the local repository:
```bash
$ git clone https://github.com/BrentLab/fishnet.git
$ cd fishnet/
```
Run FISHNET on test data to verify successful installation:
```bash
$ ./fishnet.sh --test
```
**Note:** If your platform does not support Docker (e.g. in a HPC environment),
use the `--singularity` flag:
```bash
$ ./fishnet.sh --test --singularity
```
## Quick start
### Execution
Here we show the most basic steps for a FISHNET analysis. There are a variety of
configuration options which are detailed in [Configuration](/configuration).
This code chunk assumes that you have an input summary statistics file at
`/path/to/input/file.csv` (comma-separated with columns named "Genes" and
"p_vals") and a set of tab-delimited `.txt` network module files at
`/path/to/modules/directory/`.
```bash
$ ./fishnet.sh \
    --trait /path/to/input/file.csv \
    --modules /path/to/modules/directory/
```
This will run both stages of FISHNET with 10 permutations (by default) using the
default thresholding method (by default).

### Output files
The output files are saved in a `results/` subdirectory (by default) relative to
the current working directory where you launch `fishnet.sh`. Here, we guide you
through the expected output directory structure.

1. The `results/data/` directory stores the input summary statistics file and the input
module networks. In addition, the `results/data/<trait>RR/` directory saves the
uniformly distributed p-values based on the input summary statitics file as `<trait>RR.csv`.
```
results/
└── data/
    └── <trait>/
        └── 0-<trait>.csv
    └── <trait>RR/
        └── <trait>RR.csv
    └── modules/
        └── <module_algorithm>/
            ├── <module1>.txt
            ├── ...
            └── <module3>.txt
```

2. The `results/<trait>/` directory stores results for the input summary
statistics p-values. The `master_sumary.csv` is the final output file from
FISHNET. The `enriched_modules/` directory lists significantly enriched
modules for each network. The `GO_summaries/` directory lists statistics for the
GO overrepresentation analysis.
```
results/
└── <trait>/
    └── background_genes/
        ├── <module_algorithm>-<module1>.txt
        ├── ...
        └── <module_algorithm>-<module3>.txt
    └── enriched_modules/
        ├── <trait>-<module3>
        └── └── sig_<trait>-<module3>-179.txt
    └── GO_summaries/
        └── <trait>/
            ├── GO_summaries_0-<trait>_<module1>/
            ├── GO_summaries_0-<trait>_<module3>/
            └── └── sig_<trait>_0-<trait>_<module3>_179.csv
    ├── <trait>.txt
    └── masterSummaries/
        └── summaries/
            ├── <trait>_0-<trait>_<module1>.csv
            ├── ...
            └── <trait>_0-<trait>_<module3>.csv
    ├── master_summary.csv
    ├── master_summary_filtered.csv
    ├── master_summary_filtered_parsed.csv
    └── results/
        └── raw/
            ├── <module1>_0-<trait>_<module1>_or_fishnet_genes.csv
            ├── <module1>_0-<trait>_<module1>_or_summary.csv
            ├── ...
            ├── <module3>_0-<trait>_<module3>_or_fishnet_genes.csv
            └── <module3>_0-<trait>_<module3>_or_summary.csv
    └── summary/
        ├── 0-<trait>_<module1>_summary.csv
        ├── ...
        └── 0-<trait>_<module3>_summary.csv
```
   > [comment]: # TODO: DESCRIBE THE MASTER_SUMMARY.CSV FILE
   > SANDEEP: please describe the `master_summary.csv` file and how a user can
   > interpret its contents.
3. The `results/<trait>RR/` directory stores results for the permutations.
Subdirectory contents are identical to the original `<trait>` directory as
described above.
```
results/
└── <trait>RR/
    ├── background_genes/
    └── enriched_modules/
        ├── <trait>RR-<module1>/
        ├── <trait>RR-<module3>/
        ├── GO_summaries/
        └── <trait>RR/
    ├── <trait>RR.txt
    └── masterSummaries/
        └── summaries/
    ├── master_summary.csv
    ├── master_summary_filtered.csv
    └── master_summary_filtered_parsed.csv
```
