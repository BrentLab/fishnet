#!/bin/bash

#SBATCH -J fishnet_phase1_step3_multi
#SBATCH --mem=4G
#SBATCH --cpus-per-task=1
#SBATCH -o ./logs/fishnet_phase1_step3_multi_%J.out

cd $1 # move to master script directory (important to set proper nextflow launchDir)

PVALFILEPATHRR="${STUDY_RANDOM_PATH}/${STUDY_RANDOM}.csv"
NUMTESTS=$(( $(wc -l < "$PVALFILEPATHRR") - 1 ))

nextflow run ./scripts/phase1/nextflow/main.nf \
    --trait $STUDY_RANDOM \
    --moduleFileDir $MODULE_FILE_PATH \
    --numTests $NUMTESTS \
    --pipeline $STUDY_RANDOM \
    --pvalFileName $PVALFILEPATHRR \
    --geneColName $GENECOLNAME \
    --pvalColName $PVALCOLNAME  \
    --bonferroni_alpha $BONFERRONI_ALPHA \
    --random_permutation \
    --numRP $NUM_PERMUTATIONS \
    --GO_summaries_path "GO_summaries" \
    --masterSummaries_path "masterSummaries" \
    -c $NXF_CONFIG \
    -resume
