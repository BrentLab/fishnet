#!/bin/bash

trait=$1
results_dir=$2
traitRR="${trait}RR"

# 1. create outer trait directories
trait_dir="$results_dir/$trait/"
traitRR_dir="$results_dir/$traitRR/"

mkdir -p $trait_dir
mkdir -p $traitRR_dir

# 2. move over original results
mv "$results_dir/GO_summaries" $trait_dir
mv "$results_dir/masterSummaries" $trait_dir
mv "$results_dir/master_summary_${trait}.csv" $trait_dir/master_summary.csv

# 3. move over permutation results
mv "$results_dir/GO_summaries_RP" "$traitRR_dir/GO_summaries"
mv "$results_dir/masterSummaries_RP" "$traitRR_dir/masterSummaries"
mv "$results_dir/master_summary_${traitRR}.csv" $traitRR_dir/master_summary.csv
