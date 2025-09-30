---
title: Getting Started
layout: home
nav_order: 2
permalink: /getting-started
---

# Getting Started
{: .no_toc }

Here we guide you to get started on using FISHNET for your next project.
{: .fs-6 .fw-300 }

{: .important-title }
> Citation
> 
> If you use FISHNET in published research, please cite the following paper:
>
> > **Acharya et al.**, *FISHNET: A Network-based Tool for Analyzing Gene-level P-values to Identify Significant Genes Missed by Standard Methods*, [doi:10.1101/2025.01.29.635546](https://doi.org/10.1101/2025.01.29.635546).

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc }

---

## Installation
Clone the FISHNET GitHub repository and `cd` into the local repository:
```bash
$ git clone https://github.com/BrentLab/fishnet.git
$ cd fishnet/
```
Run FISHNET on test data to verify successful installation:
```bash
$ ./fishnet.sh --test
```

{: .note }
> If your platform does not support Docker (e.g. in a HPC environment),
> use the `--singularity` flag:
> ```bash
> $ ./fishnet.sh --test --singularity
> ```

## Quick start

### Execution
Here we show the most basic steps for a FISHNET analysis. There are a variety of
configuration options which are detailed in [Configuration]({% link configuration.md %}).
This code chunk assumes that you have an input summary statistics file (comma-separated with columns named "Genes" and
"p_vals") and a set of tab-delimited network module files.

<details markdown="block"><summary>example summary statistics file
(<code>data/pvals/exampleOR/maleWC/0-maleWC.csv</code>)</summary>
    Genes,p_vals
    BRD3OS,0.12219547800000001
    PTCH2,0.8389969
    ASNS,0.274650263
    TTLL9,0.111914007
    AKR1D1,0.784900795
    LINC00839,0.901963325
</details>

<details markdown='block'><summary>example module file
format (<code>data/modules/ker_based/ppi2.txt</code>)</summary>
    0       1.0     SPEF2   PDE4B   SERTAD3
    1       1.0     CCL3L3  CCL15   CCL4L1  CCL3    CCL16   CCL5    CCL7    CCL28   CCL4L2  CCL14   CCL27   CXCL9   CCL8    CCL23   CXCL13  CCL26   CCL13   CCL24   CCL11   CCL3L1  CCL2
    2       1.0     ZHX1    COPS6   PLGRKT  SCO2    ABCB8
    3       1.0     PLXNC1  PHACTR2 HCN3    NEK8    SEMA7A  GPR63   GPR45   GPX1    TULP1   NCKAP5  BRPF3   FYN     GCFC2   LTBP2   LDAF1   RHOU    PAX7    SCARF2
    4       1.0     C7      C8B     NKX1-2  C8G     AKR1C1  C6      MMEL1   C8A     RFFL    C5      ZBTB1
    5       1.0     PIK3AP1 SLC23A1 ASAP1   CNTNAP1 SNX17   TGOLN2  CD2AP   ASAP2   ACAP1   F2RL2
</details>

To execute FISHNET, specify the `--study` argument with a directory path containing all trait subdirectories
with summary statistics files and the `--modules` argument with the directory
containing input network module files.

```bash
$ ./fishnet.sh \
    --study /path/to/input/study/directory/  \
    --modules /path/to/modules/directory/
```
This will run both stages of FISHNET with 200 permutations using the
default thresholding method (by default).

### Output files
The output files are saved in the `results/` directory (by default) relative to
the current working directory where you launch `fishnet.sh`. Here, we guide you
through the expected output directory structure.

1. The `results` directory will contain a `<study>` subdirectory containing
output files for the input study traits and a `<study>RR` subdirectory
containing similar output files for the permutations.
```
results/
├── <study>/
└── <study>RR/
```

2. Each `results/<study>/` directory, will look like so:
```
    results/
    └── <study>/
        ├── GO_summaries/
        ├── masterSummaries/
        ├── master_summary.csv
        ├── master_summary_<study>.csv
        ├── master_summary_filtered.csv
        ├── master_summary_filtered_parsed.csv
        ├── pascalInput/
        ├── pascalOutput/
        ├── results/
        └── summary/
```
The `GO_summaries/` directory lists statistics for the GO overrepresentation analysis. 
The FISHNET genes for the trait and the network the genes originate from can be found in  `summary/<network>_<trait>_fishnet_genes_<FDR-threshold>.csv`

Read through the [Example]({% link example.md %}) to interpret the output files.

