#!/bin/bash

#SBATCH --array=1-11%11
#SBATCH --mem=8G
#SBATCH --cpus-per-task=1
#SBATCH --output slurm_logs/log-%J.txt
#SBATCH -e slurm_logs/log-%J.err

#study id refers to the naming convention of the parent directory where input p-values are saved
#module refers to the type of modularization algorithm used
#result id refer to the naming convention of the parent directory where outputs of fishnet runs are saved

#$1 - studyid
#$2 - module
#$3 - resultid

ID=$( sed -n ${SLURM_ARRAY_TASK_ID}p /scratch/mblab/acharyas/fishnet/pipeline/data/pvals/traits_llfs.csv )

general_path=/scratch/mblab/acharyas/fishnet/pipeline/
studyid=$1
module=$2
resultid=$3
networks=("coex" "ppi" "ppi2") # List your three networks here

mkdir -p ${general_path}results/${resultid}/results
mkdir -p ${general_path}results/${resultid}/results/raw

master_summary_path=${general_path}results/${resultid}/

for network in "${networks[@]}"; do
    python -u dc_generate_or_statistics.py \
    --gene_set_path "${general_path}data/pvals/${studyid}/${ID}/" \
    --master_summary_path "${master_summary_path}master_summary_filtered_parsed.csv" \
    --trait "${ID}" \
    --module_path "${general_path}data/modules/${module}/${network}.txt" \
    --go_path "${general_path}results/${resultid}/GO_summaries/${ID}/" \
    --study "${studyid}" \
    --output_path "${general_path}results/${resultid}/results/raw/" \
    --network "${network}"

done