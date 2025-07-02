#!/bin/bash

#SBATCH -J llfsTWAS
#SBATCH --mem=4G
#SBATCH --cpus-per-task=1
#SBATCH -o ./logs/llfsTWAS_4000%J.out


eval $(spack load --sh singularityce@3.8.0)
eval $(spack load --sh nextflow@22.10.4)
export SINGULARITY_CACHEDIR="/scratch/mblab/acharyas/fishnet/genome_biology/fishnet/singularity_images" # set up here to share with nextflow
export NXF_CONDA_CACHEDIR="/scratch/mblab/acharyas/conda_cache"
export TMPDIR="/scratch/mblab/acharyas/tmp"
export NXF_TEMP="/scratch/mblab/acharyas/tmp"
study="./data/pvals/llfsTWASOR/"
study_random="./data/pvals/llfsTWASRR/"
modules="./data/modules/networks/"
num_permutations=100

./fishnet_multi.sh \
    --study $study \
    --study-random $study_random \
    --modules $modules \
    --skip-stage-1 \
    --singularity \
    --conda \
    --conda_env fishnet \
    --num-permutations $num_permutations \
