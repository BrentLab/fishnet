#!/bin/bash

#SBATCH -J fishnet_phase1_step1
#SBATCH --mem-per-cpu=4G
#SBATCH --cpus-per-task=1
#SBATCH -o ./logs/fishnet_phase1_step1_%J.out

MASTER_DIR=$1
ARRAYJOB_FILE=$2

cd $MASTER_DIR # move to master script directory (important to set proper nextflow launchDir)
TRAITPATH=$( sed -n ${SLURM_ARRAY_TASK_ID}p $ARRAYJOB_FILE )

TRAITNAME=$( basename $TRAITPATH )
PVALFILEPATH="${TRAITPATH}/0-${TRAITNAME}.csv"
NUMTESTS=$(( $(wc -l < "$PVALFILEPATH") - 1 ))

nextflow run ./scripts/phase1/nextflow/main.nf \
    --trait $TRAITNAME \
    --moduleFileDir $MODULE_FILE_PATH \
    --numTests $NUMTESTS \
    --pipeline $STUDY \
    --pvalFileName $PVALFILEPATH \
    --geneColName $GENECOLNAME \
    --pvalColName $PVALCOLNAME  \
    --bonferroni_alpha $BONFERRONI_ALPHA \
    -c $NXF_CONFIG
