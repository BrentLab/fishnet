#!/bin/bash -ue

######################################
# Master script for FISHNET pipeline #
######################################

usage() {
cat << EOF
Master script for the FISHNET pipeline
Usage: fishnet.sh [options]

  Options:
    -h, --help
      Prints the command usage
      Default: false
    --test
      Runs the test configuration
      Default: true
    --skip-stage-1
        Skips stage 1 of FISHNET
        Default: false
    --skip-stage-2
        Skips stage 2 of FISHNET
        Default: false
    --thresholding-alternative
        Configures stage 2 to run alternative thresholding mechanism
        Default: false (runs default thresholding mechanism)
    --singularity
        Configures containers to run using singularity
        Default: false (runs containers using docker)
    --nxf-config <path/to/nxf.config>
        Specify a custom nextflow config to use
        Default: ./conf/fishnet.config using docker, ./conf/fishnet_slurm.config using singularity on SLURM
    --FDR-threshold <float>
        Specify a custom FDR threshold cutoff
        Default: 0.05
    --percentile-threshold <float>
        Specify a custom percentile threshold cutoff
        Default: 0.99
    --num-permutations <integer>
        Configures the number of permutations
        Default: 10
    --trait <path/to/input/file.csv>
        Path to the input summary statistics file.
        File must be a CSV file with colnames "Genes" and "p_vals".
        Filename must not include any '_', '-', or '.' characters.
        (Refer to ./test/maleWC/maleWC.csv for an example)
    --modules <path/to/modules/directory/>
        Path to directory containing network modules.
        Network module files must be tab-delimited .txt files
        (Refer to ./test/ker_based/ for examples)
EOF
}

TEST_MODE=false
SKIP_STAGE_1=false
SKIP_STAGE_2=false
THRESHOLDING_MODE_DEFAULT="default"
THRESHOLDING_MODE_ALTERNATIVE="alternative"
THRESHOLDING_MODE=$THRESHOLDING_MODE_DEFAULT
SINGULARITY=false
CONTAINER_RUNTIME="DOCKER"
NXF_CONFIG_DEFAULT_DOCKER="./conf/fishnet.config"
NXF_CONFIG_DEFAULT_SINGULARITY="./conf/fishnet_slurm.config"
NXF_CONFIG="$NXF_CONFIG_DEFAULT_DOCKER"
nxf_config_provided=false
OUTPUT_DIR=$( readlink -f "./results/" )
DATADIR="${OUTPUT_DIR}/data/"
MODULEDIR="${DATADIR}/modules/"
GENECOLNAME="Genes"
PVALCOLNAME="p_vals"
BONFERRONI_ALPHA=0.05 # for phase 1 nextflow scripts

# parameters
FDR_THRESHOLD=0.05
PERCENTILE_THRESHOLD=0.99
NUM_PERMUTATIONS=10
TRAITPATH="NONE"

# print usage if no args
if [ "$#" -eq 0 ]; then
    usage
    exit 1
fi

# parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --test)
            TEST_MODE=true
            shift
            ;;
        --skip-stage-1)
            SKIP_STAGE_1=true
            shift
            ;;
        --skip-stage-2)
            SKIP_STAGE_2=true
            shift
            ;;
        --thresholding-alternative)
            THRESHOLDING_MODE=$THRESHOLDING_MODE_ALTERNATIVE
            shift
            ;;
        --singularity)
            SINGULARITY=true
            CONTAINER_RUNTIME="SINGULARITY"
            shift
            ;;
        --nxf-config)
            # make sure we have a value and not another flag
            if [[ -n "$2" && ! "$2" =~ ^- ]]; then
                NXF_CONFIG="$2"
                nxf_config_provided=true
                shift 2
            else
                echo "ERROR: --nxf-config requires a path argument."
                exit 1
            fi
            ;;
        --FDR-threshold)
            # make sure we have a value and not another flag
            if [[ -n "$2" && ! "$2" =~ ^- ]]; then
                FDR_THRESHOLD="$2"
                shift 2
            else
                echo "ERROR: --FDR-threshold requires a float argument."
                exit 1
            fi
            ;;
        --percentile-threshold)
            # make sure we have a value and not another flag
            if [[ -n "$2" && ! "$2" =~ ^- ]]; then
                PERCENTILE_THRESHOLD="$2"
                shift 2
            else
                echo "ERROR: --percentile-threshold requires a float argument."
                exit 1
            fi
            ;;
        --trait)
            # make sure we have a value and not another flag
            if [[ -n "$2" && ! "$2" =~ ^- ]]; then
                TRAITPATH="$2"
                shift 2
            else
                echo "ERROR: --trait requires a string path argument."
                exit 1
            fi
            ;;
        --modules)
            # make sure we have a value and not another flag
            if [[ -n "$2" && ! "$2" =~ ^- ]]; then
                INPUTMODULEDIR="$2"
                shift 2
            else
                echo "ERROR: --modules requires a string path argument."
                exit 1
            fi
            ;;
        --num-permutations)
            # make sure we have a value and not another flag
            if [[ -n "$2" && ! "$2" =~ ^- ]]; then
                NUM_PERMUTATIONS="$2"
                shift 2
            else
                echo "ERROR: --num-permutations requires an integer argument."
                exit 1
            fi
            ;;
        *)
            echo "ERROR: Unknown option $1"
            usage
            exit 1
            ;;
    esac
done

# check if both stage skip flags have been set
if [ "$SKIP_STAGE_1" = true ] && [ "$SKIP_STAGE_2" = true ]; then
    echo "Both --skip-stage-1 and --skip-stage-2 provided. Nothing to do. Exiting."
    exit 0
fi

# check for singularity
if [ "$SINGULARITY" = true ]; then
    # if singularity requested, but user did not specify --nxf_config
    if [ "$nxf_config_provided" = false ]; then
        NXF_CONFIG="$NXF_CONFIG_DEFAULT_SINGULARITY"
    fi
fi

# print configs
echo "Configs:"
echo " - container run-time: $CONTAINER_RUNTIME"
if [ "$CONTAINER_RUNTIME" = "SINGULARITY" ]; then
    singularity --version
else
    docker --version
fi
echo " - nextflow config: $NXF_CONFIG"
### set test parameters ###
if [ "$TEST_MODE" = true ]; then
    TRAITPATH="./test/maleWC/maleWC.csv"
    INPUTMODULEDIR="./test/ker_based/"
else
    # check for required input parameters
    # input trait file
    if [ ! -f "$TRAITPATH" ]; then
        echo "--trait $TRAITPATH FILE NOT FOUND"
        exit 1
    fi
    # input modules directory
    if [ ! -d "$INPUTMODULEDIR" ]; then
        echo "--modules $INPUTMODULEDIR DIRECTORY NOT FOUND"
        exit 1
    fi
fi

# process input pval file #
filebasename=$( basename $TRAITPATH )
TRAIT="${filebasename%.*}"
TRAITRR="${TRAIT}RR"

# copy over input pval file
PVALFILEDIR="${DATADIR}/${TRAIT}"
PVALFILEDIRRR="${DATADIR}/${TRAITRR}"
mkdir -p $PVALFILEDIR $PVALFILEDIRRR
PVALFILEPATH="${PVALFILEDIR}/0-${TRAIT}.csv"
PVALFILEPATHRR="${PVALFILEDIRRR}/${TRAITRR}.csv"
cp $TRAITPATH $PVALFILEPATH
NUMTESTS=$(( $(wc -l < "$PVALFILEPATH") - 1 ))

# copy over input modules files
mkdir -p $MODULEDIR
cp -r $INPUTMODULEDIR $MODULEDIR
MODULE_ALGO=$( basename $INPUTMODULEDIR )
MODULEFILEDIR=${MODULEDIR}/${MODULE_ALGO}


### export parameters ###
export TRAIT
export TRAITRR
export NUM_PERMUTATIONS
export PVALFILEDIR
export PVALFILEPATH
export PVALFILEPATHRR
export MODULE_ALGO
export MODULEFILEDIR
export NUMTESTS
export GENECOLNAME
export PVALCOLNAME
export BONFERRONI_ALPHA
export OUTPUT_DIR
export FDR_THRESHOLD
export PERCENTILE_THRESHOLD
export NXF_CONFIG

### list of containers ###
# contains all python dependencies for fishnet
#   TODO: create single container with all python dependencies (include statsmodels)
#   TODO: add to biocontainers 
export container_python="docker://jungwooseok/dc_rp_genes:1.0"
export container_R="docker://jungwooseok/r-webgestaltr:1.0"

#################
### FUNCTIONS ###
#################

pull_docker_image() {

    if [ "$SINGULARITY" = true ]; then
        if [ ! -d "$(pwd)/singularity_images/" ]; then
            mkdir "$(pwd)/singularity_images"
        fi

        container_python_docker=$container_python
        container_R_docker=$container_R
        export container_python="$(pwd)/singularity_images/dc_rp_genes.sif"
        export container_R="$(pwd)/singularity_images/r_webgestaltr.sif"

        if [ ! -f $container_python ]; then
            JOB_PULL_SINGULARITY_PYTHON=$(sbatch <<EOT
#!/bin/bash
#SBATCH -J pull_singularity_container_python
#SBATCH -o ./logs/pull_singularity_container_python_%J.out
singularity pull $container_python $container_python_docker
EOT
)
            JOB_PULL_SINGULARITY_PYTHON_ID=$( echo "$JOB_PULL_SINGULARITY_PYTHON" | awk '{print $4}')
        fi
        if [ ! -f $container_R ]; then
            JOB_PULL_SINGULARITY_R=$(sbatch <<EOT
#!/bin/bash
#SBATCH -J pull_singularity_container_R
#SBATCH -o ./logs/pull_singularity_container_R_%J.out
singularity pull $container_python $container_R_docker
EOT
)
            JOB_PULL_SINGULARITY_R_ID=$( echo "$JOB_PULL_SINGULARITY_R" | awk '{print $4}')
        fi
    fi
}

phase1_step1() {

    # (1) nextflow original run
    echo "# STEP 1.1: executing Nextflow MEA pipeline on original run"
    if [ "$SINGULARITY" = true ]; then
        JOB_STAGE1_STEP1=$(sbatch --dependency=afterok:"$JOB_PULL_SINGULARITY_PYTHON_ID":"$JOB_PULL_SINGULARITY_R_ID" ./scripts/phase1/phase1_step1.sh $(pwd))
        JOB_STAGE1_STEP1_ID=$(echo "$JOB_STAGE1_STEP1" | awk '{print $4}')
    else
        ./scripts/phase1/phase1_step1.sh $(pwd)
    fi

    # (4.1) original
    summaries_path_original="${OUTPUT_DIR}/masterSummaries/summaries/"
    if [ "$SINGULARITY" = true ]; then
        JOB_STAGE1_STEP4_ORIGINAL=$(sbatch --dependency=afterok:"$JOB_STAGE1_STEP1_ID" <<EOT
#!/bin/bash
#SBATCH -J phase1_step4_original
#SBATCH -o ./logs/phase1_step4_original_%J.out
singularity exec --no-home -B $(pwd):$(pwd) --pwd $(pwd) $container_python \
python3 ./scripts/phase1/compile_results.py \
    --dirPath $summaries_path_original \
    --identifier $TRAIT \
    --output $OUTPUT_DIR
EOT
)
        JOB_STAGE1_STEP4_ORIGINAL_ID=$(echo "$JOB_STAGE1_STEP4_ORIGINAL" | awk '{print $4}')
    else
        docker run --rm -v $(pwd):$(pwd) -w $(pwd) -u $(id -u):$(id -g) $container_python /bin/bash -c \
            "python3 ./scripts/phase1/compile_results.py \
                --dirPath $summaries_path_original \
                --identifier $TRAIT \
                --output $OUTPUT_DIR"
    fi

}

phase1_step3() {

    # (2) generate uniform p-values
    echo "# STEP 1.2: generating uniformly distributed p-values"
    if [ "$SINGULARITY" = true ]; then
        JOB_STAGE1_STEP2=$(sbatch <<EOT
#!/bin/bash
#SBATCH -J phase1_step2
#SBATCH -o ./logs/phase1_step2_%J.out
singularity exec --no-home -B $(pwd):$(pwd) --pwd $(pwd) $container_python \
python3 ./scripts/phase1/generate_uniform_pvals.py \
    --genes_filepath $PVALFILEPATH
EOT
)
        JOB_STAGE1_STEP2_ID=$(echo "$JOB_STAGE1_STEP2" | awk '{print $4}')
    else
        docker run --rm -v $(pwd):$(pwd) -w $(pwd) -u $(id -u):$(id -g) $container_python  /bin/bash -c \
            "python3 ./scripts/phase1/generate_uniform_pvals.py \
            --genes_filepath $PVALFILEPATH"
    fi

    # (3) nextflow random permutation run
    echo "# STEP 1.3: executing Nextflow MEA pipeline on random permutations"
    echo "executing Nextflow MEA pipeline on random permutations"
    if [ "$SINGULARITY" = true ]; then
        JOB_STAGE1_STEP3=$(sbatch --dependency=afterok:"$JOB_STAGE1_STEP2_ID" ./scripts/phase1/phase1_step3.sh $(pwd))
        JOB_STAGE1_STEP3_ID=$(echo "$JOB_STAGE1_STEP3" | awk '{print $4}')
    else
        ./scripts/phase1/phase1_step3.sh $(pwd)
    fi

    # (4.2)
    summaries_path_permutation="${OUTPUT_DIR}/masterSummaries_RP/summaries/"
    if [ "$SINGULARITY" = true ]; then
        JOB_STAGE1_STEP4_PERMUTATION=$(sbatch --dependency=afterok:"$JOB_STAGE1_STEP3_ID" <<EOT
#!/bin/bash
#SBATCH -J phase1_step4_permutation
#SBATCH -o ./logs/phase1_step4_permutation_%J.out
singularity exec --no-home -B $(pwd):$(pwd) --pwd $(pwd) $container_python \
python3 ./scripts/phase1/compile_results.py \
    --dirPath $summaries_path_permutation \
    --identifier ${TRAITRR} \
    --output $OUTPUT_DIR
EOT
)
        JOB_STAGE1_STEP4_PERMUTATION_ID=$(echo "$JOB_STAGE1_STEP4_PERMUTATION" | awk '{print $4}')
    else
        docker run --rm -v $(pwd):$(pwd) -w $(pwd) -u $(id -u):$(id -g) $container_python /bin/bash -c \
            "python3 ./scripts/phase1/compile_results.py \
                --dirPath $summaries_path_permutation \
                --identifier ${TRAITRR} \
                --output $OUTPUT_DIR"
    fi

}

phase1_step5() {

    # (5) organize phase 1 results
    echo "# STEP 5: restructuring phase 1 results for input to phase 2"
    # TODO: consider defining shell functions in separate file
    # function to organize phase 1 nextflow pipeline results
    if [ "$SINGULARITY" = true ]; then
        JOB_STAGE1_STEP5=$(sbatch --dependency=afterok:"$JOB_STAGE1_STEP4_ORIGINAL_ID","$JOB_STAGE1_STEP4_PERMUTATION_ID" <<EOT
#!/bin/bash
#SBATCH -J phase1_step5
#SBATCH -o ./logs/phase1_step5_%J.out
organize_nextflow_results() {
    trait=\$1
    results_dir=\$2
    traitRR=\$3

    # create outer trait directories
    trait_dir="\${results_dir}/\${trait}/"
    traitRR_dir="\${results_dir}/\${traitRR}/"
    mkdir -p \$trait_dir \$traitRR_dir

    # move over original results
    mv "\${results_dir}/GO_summaries" \${trait_dir}
    mv "\${results_dir}/masterSummaries" \${trait_dir}
    mv "\${results_dir}/master_summary_\${trait}.csv" \${trait_dir}/master_summary.csv

    # 3. move over permutation results
    mv "\${results_dir}/GO_summaries_RP" "\${traitRR_dir}/GO_summaries"
    mv "\${results_dir}/masterSummaries_RP" "\${traitRR_dir}/masterSummaries"
    mv "\${results_dir}/master_summary_\${traitRR}.csv" \${traitRR_dir}/master_summary.csv
}
organize_nextflow_results $TRAIT $OUTPUT_DIR $TRAITRR
EOT
)
        JOB_STAGE1_STEP5_ID=$(echo "$JOB_STAGE1_STEP5" | awk '{print $4}')
    else
        organize_nextflow_results() {
            trait=$1
            results_dir=$2
            traitRR="${TRAITRR}"

            # create outer trait directories
            trait_dir="${results_dir}/${TRAIT}/"
            traitRR_dir="${results_dir}/${TRAITRR}/"
            mkdir -p $TRAIT_dir $TRAITRR_dir

            # move over original results
            mv "${results_dir}/GO_summaries" ${trait_dir}
            mv "${results_dir}/masterSummaries" ${trait_dir}
            mv "${results_dir}/master_summary_${TRAIT}.csv" ${trait_dir}/master_summary.csv

            # 3. move over permutation results
            mv "${results_dir}/GO_summaries_RP" "${traitRR_dir}/GO_summaries"
            mv "${results_dir}/masterSummaries_RP" "${traitRR_dir}/masterSummaries"
            mv "${results_dir}/master_summary_${TRAITRR}.csv" ${traitRR_dir}/master_summary.csv
        }
        organize_nextflow_results $TRAIT $OUTPUT_DIR
    fi
}

phase2_step0() {
    # (0) filter the summary file for original/permuted runs
    echo "# STEP 2.0: filtering + parsing master_summary.csv files"
    ( head -n 1 "${OUTPUT_DIR}/${TRAIT}/master_summary.csv"; grep 'True' "${OUTPUT_DIR}/${TRAIT}/master_summary.csv" ) > "${OUTPUT_DIR}/${TRAIT}/master_summary_filtered.csv"
    cut -d ',' -f 1-8 "${OUTPUT_DIR}/${TRAIT}/master_summary_filtered.csv" > "${OUTPUT_DIR}/${TRAIT}/master_summary_filtered_parsed.csv"

    ( head -n 1 "${OUTPUT_DIR}/${TRAITRR}/master_summary.csv"; grep 'True' "${OUTPUT_DIR}/${TRAITRR}/master_summary.csv" ) > "${OUTPUT_DIR}/${TRAITRR}/master_summary_filtered.csv"
    cut -d ',' -f 1-8 "${OUTPUT_DIR}/${TRAITRR}/master_summary_filtered.csv" > "${OUTPUT_DIR}/${TRAITRR}/master_summary_filtered_parsed.csv"
}

phase2_step1_default() {
    ## (1) generate statistics for original run
    echo "# STEP 2.1: generating statistics for original run"
    if [ "$SINGULARITY" = true ]; then
        tmpfile=$(mktemp --tmpdir="$(pwd)/tmp")
        ls ${MODULEFILEDIR} > $tmpfile
        num_networks=$( wc -l < $tmpfile)
        JOB_STAGE2_STEP1_DEFAULT=$(sbatch <<EOT
#!/bin/bash
#SBATCH -J phase2_step1_default
#SBATCH --array=1-$num_networks
#SBATCH -o ./logs/phase2_step1_default_%A_%a.out
network=\$( sed -n \${SLURM_ARRAY_TASK_ID}p $tmpfile  )
network="\${network%.*}" # remove extension
echo "Network: \$network"
singularity exec --no-home -B $(pwd):$(pwd) --pwd $(pwd) $container_python \
    python3 ./scripts/phase2/dc_generate_or_statistics.py \
        --gene_set_path $PVALFILEDIR \
        --master_summary_path ${OUTPUT_DIR}/${TRAIT}/master_summary_filtered_parsed.csv \
        --trait $TRAIT  \
        --module_path ${MODULEFILEDIR}/\${network}.txt \
        --go_path ${OUTPUT_DIR}/${TRAIT}/GO_summaries/${TRAIT}/ \
        --study $TRAIT \
        --output_path ${OUTPUT_DIR}/${TRAIT}/results/raw/ \
        --network \$network
EOT
)
        #rm $tmpfile
        JOB_STAGE2_STEP1_DEFAULT_ID=$(echo "$JOB_STAGE2_STEP1_DEFAULT" | awk '{print $4}')
    else
        for network in `ls ${MODULEFILEDIR}/`;
        do
            echo "Network: $network"
            network="${network%.*}" # remove extension
            docker run --rm -v $(pwd):$(pwd) -w $(pwd) -u $(id -u):$(id -g) $container_python /bin/bash -c \
                "python3 ./scripts/phase2/dc_generate_or_statistics.py \
                    --gene_set_path $PVALFILEDIR \
                    --master_summary_path ${OUTPUT_DIR}/${TRAIT}/master_summary_filtered_parsed.csv \
                    --trait $TRAIT  \
                    --module_path ${MODULEFILEDIR}/${network}.txt \
                    --go_path ${OUTPUT_DIR}/${TRAIT}/GO_summaries/${TRAIT}/ \
                    --study $TRAIT \
                    --output_path ${OUTPUT_DIR}/${TRAIT}/results/raw/ \
                    --network $network"
        done
    fi
}

create_tmp_threshold_network_pairs_default() {
    # 1. take 25% of number of genes form original p-values input file
    #pct_25=$( bc <<< "scale=2; 0.25 * $NUMTESTS" )
    #rounded_25=$( printf "%.0f" "$pct_25" )
    rounded_25=$(( (25 * NUMTESTS + 50) / 100 ))
    # 2. range 10..{1} take nearest multiple of 10
    max_threshold=$(( rounded_25 - (rounded_25 % 10) ))
    thresholds=()
    for (( i=10; i<=max_threshold; i+=10 )); do
        thresholds+=( "$i" )
    done

    modules=( $( ls ./test/ker_based/*.txt ) )
    for f in "${modules[@]}"; do
        base="$(basename "$f" .txt )"
        for t in "${thresholds[@]}"; do
            echo -e "${t}\t${base}"
        done
    done
}

phase2_step2_default() {

    # (2.2) generate statistics for permutation run
    echo "# STEP 2.2: generating statistics for permutation runs"
    genes_rpscores_filedir="./results/RPscores/${TRAITRR}/"
    tmpfile=$(mktemp --tmpdir="$(pwd)/tmp")
    create_tmp_threshold_network_pairs_default > $tmpfile
    if [ "$SINGULARITY" = true ]; then
        num_pairs=$( wc -l < $tmpfile )
        JOB_STAGE2_STEP2_DEFAULT=$(sbatch --dependency=afterok:"$JOB_STAGE2_STEP1_DEFAULT_ID" <<EOT
#!/bin/bash
#SBATCH -J phase2_step2_default
#SBATCH --array=1-$num_pairs
#SBATCH --mem-per-cpu=4G
#SBATCH --cpus-per-task=1
#SBATCH -o ./logs/phase2_step2_default_%A_%a.out
network=\$( sed -n \${SLURM_ARRAY_TASK_ID}p $tmpfile | cut -f 2 )
threshold=\$( sed -n \${SLURM_ARRAY_TASK_ID}p $tmpfile | cut -f 1 )
echo \$network
echo \$threshold
singularity exec --no-home -B $(pwd):$(pwd) --pwd $(pwd) $container_python \
    python3 ./scripts/phase2/dc_generate_rp_statistics.py \
        --gene_set_path $genes_rpscores_filedir \
        --master_summary_path ${OUTPUT_DIR}/${TRAITRR}/master_summary_filtered_parsed.csv \
        --trait ${TRAITRR} \
        --module_path ${MODULEFILEDIR}/\${network}.txt \
        --go_path ${OUTPUT_DIR}/${TRAITRR}/GO_summaries/${TRAITRR}/ \
        --output_path ${OUTPUT_DIR}/${TRAITRR}/results/raw/ \
        --network \$network \
        --threshold \$threshold \
        --num_permutations ${NUM_PERMUTATIONS}
EOT
)
        JOB_STAGE2_STEP2_DEFAULT_ID=$(echo "$JOB_STAGE2_STEP2_DEFAULT" | awk '{print $4}')
    else
        while IFS=$'\t' read -r threshold network; do
            echo "Threshold $threshold, Network: $network"
            docker run --rm -v $(pwd):$(pwd) -w $(pwd) -u $(id -u):$(id -g) $container_python /bin/bash -c \
                "python3 ./scripts/phase2/dc_generate_rp_statistics.py \
                    --gene_set_path $genes_rpscores_filedir \
                    --master_summary_path ${OUTPUT_DIR}/${TRAITRR}/master_summary_filtered_parsed.csv \
                    --trait ${TRAITRR} \
                    --module_path ${MODULEFILEDIR}/${network}.txt \
                    --go_path ${OUTPUT_DIR}/${TRAITRR}/GO_summaries/${TRAITRR}/ \
                    --output_path ${OUTPUT_DIR}/${TRAITRR}/results/raw/ \
                    --network $network \
                    --threshold $threshold \
                    --num_permutations $NUM_PERMUTATIONS"
        done < $tmpfile
   fi
   #rm -rf $tmpfile
}

phase2_step3_default() {
    # (3) summarize statistics
    echo "# STEP 2.3: summarizing statistics"
    if [ "$SINGULARITY" = true ]; then
        tmpfile=$(mktemp --tmpdir="$(pwd)/tmp")
        ls ${MODULEFILEDIR} > $tmpfile
        num_networks=$( wc -l < $tmpfile)
        JOB_STAGE2_STEP3_DEFAULT=$(sbatch --dependency=afterok:"$JOB_STAGE2_STEP2_DEFAULT_ID" <<EOT
#!/bin/bash
#SBATCH -J phase2_step3_default
#SBATCH --array=1-$num_networks
#SBATCH --mem-per-cpu=4G
#SBATCH --cpus-per-task=1
#SBATCH -o ./logs/phase2_step3_default_%A_%a.out
network=\$( sed -n \${SLURM_ARRAY_TASK_ID}p $tmpfile )
network="\${network%.*}" # remove extension
echo "Network: \$network"
singularity exec --no-home -B $(pwd):$(pwd) --pwd $(pwd) $container_python \
    python3 ./scripts/phase2/dc_summary_statistics_rp.py \
        --trait $TRAIT \
        --input_path $OUTPUT_DIR \
        --or_id $TRAIT \
        --rr_id $TRAITRR \
        --input_file_rr_id $TRAITRR \
        --network \$network \
        --output_path ${OUTPUT_DIR}/${TRAIT}/summary/
EOT
)
        #rm $tmpfile
        JOB_STAGE2_STEP3_DEFAULT_ID=$(echo "$JOB_STAGE2_STEP3_DEFAULT" | awk '{print $4}')
    else
        for network in `ls ${MODULEFILEDIR}/`;
        do
            echo "Network: $network"
            network="${network%.*}" # remove extension
            docker run --rm -v $(pwd):$(pwd) -w $(pwd) -u $(id -u):$(id -g) $container_python /bin/bash -c \
                "python3 ./scripts/phase2/dc_summary_statistics_rp.py \
                    --trait $TRAIT \
                    --input_path $OUTPUT_DIR \
                    --or_id $TRAIT \
                    --rr_id ${TRAITRR} \
                    --input_file_rr_id ${TRAITRR} \
                    --network $network \
                    --output_path ${OUTPUT_DIR}/${TRAIT}/summary/"
        done
    fi
}

phase2_step4_default() {
    # (4) identify MEA passing genes
    echo "# STEP 2.4: identify MEA-passing genes"
    if [ "$SINGULARITY" = true ]; then
        tmpfile=$(mktemp --tmpdir="$(pwd)/tmp")
        ls ${MODULEFILEDIR} > $tmpfile
        num_networks=$( wc -l < $tmpfile)
        JOB_STAGE2_STEP4_DEFAULT=$(sbatch --dependency=afterok:"$JOB_STAGE2_STEP3_DEFAULT_ID" <<EOT
#!/bin/bash
#SBATCH -J phase2_step4_default
#SBATCH --array=1-$num_networks
#SBATCH --mem-per-cpu=4G
#SBATCH --cpus-per-task=1
#SBATCH -o ./logs/phase2_step4_default_%A_%a.out
network=\$( sed -n \${SLURM_ARRAY_TASK_ID}p $tmpfile )
network="\${network%.*}" # remove extension
echo "Network: \$network"
singularity exec --no-home -B $(pwd):$(pwd) --pwd $(pwd) $container_python \
    python3 ./scripts/phase2/dc_identify_mea_passing_genes.py \
        --trait $TRAIT \
        --geneset_input $PVALFILEDIR\
        --FDR_threshold $FDR_THRESHOLD \
        --percentile_threshold $PERCENTILE_THRESHOLD \
        --network \$network \
        --input_path ${OUTPUT_DIR}/${TRAIT}
EOT
)
        #rm $tmpfile
        JOB_STAGE2_STEP4_DEFAULT_ID=$(echo "$JOB_STAGE2_STEP4_DEFAULT" | awk '{print $4}')
    else
        for network in `ls ${MODULEFILEDIR}/`;
        do
            echo "Network: $network"
            network="${network%.*}" # remove extension
            docker run --rm -v $(pwd):$(pwd) -w $(pwd) -u $(id -u):$(id -g) $container_python /bin/bash -c \
                "python3 ./scripts/phase2/dc_identify_mea_passing_genes.py \
                    --trait $TRAIT \
                    --geneset_input $PVALFILEDIR\
                    --FDR_threshold $FDR_THRESHOLD \
                    --percentile_threshold $PERCENTILE_THRESHOLD \
                    --network $network \
                    --input_path ${OUTPUT_DIR}/${TRAIT}"
        done
    fi
}

phase2_step1_alternate() {

    # (1) generate background gene sets for GO analysis
    echo "# STEP 1: generating background gene sets for GO analysis"
    if [ "$SINGULARITY" = true ]; then
    JOB_STAGE2_STEP1_ALTERNATE=$(sbatch <<EOT
#!/bin/bash
#SBATCH -J phase2_step1_alternate
#SBATCH --mem-per-cpu=4G
#SBATCH --cpus-per-task=1
#SBATCH -o ./logs/phase2_step1_alternate_%J.out
singularity exec --no-home -B $(pwd):$(pwd) --pwd $(pwd) $container_python \
    python3 ./scripts/phase2/dc_fishnet_background_genes.py \
        --genes_filepath $PVALFILEPATHRR \
        --module_filepath $MODULEFILEDIR \
        --output_filepath ${OUTPUT_DIR}/${TRAIT}/
# (1.1) copy background genes to permutation directory
cp -r ${OUTPUT_DIR}/${TRAIT}/background_genes/ ${OUTPUT_DIR}/${TRAITRR}/
EOT
)
        JOB_STAGE2_STEP1_ALTERNATE_ID=$(echo "$JOB_STAGE2_STEP1_ALTERNATE" | awk '{print $4}')
    else
        docker run --rm -v $(pwd):$(pwd) -w $(pwd) -u $(id -u):$(id -g) $container_python /bin/bash -c \
            "python3 ./scripts/phase2/dc_fishnet_background_genes.py \
                --genes_filepath $PVALFILEPATHRR \
                --module_filepath $MODULEFILEDIR \
                --output_filepath ${OUTPUT_DIR}/${TRAIT}/"
        # (1.1) copy background genes to permutation directory
        cp -r ${OUTPUT_DIR}/${TRAIT}/background_genes/ ${OUTPUT_DIR}/${TRAITRR}/
    fi

}

phase2_step2_original_alternate() {

    # (2) Extract and save module genes as individual files for modules that satisfy Bonferroni 0.25
    echo "# STEP 2.1: extract and save modules that satisfy Bonferroni threshold (original run)"
    # (2.1) original run
    if [ "$SINGULARITY" = true ]; then
        JOB_STAGE2_STEP2_ORIGINAL_ALTERNATE=$(sbatch --dependency=afterok:"$JOB_STAGE2_STEP1_ALTERNATE_ID" <<EOT
#!/bin/bash
#SBATCH -J phase2_step2_original_alternate
#SBATCH --mem-per-cpu=4G
#SBATCH --cpus-per-task=1
#SBATCH -o ./logs/phase2_step2_original_alternate_%J.out
singularity exec --no-home -B $(pwd):$(pwd) --pwd $(pwd) $container_python \
    python3 ./scripts/phase2/dc_fishnet_module_genes.py \
        --genes_filepath $PVALFILEPATHRR \
        --module_filepath $MODULEFILEDIR \
        --master_summary_path ${OUTPUT_DIR}/${TRAIT}/ \
        --study $TRAIT
EOT
)
        JOB_STAGE2_STEP2_ORIGINAL_ALTERNATE_ID=$(echo "$JOB_STAGE2_STEP2_ORIGINAL_ALTERNATE" | awk '{print $4}')
    else
        docker run --rm -v $(pwd):$(pwd) -w $(pwd) -u $(id -u):$(id -g) $container_python /bin/bash -c \
            "python3 ./scripts/phase2/dc_fishnet_module_genes.py \
                --genes_filepath $PVALFILEPATHRR \
                --module_filepath $MODULEFILEDIR \
                --master_summary_path ${OUTPUT_DIR}/${TRAIT}/ \
                --study $TRAIT"
    fi
}

phase2_step2_permutation_alternate() {

    # (2) Extract and save module genes as individual files for modules that satisfy Bonferroni 0.25
    echo "# STEP 2.2: extract and save modules that satisfy Bonferroni threshold (permutation run)"
    # (2.2) permutation run
    if [ "$SINGULARITY" = true ]; then
        JOB_STAGE2_STEP2_PERMUTATION_ALTERNATE=$(sbatch --dependency=afterok:"$JOB_STAGE2_STEP1_ALTERNATE_ID" <<EOT
#!/bin/bash
#SBATCH -J phase2_step2_permutation_alternate
#SBATCH --mem-per-cpu=4G
#SBATCH --cpus-per-task=1
#SBATCH -o ./logs/phase2_step2_permutation_alternate_%J.out
singularity exec --no-home -B $(pwd):$(pwd) --pwd $(pwd) $container_python \
    python3 ./scripts/phase2/dc_fishnet_module_genes.py \
        --genes_filepath $PVALFILEPATHRR \
        --module_filepath $MODULEFILEDIR \
        --master_summary_path ${OUTPUT_DIR}/${TRAITRR}/ \
        --study $TRAITRR
EOT
)
        JOB_STAGE2_STEP2_PERMUTATION_ALTERNATE_ID=$(echo "$JOB_STAGE2_STEP2_PERMUTATION_ALTERNATE" | awk '{print $4}')
    else
        docker run --rm -v $(pwd):$(pwd) -w $(pwd) -u $(id -u):$(id -g) $container_python /bin/bash -c \
            "python3 ./scripts/phase2/dc_fishnet_module_genes.py \
                --genes_filepath $PVALFILEPATHRR \
                --module_filepath $MODULEFILEDIR \
                --master_summary_path ${OUTPUT_DIR}/${TRAITRR}/ \
                --study $TRAITRR"
    fi
}

phase2_step3_original_alternate() {

    # (3) Run GO analysis
    echo "# STEP 3.1: running GO analysis (original run)"
    # (3.1) original run
    set +e
    if [ "$SINGULARITY" = true ]; then
        tmpfile=$(mktemp --tmpdir="$(pwd)/tmp")
        ls ${MODULEFILEDIR} > $tmpfile
        num_networks=$( wc -l < $tmpfile)
        JOB_STAGE2_STEP3_ORIGINAL_ALTERNATE=$(sbatch --dependency=afterok:"$JOB_STAGE2_STEP2_ORIGINAL_ALTERNATE_ID" <<EOT
#!/bin/bash
#SBATCH -J phase2_step3_original_alternate
#SBATCH --array=1-$num_networks
#SBATCH --mem-per-cpu=4G
#SBATCH --cpus-per-task=1
#SBATCH -o ./logs/phase2_step3_original_alternate_%A_%a.out
network=\$( sed -n \${SLURM_ARRAY_TASK_ID}p $tmpfile )
network="\${network%.*}" # remove extension
echo "Network: \$network"
singularity exec --no-home -B $(pwd):$(pwd) --pwd $(pwd) $container_R \
    Rscript ./scripts/phase2/dc_ORA_cmd.R \
        --sigModuleDir ${OUTPUT_DIR}/${TRAIT}/enriched_modules/${TRAIT}-\${network}/ \
        --backGroundGenesFile ${OUTPUT_DIR}/${TRAIT}/background_genes/${MODULE_ALGO}-\${network}.txt \
        --summaryRoot ${OUTPUT_DIR}/${TRAIT}/GO_summaries_alternate/ \
        --reportRoot ${OUTPUT_DIR}/${TRAIT}/report_sumamries_alternate/
EOT
)
        #rm $tmpfile
        JOB_STAGE2_STEP3_ORIGINAL_ALTERNATE_ID=$(echo "$JOB_STAGE2_STEP3_ORIGINAL_ALTERNATE" | awk '{print $4}')
    else
        for network in `ls ${MODULEFILEDIR}/`;
        do
            echo "Network: $network"
            network="${network%.*}" # remove extension
            docker run --rm -v $(pwd):$(pwd) -w $(pwd) -u $(id -u):$(id -g) $container_R /bin/bash -c \
                "Rscript ./scripts/phase2/dc_ORA_cmd.R \
                    --sigModuleDir ${OUTPUT_DIR}/${TRAIT}/enriched_modules/${TRAIT}-${network}/ \
                    --backGroundGenesFile ${OUTPUT_DIR}/${TRAIT}/background_genes/${MODULE_ALGO}-${network}.txt \
                    --summaryRoot ${OUTPUT_DIR}/${TRAIT}/GO_summaries_alternate/ \
                    --reportRoot ${OUTPUT_DIR}/${TRAIT}/report_sumamries_alternate/"
        done
    fi
    set -e
}

phase2_step3_permutation_alternate() {

    # (3) Run GO analysis
    echo "# STEP 3.1: running GO analysis (permutation run)"
    # (3.2) permutation run
    set +e
    if [ "$SINGULARITY" = true ]; then
        tmpfile=$(mktemp --tmpdir="$(pwd)/tmp")
        ls ${MODULEFILEDIR} > $tmpfile
        num_networks=$( wc -l < $tmpfile)
        JOB_STAGE2_STEP3_PERMUTATION_ALTERNATE=$(sbatch --dependency=afterok:"$JOB_STAGE2_STEP2_PERMUTATION_ALTERNATE_ID" <<EOT
#!/bin/bash
#SBATCH -J phase2_step3_permutation_alternate
#SBATCH --array=1-$num_networks
#SBATCH --mem-per-cpu=4G
#SBATCH --cpus-per-task=1
#SBATCH -o ./logs/phase2_step3_permutation_alternate_%A_%a.out
network=\$( sed -n \${SLURM_ARRAY_TASK_ID}p $tmpfile )
network="\${network%.*}" # remove extension
echo "Network: \$network"
singularity exec --no-home -B $(pwd):$(pwd) --pwd $(pwd) $container_R \
    Rscript ./scripts/phase2/dc_ORA_cmd.R \
        --sigModuleDir ${OUTPUT_DIR}/${TRAITRR}/enriched_modules/${TRAITRR}-\${network}/ \
        --backGroundGenesFile ${OUTPUT_DIR}/${TRAITRR}/background_genes/${MODULE_ALGO}-\${network}.txt \
        --summaryRoot ${OUTPUT_DIR}/${TRAITRR}/GO_summaries_alternate/ \
        --reportRoot ${OUTPUT_DIR}/${TRAITRR}/report_sumamries_alternate/
EOT
)
        #rm $tmpfile
        JOB_STAGE2_STEP3_PERMUTATION_ALTERNATE_ID=$(echo "$JOB_STAGE2_STEP3_PERMUTATION_ALTERNATE" | awk '{print $4}')
    else
        for network in `ls ${MODULEFILEDIR}/`;
        do
            echo "Network: $network"
            network="${network%.*}" # remove extension
            docker run --rm -v $(pwd):$(pwd) -w $(pwd) -u $(id -u):$(id -g) $container_R /bin/bash -c \
                "Rscript ./scripts/phase2/dc_ORA_cmd.R \
                    --sigModuleDir ${OUTPUT_DIR}/${TRAITRR}/enriched_modules/${TRAITRR}-${network}/ \
                    --backGroundGenesFile ${OUTPUT_DIR}/${TRAITRR}/background_genes/${MODULE_ALGO}-${network}.txt \
                    --summaryRoot ${OUTPUT_DIR}/${TRAITRR}/GO_summaries_alternate/ \
                    --reportRoot ${OUTPUT_DIR}/${TRAITRR}/report_sumamries_alternate/"

        done
    fi
    set -e
}

phase2_step4_alternate() {

    # (4) Generate statistics for original gene-level p-values
    echo "# STEP 4: generate statistics for original gene-level p-values"
    if [ "$SINGULARITY" = true ]; then
        tmpfile=$(mktemp --tmpdir="$(pwd)/tmp")
        ls ${MODULEFILEDIR} > $tmpfile
        num_networks=$( wc -l < $tmpfile)
        JOB_STAGE2_STEP4_ALTERNATE=$(sbatch --dependency=afterany:"$JOB_STAGE2_STEP3_ORIGINAL_ALTERNATE_ID" <<EOT
#!/bin/bash
#SBATCH -J phase2_step4_alternate
#SBATCH --array=1-$num_networks
#SBATCH --mem-per-cpu=4G
#SBATCH --cpus-per-task=1
#SBATCH -o ./logs/phase2_step4_alternate_%A_%a.out
network=\$( sed -n \${SLURM_ARRAY_TASK_ID}p $tmpfile )
network="\${network%.*}" # remove extension
echo "Network: \$network"
singularity exec --no-home -B $(pwd):$(pwd) --pwd $(pwd) $container_python  \
    python3 ./scripts/phase2/dc_generate_or_statistics_alternate.py \
        --gene_set_path ${PVALFILEDIR} \
        --master_summary_path ${OUTPUT_DIR}/${TRAIT}/master_summary_alternate.csv \
        --trait $TRAIT \
        --module_path ${OUTPUT_DIR}/${TRAIT}/enriched_modules/${TRAIT}-\${network}/ \
        --go_path ${OUTPUT_DIR}/${TRAIT}/GO_summaries_alternate/ \
        --study $TRAIT \
        --output_path ${OUTPUT_DIR}/${TRAIT}/results/raw_alternate/ \
        --network \$network
EOT
)
        #rm $tmpfile
        JOB_STAGE2_STEP4_ALTERNATE_ID=$(echo "$JOB_STAGE2_STEP4_ALTERNATE" | awk '{print $4}')
    else
        for network in `ls ${MODULEFILEDIR}/`;
        do
            echo "Network: $network"
            network="${network%.*}" # remove extension
            docker run --rm -v $(pwd):$(pwd) -w $(pwd) -u $(id -u):$(id -g) $container_python /bin/bash -c \
                "python3 ./scripts/phase2/dc_generate_or_statistics_alternate.py \
                    --gene_set_path ${PVALFILEDIR} \
                    --master_summary_path ${OUTPUT_DIR}/${TRAIT}/master_summary_alternate.csv \
                    --trait $TRAIT \
                    --module_path ${OUTPUT_DIR}/${TRAIT}/enriched_modules/${TRAIT}-${network}/ \
                    --go_path ${OUTPUT_DIR}/${TRAIT}/GO_summaries_alternate/ \
                    --study $TRAIT \
                    --output_path ${OUTPUT_DIR}/${TRAIT}/results/raw_alternate/ \
                    --network $network"
        done
    fi
}

create_tmp_threshold_network_pairs_alternate() {
    thresholds=(0.00005 0.0001 0.005 0.01 0.05 0.1 0.15 0.2 0.25)
    modules=( $( ls ./test/ker_based/*.txt ) )
    for f in "${modules[@]}"; do
        base="$(basename "$f" .txt )"
        for t in "${thresholds[@]}"; do
            echo -e "${t}\t${base}"
        done
    done
}

phase2_step5_alternate() {

    # (5) Generate statistics for random permutation runs
    echo "# STEP 5: generate statistics for random permutations"
    tmpfile=$(mktemp --tmpdir="$(pwd)/tmp")
    create_tmp_threshold_network_pairs_alternate > $tmpfile
    if [ "$SINGULARITY" = true ]; then
        num_pairs=$( wc -l < $tmpfile )
        JOB_STAGE2_STEP5_ALTERNATE=$(sbatch --dependency="$JOB_STAGE2_STEP3_PERMUTATION_ALTERNATE_ID" <<EOF
#!/bin/bash
#SBATCH -J phase2_step5_alternate
#SBATCH --array=1-$num_pairs
#SBATCH --mem-per-cpu=4G
#SBATCH --cpus-per-task=1
#SBATCH -o ./logs/phase2_step5_alternate_%A_%a.out
threshold=\$( sed -n \${SLURM_ARRAY_TASK_ID}p $tmpfile | cut -f 1)
network=\$( sed -n \${SLURM_ARRAY_TASK_ID}p $tmpfile | cut -f 2)
echo "Threshold \$threshold, Network: \$network"
singularity exec --no-home -B $(pwd):$(pwd) --pwd $(pwd) $container_python  \
    python3 ./scripts/phase2/dc_generate_rp_statistics_alternate.py \
        --gene_set_path ${OUTPUT_DIR}/RPscores/${TRAITRR}/ \
        --master_summary_path ${OUTPUT_DIR}/${TRAITRR}/master_summary_alternate.csv \
        --trait ${TRAITRR} \
        --module_path ${OUTPUT_DIR}/${TRAITRR}/enriched_modules/${TRAITRR}-\${network}/ \
        --go_path ${OUTPUT_DIR}/${TRAITRR}/GO_summaries_alternate/ \
        --output_path ${OUTPUT_DIR}/${TRAITRR}/results/raw_alternate/ \
        --network \$network \
        --threshold \$threshold
EOF
)
        JOB_STAGE2_STEP5_ALTERNATE_ID=$(echo "$JOB_STAGE2_STEP5_ALTERNATE" | awk '{print $4}')
    else
        while IFS=$'\t' read -r threshold network; do
            echo "Threshold $threshold, Network: $network"
            docker run --rm -v $(pwd):$(pwd) -w $(pwd) -u $(id -u):$(id -g) $container_python /bin/bash -c \
                "python3 ./scripts/phase2/dc_generate_rp_statistics_alternate.py \
                    --gene_set_path ${OUTPUT_DIR}/RPscores/${TRAITRR}/ \
                    --master_summary_path ${OUTPUT_DIR}/${TRAITRR}/master_summary_alternate.csv \
                    --trait ${TRAITRR} \
                    --module_path ${OUTPUT_DIR}/${TRAITRR}/enriched_modules/${TRAITRR}-${network}/ \
                    --go_path ${OUTPUT_DIR}/${TRAITRR}/GO_summaries_alternate/ \
                    --output_path ${OUTPUT_DIR}/${TRAITRR}/results/raw_alternate/ \
                    --network $network \
                    --threshold $threshold"
        done < $tmpfile
    fi
    #rm -rf $tmpfile
}

phase2_step6_alternate() {

    # (6) summarize statistics from original and permutation runs
    echo "# STEP 6: summarize statistics from original and permutation runs"
    if [ "$SINGULARITY" = true ]; then
        tmpfile=$(mktemp --tmpdir="$(pwd)/tmp")
        ls ${MODULEFILEDIR} > $tmpfile
        num_networks=$( wc -l < $tmpfile)
        JOB_STAGE2_STEP6_ALTERNATE=$(sbatch --dependency=afterok:"$JOB_STAGE2_STEP4_ALTERNATE_ID","$JOB_STAGE2_STEP5_ALTERNATE_ID" <<EOF
#!/bin/bash
#SBATCH -J phase2_step6_alternate
#SBATCH --array=1-$num_networks
#SBATCH --mem-per-cpu=4G
#SBATCH --cpus-per-task=1
#SBATCH -o ./logs/phase2_step6_alternate_%A_%a.out
network=\$( sed -n \${SLURM_ARRAY_TASK_ID}p $tmpfile )
network="\${network%.*}" # remove extension
singularity exec --no-home -B $(pwd):$(pwd) --pwd $(pwd) $container_python  \
    python3 ./scripts/phase2/dc_summary_statistics_rp_alternate.py \
        --trait $TRAIT \
        --input_path $OUTPUT_DIR \
        --or_id $TRAIT \
        --rr_id $TRAITRR \
        --input_file_rr_id $TRAITRR \
        --network \$network \
        --output_path ${OUTPUT_DIR}/${TRAIT}/summary_alternate/
EOF
)
        JOB_STAGE2_STEP6_ALTERNATE_ID=$(echo "$JOB_STAGE2_STEP6_ALTERNATE" | awk '{print $4}')
    else
        for network in `ls ${MODULEFILEDIR}/`;
        do
            echo "Network: $network"
            network="${network%.*}" # remove extension
            docker run --rm -v $(pwd):$(pwd) -w $(pwd) -u $(id -u):$(id -g) $container_python /bin/bash -c \
                "python3 ./scripts/phase2/dc_summary_statistics_rp_alternate.py \
                    --trait $TRAIT \
                    --input_path $OUTPUT_DIR \
                    --or_id $TRAIT \
                    --rr_id $TRAITRR \
                    --input_file_rr_id $TRAITRR \
                    --network $network \
                    --output_path ${OUTPUT_DIR}/${TRAIT}/summary_alternate/"
        done
    fi
}

phase2_step7_alternate() {

    # (7) Extract genes that meet FISHNET criteria
    echo "# STEP 7: Extracting FISHNET genes"
    if [ "$SINGULARITY" = true ]; then
        tmpfile=$(mktemp --tmpdir="$(pwd)/tmp")
        ls ${MODULEFILEDIR} > $tmpfile
        num_networks=$( wc -l < $tmpfile)
        JOB_STAGE2_STEP7_ALTERNATE=$(sbatch --dependency=afterok:"$JOB_STAGE2_STEP6_ALTERNATE_ID" <<EOF
#!/bin/bash
#SBATCH -J phase2_step7_alternate
#SBATCH --array=1-$num_networks
#SBATCH --mem-per-cpu=4G
#SBATCH --cpus-per-task=1
#SBATCH -o ./logs/phase2_step7_alternate_%A_%a.out
network=\$( sed -n \${SLURM_ARRAY_TASK_ID}p $tmpfile )
network="\${network%.*}" # remove extension
singularity exec --no-home -B $(pwd):$(pwd) --pwd $(pwd) $container_python  \
    python3 ./scripts/phase2/dc_identify_mea_passing_genes_alternate.py \
        --trait $TRAIT \
        --geneset_input $PVALFILEDIR \
        --FDR_threshold $FDR_THRESHOLD \
        --percentile_threshold $PERCENTILE_THRESHOLD \
        --network \$network \
        --input_path ${OUTPUT_DIR}/${TRAIT}/
EOF
)
        #rm -rf $tmpfile
        JOB_STAGE2_STEP7_ALTERNATE_ID=$(echo "$JOB_STAGE2_STEP7_ALTERNATE" | awk '{print $4}')
    else
        for network in `ls ${MODULEFILEDIR}/`;
        do
            echo "Network: $network"
            network="${network%.*}" # remove extension
            docker run --rm -v $(pwd):$(pwd) -w $(pwd) -u $(id -u):$(id -g) $container_python /bin/bash -c \
                "python3 ./scripts/phase2/dc_identify_mea_passing_genes_alternate.py \
                    --trait $TRAIT \
                    --geneset_input $PVALFILEDIR \
                    --FDR_threshold $FDR_THRESHOLD \
                    --percentile_threshold $PERCENTILE_THRESHOLD \
                    --network $network \
                    --input_path ${OUTPUT_DIR}/${TRAIT}/"
        done
    fi
}

print_test_message() {
    echo "
########################################
##### RUNNING FISHNET ON TEST DATA #####
########################################
"
}

print_phase_message() {
    echo "
###############
### PHASE $1 ###
###############
"
}

print_phase_completion() {
    echo "
########################
### PHASE $1 COMPLETE ###
########################
"
}

print_default_thresholding_message() {
    echo "
##########################
## DEFAULT THRESHOLDING ##
##########################
"
}

print_alternative_thresholding_message() {
    echo "
##############################
## ALTERNATIVE THRESHOLDING ##
##############################
"
}

print_phase1_completion_message() {
    if [ "$SINGULARITY" = true ]; then
    # wait for phase1_step5 to complete
        while squeue -j "$JOB_STAGE1_STEP5_ID" | grep -q "$JOB_STAGE1_STEP5_ID"; do
            sleep 5
        done
    fi
    print_phase_completion 1
}

print_phase2_completion_message() {
    if [ "$SINGULARITY" = true ]; then
    # wait for phase1_step5 to complete
        while squeue -j "$1" | grep -q "$1"; do
            sleep 5
        done
    fi
    print_phase_completion 2
}

nextflow_cleanup() {
    rm -rf .nextflow* work/
}

##############################
### TEST CONFIG ENTRYPOINT ###
##############################
if [ "$TEST_MODE" = true ]; then

    print_test_message

    pull_docker_image

    if [ "$SKIP_STAGE_1" = true ]; then
        echo "Skipping STAGE 1"
    else
        ###############
        ### PHASE 1 ###
        ###############
        print_phase_message 1

        phase1_step1

        phase1_step3

        phase1_step5

        print_phase1_completion_message

        nextflow_cleanup
    fi

    if [ "$SKIP_STAGE_2" = true ]; then
        echo "Skipping STAGE 2"
    else
        ###############
        ### PHASE 2 ###
        ###############

        print_phase_message 2

        phase2_step0

        if [ "$THRESHOLDING_MODE" = "$THRESHOLDING_MODE_DEFAULT" ]; then
            ##########################
            ## DEFAULT THRESHOLDING ##
            ##########################

            print_default_thresholding_message

            phase2_step1_default

            phase2_step2_default

            phase2_step3_default

            phase2_step4_default

            print_phase2_completion_message $JOB_STAGE2_STEP4_DEFAULT_ID

        else
            ##############################
            ## ALTERNATIVE THRESHOLDING ##
            ##############################
            print_alternative_thresholding_message

            phase2_step1_alternate

            phase2_step2_original_alternate

            phase2_step2_permutation_alternate

            phase2_step3_original_alternate

            phase2_step3_permutation_alternate

            phase2_step4_alternate

            phase2_step5_alternate

            phase2_step6_alternate

            phase2_step7_alternate

            print_phase2_completion_message $JOB_STAGE2_STEP7_ALTERNATE_ID
        fi
    fi
    # TODO: reverse the ranks of the original p-values SS --> run OR part of stage 1 --> filter for sig modules
else
    echo "FISHENT CURRENTLY ONLY SUPPORTS the --test FLAG"
fi
echo "### FISHNET COMPLETE ###"
