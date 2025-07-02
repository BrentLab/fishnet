#!/bin/bash -ue


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
    --conda
        Configures (phase2_step2_default) to run using a conda environment in SLURM (much faster than singularity)
        Default: false (runs phase2_step2_default using singularity)
    --conda-env <conda_environment_name>
        Specify a conda environment to use/create
        Default: fishnet (creates a conda environment named fishnet)
    --FDR-threshold <float>
        Specify a custom FDR threshold cutoff
        Default: 0.05
    --percentile-threshold <float>
        Specify a custom percentile threshold cutoff
        Default: 99
    --modules <path/to/modules/directory/>
        Path to directory containing network modules.
        Network module files must be tab-delimited .txt files
        (e.g. data/modules/ker_based/)
    --study <path/to/study/directory>
        Path to directory containing trait subdirectories with input summary statistics files.
        Runs FISHNET for all traits in this directory.
        Summary statistics files must be CSV files with colnames "Genes" and "p_vals".
        Filename must not include any '_', '-', or '.' characters.
        (e.g. --study data/pvals/maleWC/)
    --study-random <path/to/random/permutation/study/directory>
        Path to the directory containing uniformly distributed p-values for random permutations.
        (e.g. --study data/pvals/maleWCRR/)
    --num-permutations <integer>
        Configures the number of permutations (only relevant with --random)
        Default: 10
EOF
}

# default parameters
TEST_MODE=false
SKIP_STAGE_1=false
SKIP_STAGE_2=false
THRESHOLDING_MODE_DEFAULT="default"
THRESHOLDING_MODE_ALTERNATIVE="alternative"
THRESHOLDING_MODE=$THRESHOLDING_MODE_DEFAULT
SINGULARITY=false
CONDA=false
CONDA_ENV_DEFAULT="fishnet"
CONTAINER_RUNTIME="DOCKER"
NXF_CONFIG_DEFAULT_DOCKER="./conf/fishnet.config"
NXF_CONFIG_DEFAULT_SINGULARITY="./conf/fishnet_slurm.config"
NXF_CONFIG="$NXF_CONFIG_DEFAULT_DOCKER"
conda_env_provided=false
nxf_config_provided=false
RESULTS_PATH=$( readlink -f "./results/" )
GENECOLNAME="Genes"
PVALCOLNAME="p_vals"
BONFERRONI_ALPHA=0.05 # for phase 1 nextflow scripts

FDR_THRESHOLD=0.05
PERCENTILE_THRESHOLD=99
NUM_PERMUTATIONS=10
STUDY_PATH="NONE"
STUDY_RANDOM_PATH="NONE"
STUDY="NONE"
STUDY_RANDOM="NONE"


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
        --conda)
            CONDA=true
            shift
            ;;
        --conda_env)
            if [[ -n "$2" && ! "$2" =~ ^- ]]; then
                CONDA_ENV="$2"
                conda_env_provided=true
                shift 2
            else
                echo "ERROR: --conda_env requires a path argument."
                exit 1
            fi
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
        --study)
            # make sure we have a value and not another flag
            if [[ -n "$2" && ! "$2" =~ ^- && -d "$2" ]]; then
                STUDY_PATH="$2"
                shift 2
            else
                echo "ERROR: --study requires a valid directory path.."
                exit 1
            fi
            ;;
        --modules)
            # make sure we have a value and not another flag
            if [[ -n "$2" && ! "$2" =~ ^- ]]; then
                MODULE_FILE_PATH="$2"
                shift 2
            else
                echo "ERROR: --modules requires a string path argument."
                exit 1
            fi
            ;;
        --study-random)
            # make sure we have a value and not another flag
            if [[ -n "$2" && ! "$2" =~ ^- && -d "$2" ]]; then
                STUDY_RANDOM_PATH="$2"
                shift 2
            else
                echo "ERROR: --study-random requires a valid directory path.."
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

# check for singularity
if [ "$SINGULARITY" = true ]; then
    # if singularity requested, but user did not specify --nxf_config
    if [ "$nxf_config_provided" = false ]; then
        NXF_CONFIG="$NXF_CONFIG_DEFAULT_SINGULARITY"
    fi
fi

# check for conda
if [ "$CONDA" = true ]; then
    # if conda requested, but user did not specify --conda_env
    if [ "$conda_env_provided" = false ]; then
        CONDA_ENV="$CONDA_ENV_DEFAULT"
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
if [ "$CONDA" = true ]; then
    conda --version
fi
echo " - nextflow config: $NXF_CONFIG"


### set test parameters ###
if [ "$TEST_MODE" = true ]; then
    STUDY_PATH="./data/pvals/dreamGWASORKBtest"
    STUDY_RANDOM_PATH="./data/pvals/dreamGWASRRKBtest"
    MODULE_FILE_PATH="./data/modules/ker_based/"
else
    # check for required input parameters
    # input trait file
    if [ ! -d "$STUDY_PATH" ]; then
        echo "--study $STUDY_PATH NOT FOUND"
        exit 1
    fi
    if [ ! -d "$STUDY_RANDOM_PATH" ]; then
        echo "--study $STUDY_RANDOM_PATH NOT FOUND"
        exit 1
    fi
    # input modules directory
    if [ ! -d "$MODULE_FILE_PATH" ]; then
        echo "--modules $MODULE_FILE_PATH DIRECTORY NOT FOUND"
        exit 1
    fi
fi

# TODO: allow this to run without specifying --study-random
#       in which case, should generate uniformly distributed p-values for each study trait


# ensure absolutepaths for nextflow
STUDY_PATH=$( readlink -f "$STUDY_PATH" )
STUDY=$( basename $STUDY_PATH )
STUDY_RANDOM_PATH=$( readlink -f "$STUDY_RANDOM_PATH" )
STUDY_RANDOM=$( basename $STUDY_RANDOM_PATH )
MODULE_FILE_PATH=$( readlink -f "$MODULE_FILE_PATH" )

# check and list traits in input study path
TRAITDIRS=($(find "$STUDY_PATH" -mindepth 1 -maxdepth 1 -type d))
NUM_TRAITS=${#TRAITDIRS[@]}
echo "# Found ${NUM_TRAITS} traits"
for trait in "${TRAITDIRS[@]}"; do
    trait=$( basename $trait )
    echo "> $trait"
done

RESULTS_PATH_OR="${RESULTS_PATH}/${STUDY}"
RESULTS_PATH_RR="${RESULTS_PATH}/${STUDY_RANDOM}"

# record number of module files
NUM_MODULE_FILES=$( ls -1 ${MODULE_FILE_PATH}/*.txt 2>/dev/null | wc -l)
echo "# FOUND ${NUM_MODULE_FILES} module files"

# number of genes for random permutation
NUMTESTS_RANDOM=$(( $(wc -l < "${STUDY_RANDOM_PATH}/${STUDY_RANDOM}.csv")  - 1 ))

### export parameters ###
export STUDY_PATH
export STUDY
export STUDY_RANDOM_PATH
export STUDY_RANDOM
export NUM_TRAITS
export RANDOM_PERMUTATION
export NUM_PERMUTATIONS
export NUM_MODULE_FILES
export PVALFILEDIR
export PVALFILEPATH
export PVALFILEPATHRR
export MODULE_ALGO
export MODULE_FILE_PATH
export NUMTESTS_RANDOM
export GENECOLNAME
export PVALCOLNAME
export BONFERRONI_ALPHA
export RESULTS_PATH
export RESULTS_PATH_OR
export RESULTS_PATH_RR
export FDR_THRESHOLD
export PERCENTILE_THRESHOLD
export NXF_CONFIG

### list of containers ###
# contains all python dependencies for fishnet
#   TODO: create single container with all python dependencies (include statsmodels)
#   TODO: add to biocontainers 
export container_python="docker://jungwooseok/dc_rp_genes:1.0"
export container_R="docker://jungwooseok/r-webgestaltr:1.0"
export CONDA_ENV

#########################
### PHASE 1 FUNCTIONS ###
#########################
pull_docker_image() {

    # boolean whether to pull or not (for job dependencies)
    PULL_PYTHON_CONTAINER=false
    PULL_R_CONTAINER=false
    JOB_PULL_SINGULARITY_PYTHON_ID=false
    JOB_PULL_SINGULARITY_R_ID=false

    # pull docker images as singularity .sif files
    if [ "$SINGULARITY" = true ]; then
        # create dir to store .sif files
        if [ ! -d "$(pwd)/singularity_images/" ]; then
            mkdir "$(pwd)/singularity_images"
        fi
        # create tmp directory
        if [ ! -d "$(pwd)/tmp" ]; then
            mkdir "$(pwd)/tmp"
        fi

        container_python_docker=$container_python
        container_R_docker=$container_R
        export container_python="$(pwd)/singularity_images/dc_rp_genes.sif"
        export container_R="$(pwd)/singularity_images/r_webgestaltr.sif"


        # pull python container if not exist
        if [ ! -f $container_python ]; then
            PULL_PYTHON_CONTAINER=true
            JOB_PULL_SINGULARITY_PYTHON=$(sbatch <<EOT
#!/bin/bash
#SBATCH -J pull_singularity_container_python
#SBATCH --mem=4G
#SBATCH -o ./logs/pull_singularity_container_python_%J.out
singularity pull $container_python $container_python_docker
EOT
)
            JOB_PULL_SINGULARITY_PYTHON_ID=$( echo "$JOB_PULL_SINGULARITY_PYTHON" | awk '{print $4}')
        fi

        # pull R container if not exist
        if [ ! -f $container_R ]; then
            PULL_R_CONTAINER=true
            JOB_PULL_SINGULARITY_R=$(sbatch <<EOT
#!/bin/bash
#SBATCH -J pull_singularity_container_R
#SBATCH --mem=4G
#SBATCH -o ./logs/pull_singularity_container_R_%J.out
singularity pull $container_R $container_R_docker
EOT
)
            JOB_PULL_SINGULARITY_R_ID=$( echo "$JOB_PULL_SINGULARITY_R" | awk '{print $4}')
        fi
    fi

    # check for conda environment, create if not exist
    if [ "$CONDA" = true ]; then
        if conda env list | awk '{print $1}' | grep -Fxq "$CONDA_ENV"; then
            echo "Conda environment $CONDA_ENV found"
        else
            echo "Conda environment $CONDA_ENV not found...creating"
            conda env create -f conf/fishnet_conda_environment.yml
            echo "done"
        fi
    fi

    # TODO: pull nextflow singuarity images prior to run (TEMPORARY BUG FIX)
    echo "pulling singularity images for nextflow (temp bug fix)"
    if [ ! -f "${SINGULARITY_CACHEDIR}/depot.galaxyproject.org-singularity-mulled-v2-9d836da785124bb367cbe6fbfc00dddd2107a4da-b033d6a4ea3a42a6f5121a82b262800f1219b382-0.img" ]; then
        singularity pull "${SINGULARITY_CACHEDIR}/depot.galaxyproject.org-singularity-mulled-v2-9d836da785124bb367cbe6fbfc00dddd2107a4da-b033d6a4ea3a42a6f5121a82b262800f1219b382-0.img" https://depot.galaxyproject.org/singularity/mulled-v2-9d836da785124bb367cbe6fbfc00dddd2107a4da:b033d6a4ea3a42a6f5121a82b262800f1219b382-0
    fi
    if [ ! -f "${SINGULARITY_CACHEDIR}/depot.galaxyproject.org-singularity-pandas:1.1.5.img" ]; then
        singularity pull "${SINGULARITY_CACHEDIR}/depot.galaxyproject.org-singularity-pandas:1.1.5.img" https://depot.galaxyproject.org/singularity/pandas:1.1.5
    fi
    if [ ! -f "${SINGULARITY_CACHEDIR}/jungwooseok-mea_pascal-1.1.img" ]; then
        singularity pull "${SINGULARITY_CACHEDIR}/jungwooseok-mea_pascal-1.1.img" docker://jungwooseok/mea_pascal:1.1
    fi

    export PULL_PYTHON_CONTAINER
    export PULL_R_CONTAINER
    export JOB_PULL_SINGULARITY_PYTHON_ID
    export JOB_PULL_SINGULARITY_R_ID
}


phase1_step1() {

    # (1) nextflow (original)
    echo "# STEP 1.1: executing Nextflow MEA pipeline on original run"

    # MULTI-TRAIT: generate temporary SBATCH array job file
    tmpfile=$(mktemp --tmpdir="$(pwd)/tmp")
    find "$STUDY_PATH" -mindepth 1 -maxdepth 1 -type d > $tmpfile

    # run nextflow
    if [ "$SINGULARITY" = true ]; then
        if [ "$PULL_PYTHON_CONTAINER" = true ]; then
            if [ "$PULL_R_CONTAINER" = true ]; then
                JOB_STAGE1_STEP1=$(sbatch --dependency=afterok:"$JOB_PULL_SINGULARITY_PYTHON_ID":"$JOB_PULL_SINGULARITY_R_ID" --array=1-${NUM_TRAITS} ./scripts/phase1/phase1_step1_multi.sh $(pwd) $tmpfile )
            else
                JOB_STAGE1_STEP1=$(sbatch --dependency=afterok:"$JOB_PULL_SINGULARITY_PYTHON_ID"  --array=1-${NUM_TRAITS} ./scripts/phase1/phase1_step1_multi.sh $(pwd) $tmpfile)
            fi
        elif [ "$PULL_R_CONTAINER" = true ]; then
                JOB_STAGE1_STEP1=$(sbatch --dependency=afterok:"$JOB_PULL_SINGULARITY_R_ID" --array=1-${NUM_TRAITS} ./scripts/phase1/phase1_step1_multi.sh $(pwd) $tmpfile)
        else
            JOB_STAGE1_STEP1=$(sbatch --array=1-${NUM_TRAITS} ./scripts/phase1/phase1_step1_multi.sh $(pwd) $tmpfile)
        fi
        JOB_STAGE1_STEP1_ID=$(echo "$JOB_STAGE1_STEP1" | awk '{print $4}')
    else
        ./scripts/phase1/phase1_step1_multi.sh $(pwd)
    fi
}

phase1_step2() {

    # (2) compile results (original)
    echo "# STEP 1.2: compiling permutation results"
    SUMMARIES_PATH_ORIGINAL="${RESULTS_PATH_OR}/masterSummaries/summaries/"
    if [ "$CONDA" = true ]; then
        JOB_STAGE1_STEP2_ORIGINAL=$(sbatch --dependency=afterok:"$JOB_STAGE1_STEP1_ID" <<EOT
#!/bin/bash
#SBATCH -J phase1_step2_original_${STUDY}
#SBATCH -o ./logs/phase1_step2_original_%J.out
source activate $CONDA_ENV
python3 ./scripts/phase1/compile_results.py \
    --dirPath $SUMMARIES_PATH_ORIGINAL \
    --identifier $STUDY \
    --output $RESULTS_PATH_OR
EOT
)
        JOB_STAGE1_STEP2_ORIGINAL_ID=$(echo "$JOB_STAGE1_STEP2_ORIGINAL" | awk '{print $4}')
    elif [ "$SINGULARITY" = true ]; then
        JOB_STAGE1_STEP2_ORIGINAL=$(sbatch --dependency=afterok:"$JOB_STAGE1_STEP1_ID" <<EOT
#!/bin/bash
#SBATCH -J phase1_step2_original
#SBATCH -o ./logs/phase1_step2_original_%J.out
singularity exec --no-home -B $(pwd):$(pwd) --pwd $(pwd) $container_python \
python3 ./scripts/phase1/compile_results.py \
    --dirPath $SUMMARIES_PATH_ORIGINAL \
    --identifier $STUDY \
    --output $RESULTS_PATH_OR
EOT
)
        JOB_STAGE1_STEP2_ORIGINAL_ID=$(echo "$JOB_STAGE1_STEP2_ORIGINAL" | awk '{print $4}')
    else
        docker run --rm -v $(pwd):$(pwd) -w $(pwd) -u $(id -u):$(id -g) $container_python /bin/bash -c \
            "python3 ./scripts/phase1/compile_results.py \
                --dirPath $SUMMARIES_PATH_ORIGINAL \
                --identifier $TRAIT \
                --output $RESULTS_PATH"
    fi
}

phase1_step3() {

    # TODO: generate uniform p-values if --study-random not specified

    # (3) nextflow random permutation run
    echo "# STEP 1.3: executing Nextflow MEA pipeline on random permutations"
    if [ "$SINGULARITY" = true ]; then
        JOB_STAGE1_STEP3=$(sbatch --dependency=afterok:"$JOB_STAGE1_STEP1_ID" ./scripts/phase1/phase1_step3_multi.sh $(pwd))
        JOB_STAGE1_STEP3_ID=$(echo "$JOB_STAGE1_STEP3" | awk '{print $4}')
    else
        ./scripts/phase1/phase1_step3_multi.sh $(pwd)
    fi
}

phase1_step4() {

    # (4)
    echo "# STEP 1.4: compiling permutation results"
    SUMMARIES_PATH_PERMUTATION="${RESULTS_PATH_RR}/masterSummaries/summaries/"
    # dynamically set memory allocation based on number of modules and number of permutations
    # currently: 2 MB * N(modules) * N(permutations)
    MEM_ALLOCATION=$(( 2 * $NUM_MODULE_FILES * $NUM_PERMUTATIONS ))
    if [ "$CONDA" = true ]; then
        JOB_STAGE1_STEP4_PERMUTATION=$(sbatch --dependency=afterok:"$JOB_STAGE1_STEP3_ID" <<EOT
#!/bin/bash
#SBATCH -J phase1_step4_permutation_${STUDY_RANDOM}
#SBATCH --mem ${MEM_ALLOCATION}M
#SBATCH -o ./logs/phase1_step4_permutation_%J.out
source activate $CONDA_ENV
python3 ./scripts/phase1/compile_results.py \
    --dirPath $SUMMARIES_PATH_PERMUTATION \
    --identifier $STUDY_RANDOM \
    --output $RESULTS_PATH_RR
EOT
)
        JOB_STAGE1_STEP4_PERMUTATION_ID=$(echo "$JOB_STAGE1_STEP4_PERMUTATION" | awk '{print $4}')
    elif [ "$SINGULARITY" = true ]; then
        JOB_STAGE1_STEP4_PERMUTATION=$(sbatch --dependency=afterok:"$JOB_STAGE1_STEP3_ID" <<EOT
#!/bin/bash
#SBATCH -J phase1_step4_permutation
#SBATCH --mem ${MEM_ALLOCATION}M
#SBATCH -o ./logs/phase1_step4_permutation_%J.out
singularity exec --no-home -B $(pwd):$(pwd) --pwd $(pwd) $container_python \
python3 ./scripts/phase1/compile_results.py \
    --dirPath $SUMMARIES_PATH_PERMUTATION \
    --identifier $STUDY_RANDOM \
    --output $RESULTS_PATH_RR
EOT
)
        JOB_STAGE1_STEP4_PERMUTATION_ID=$(echo "$JOB_STAGE1_STEP4_PERMUTATION" | awk '{print $4}')
    else
        docker run --rm -v $(pwd):$(pwd) -w $(pwd) -u $(id -u):$(id -g) $container_python /bin/bash -c \
            "python3 ./scripts/phase1/compile_results.py \
                --dirPath $SUMMARIES_PATH_PERMUTATION \
                --identifier $STUDY_RANDOM \
                --output $RESULTS_PATH_RR"
    fi
}


#########################
### PHASE 2 FUNCTIONS ###
#########################
phase2_step0() {
    # (0) filter the summary file for original/permuted runs
    echo "# STEP 2.0: filtering + parsing master_summary.csv files"
    cp "${RESULTS_PATH_OR}/master_summary_${STUDY}.csv" "${RESULTS_PATH_OR}/master_summary.csv"
    ( head -n 1 "${RESULTS_PATH_OR}/master_summary.csv"; grep 'True' "${RESULTS_PATH_OR}/master_summary.csv" ) > "${RESULTS_PATH_OR}/master_summary_filtered.csv"
    cut -d ',' -f 1-8 "${RESULTS_PATH_OR}/master_summary_filtered.csv" > "${RESULTS_PATH_OR}/master_summary_filtered_parsed.csv"

    cp "${RESULTS_PATH_RR}/master_summary_${STUDY_RANDOM}.csv" "${RESULTS_PATH_RR}/master_summary.csv"
    ( head -n 1 "${RESULTS_PATH_RR}/master_summary.csv"; grep 'True' "${RESULTS_PATH_RR}/master_summary.csv" ) > "${RESULTS_PATH_RR}/master_summary_filtered.csv"
    cut -d ',' -f 1-8 "${RESULTS_PATH_RR}/master_summary_filtered.csv" > "${RESULTS_PATH_RR}/master_summary_filtered_parsed.csv"
}

# generates tab-delimited file with all pairs
# of module networks and traits for array job
generate_network_trait_combinations() {
    local networks_dir="$1"
    local study_dir="$2"
    local output_file="$3"

    # clear output file
    > "$output_file"

    for network_file in "$networks_dir"/*.txt; do
        network_name=$(basename "$network_file" .txt)
        for trait in "$study_dir"/*/; do
            trait_name=$(basename "$trait")
            echo -e "${network_name}\t${trait_name}" >> "$output_file"
        done
    done
}

phase2_step1_default() {
    ## (1) generate statistics for original run
    echo "# STEP 2.1: generating statistics for original run"

    tmpfile=$(mktemp --tmpdir="$(pwd)/tmp")
    generate_network_trait_combinations ${MODULE_FILE_PATH} ${STUDY_PATH} ${tmpfile}
    NUM_ARRAY_JOBS=$( wc -l < $tmpfile)

    if [ "$SINGULARITY" = true ]; then
        if [ "$CONDA" = true ]; then
            echo "RUNNING WITH CONDA ENVIRONMENT ($CONDA_ENV)"
            JOB_STAGE2_STEP1_DEFAULT=$(sbatch <<EOT
#!/bin/bash
#SBATCH -J phase2_step1_default_${STUDY}
#SBATCH --mem-per-cpu=4G
#SBATCH --array=1-$NUM_ARRAY_JOBS
#SBATCH -o ./logs/phase2_step1_default_%A_%a.out
NETWORK=\$( sed -n \${SLURM_ARRAY_TASK_ID}p $tmpfile | cut -f1 )
TRAIT=\$( sed -n \${SLURM_ARRAY_TASK_ID}p $tmpfile | cut -f2 )
PVALFILEPATH="${STUDY_PATH}/\${TRAIT}/"
echo "Network: \$NETWORK"

source activate $CONDA_ENV

python3 ./scripts/phase2/dc_generate_or_statistics.py \
    --gene_set_path \$PVALFILEPATH \
    --master_summary_path ${RESULTS_PATH_OR}/master_summary_filtered_parsed.csv \
    --trait \$TRAIT  \
    --module_path ${MODULE_FILE_PATH}/\${NETWORK}.txt \
    --go_path ${RESULTS_PATH_OR}/GO_summaries/\${TRAIT}/ \
    --study $STUDY \
    --output_path ${RESULTS_PATH_OR}/results/raw/ \
    --network \$NETWORK
EOT
)
        else
            echo "RUNNING WITH SINGULARITY"
            JOB_STAGE2_STEP1_DEFAULT=$(sbatch <<EOT
#!/bin/bash
#SBATCH -J phase2_step1_default_${STUDY}
#SBATCH --mem-per-cpu=4G
#SBATCH --array=1-$NUM_ARRAY_JOBS
#SBATCH -o ./logs/phase2_step1_default_%A_%a.out
NETWORK=\$( sed -n \${SLURM_ARRAY_TASK_ID}p $tmpfile | cut -f1 )
TRAIT=\$( sed -n \${SLURM_ARRAY_TASK_ID}p $tmpfile | cut -f2 )
PVALFILEPATH="${STUDY_PATH}/\${TRAIT}/"
echo "Network: \$NETWORK"

singularity exec --no-home -B $(pwd):$(pwd) --pwd $(pwd) $container_python \
    python3 ./scripts/phase2/dc_generate_or_statistics.py \
        --gene_set_path \$PVALFILEPATH \
        --master_summary_path ${RESULTS_PATH_OR}/master_summary_filtered_parsed.csv \
        --trait \$TRAIT  \
        --module_path ${MODULE_FILE_PATH}/\${NETWORK}.txt \
        --go_path ${RESULTS_PATH_OR}/GO_summaries/\${TRAIT}/ \
        --study $STUDY \
        --output_path ${RESULTS_PATH_OR}/results/raw/ \
        --network \$NETWORK
EOT
)
        fi
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

phase2_step2_default() {

    # (2.2) generate statistics for permutation run
    echo "# STEP 2.2: generating statistics for permutation runs"

    # generates tab-delimited file with all pairs of
    # module newtorks and thresholds for array job
    create_tmp_threshold_network_pairs_default() {
        local output_file="$1"

        # clear output file
        > "$output_file"

        # 1. take 25% of number of genes form original p-values input file
        local ROUNDED_25=$(( (25 * NUMTESTS_RANDOM + 50) / 100 ))
        # 2. range 10..{1} take nearest multiple of 10
        local MAX_THRESHOLD=$(( ROUNDED_25 - (ROUNDED_25 % 10) ))
        local THRESHOLDS=()
        for (( i=10; i<=MAX_THRESHOLD; i+=10 )); do
            THRESHOLDS+=( "$i" )
        done

        local MODULES=( $(ls ${MODULE_FILE_PATH}/*.txt) )
        for f in "${MODULES[@]}"; do
            BASE="$(basename "$f" .txt )"
            for t in "${THRESHOLDS[@]}"; do
                echo -e "${t}\t${BASE}" >> "$output_file"
            done
        done
    }

    GENES_RPSCORES_FILEDIR="${RESULTS_PATH_RR}/RPscores/${STUDY_RANDOM}"
    tmpfile=$(mktemp --tmpdir="$(pwd)/tmp")
    create_tmp_threshold_network_pairs_default $tmpfile

    if [ "$SINGULARITY" = true ]; then
        NUM_PAIRS=$( wc -l < $tmpfile )
        if [ "$CONDA" = true ]; then
            echo "RUNNING WITH CONDA ENVIRONMENT ($CONDA_ENV)"
            JOB_STAGE2_STEP2_DEFAULT=$(sbatch --dependency=afterok:"$JOB_STAGE2_STEP1_DEFAULT_ID" <<EOT
#!/bin/bash
#SBATCH -J phase2_step2_default_${STUDY_RANDOM}
#SBATCH --array=1-$NUM_PAIRS
#SBATCH --mem-per-cpu=4G
#SBATCH --cpus-per-task=1
#SBATCH -o ./logs/phase2_step2_default_%A_%a.out
NETWORK=\$( sed -n \${SLURM_ARRAY_TASK_ID}p $tmpfile | cut -f 2 )
THRESHOLD=\$( sed -n \${SLURM_ARRAY_TASK_ID}p $tmpfile | cut -f 1 )
echo \$NETWORK
echo \$THRESHOLD

source activate $CONDA_ENV

python3 ./scripts/phase2/dc_generate_rp_statistics.py \
    --gene_set_path $GENES_RPSCORES_FILEDIR \
    --master_summary_path ${RESULTS_PATH_RR}/master_summary_filtered_parsed.csv \
    --trait ${STUDY_RANDOM} \
    --module_path ${MODULE_FILE_PATH}/\${NETWORK}.txt \
    --go_path ${RESULTS_PATH_RR}/GO_summaries/${STUDY_RANDOM}/ \
    --output_path ${RESULTS_PATH_RR}/results/raw/ \
    --network \$NETWORK \
    --threshold \$THRESHOLD \
    --num_permutations ${NUM_PERMUTATIONS}
EOT
)
        else
            echo "RUNNING WITH SINGULARITY"
            JOB_STAGE2_STEP2_DEFAULT=$(sbatch --dependency=afterok:"$JOB_STAGE2_STEP1_DEFAULT_ID" <<EOT
#!/bin/bash
#SBATCH -J phase2_step2_default_${STUDY_RANDOM}
#SBATCH --array=1-$NUM_PAIRS
#SBATCH --mem-per-cpu=4G
#SBATCH --cpus-per-task=1
#SBATCH -o ./logs/phase2_step2_default_%A_%a.out
NETWORK=\$( sed -n \${SLURM_ARRAY_TASK_ID}p $tmpfile | cut -f 2 )
THRESHOLD=\$( sed -n \${SLURM_ARRAY_TASK_ID}p $tmpfile | cut -f 1 )
echo \$NETWORK
echo \$THRESHOLD

singularity exec --no-home -B $(pwd):$(pwd) --pwd $(pwd) $container_python \
    python3 ./scripts/phase2/dc_generate_rp_statistics.py \
        --gene_set_path $GENES_RPSCORES_FILEDIR \
        --master_summary_path ${RESULTS_PATH_RR}/master_summary_filtered_parsed.csv \
        --trait ${STUDY_RANDOM} \
        --module_path ${MODULE_FILE_PATH}/\${NETWORK}.txt \
        --go_path ${RESULTS_PATH_RR}/GO_summaries/${STUDY_RANDOM}/ \
        --output_path ${RESULTS_PATH_RR}/results/raw/ \
        --network \$NETWORK \
        --threshold \$THRESHOLD \
        --num_permutations ${NUM_PERMUTATIONS}
EOT
)
        fi
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

    tmpfile=$(mktemp --tmpdir="$(pwd)/tmp")
    generate_network_trait_combinations ${MODULE_FILE_PATH} ${STUDY_PATH} ${tmpfile}
    NUM_ARRAY_JOBS=$( wc -l < $tmpfile)

    if [ "$SINGULARITY" = true ]; then
        if [ "$CONDA" = true ]; then
            echo "RUNNING WITH CONDA ENVIRONMENT ($CONDA_ENV)"
            JOB_STAGE2_STEP3_DEFAULT=$(sbatch --dependency=afterok:"$JOB_STAGE2_STEP2_DEFAULT_ID" <<EOT
#!/bin/bash
#SBATCH -J phase2_step3_default_${STUDY}
#SBATCH --array=1-$NUM_ARRAY_JOBS
#SBATCH --mem-per-cpu=4G
#SBATCH --cpus-per-task=1
#SBATCH -o ./logs/phase2_step3_default_%A_%a.out
NETWORK=\$( sed -n \${SLURM_ARRAY_TASK_ID}p $tmpfile | cut -f1 )
TRAIT=\$( sed -n \${SLURM_ARRAY_TASK_ID}p $tmpfile | cut -f2 )
NETWORK="\${NETWORK%.*}" # remove extension
echo "Network: \$NETWORK"

source activate $CONDA_ENV

python3 ./scripts/phase2/dc_summary_statistics_rp.py \
    --trait \$TRAIT \
    --input_path ${RESULTS_PATH} \
    --or_id ${STUDY} \
    --rr_id ${STUDY_RANDOM} \
    --input_file_rr_id ${STUDY_RANDOM} \
    --network \$NETWORK \
    --output_path ${RESULTS_PATH_OR}/summary/ \
    --num_permutations ${NUM_PERMUTATIONS}
EOT
)
        else
            echo "RUNNING WITH SINGULARITY"
            JOB_STAGE2_STEP3_DEFAULT=$(sbatch --dependency=afterok:"$JOB_STAGE2_STEP2_DEFAULT_ID" <<EOT
#!/bin/bash
#SBATCH -J phase2_step3_default_${STUDY}
#SBATCH --array=1-$NUM_ARRAY_JOBS
#SBATCH --mem-per-cpu=4G
#SBATCH --cpus-per-task=1
#SBATCH -o ./logs/phase2_step3_default_%A_%a.out
NETWORK=\$( sed -n \${SLURM_ARRAY_TASK_ID}p $tmpfile | cut -f1 )
TRAIT=\$( sed -n \${SLURM_ARRAY_TASK_ID}p $tmpfile | cut -f2 )
NETWORK="\${NETWORK%.*}" # remove extension
echo "Network: \$NETWORK"

singularity exec --no-home -B $(pwd):$(pwd) --pwd $(pwd) $container_python \
    python3 ./scripts/phase2/dc_summary_statistics_rp.py \
        --trait \$TRAIT \
        --input_path ${RESULTS_PATH} \
        --or_id ${STUDY} \
        --rr_id ${STUDY_RANDOM} \
        --input_file_rr_id ${STUDY_RANDOM} \
        --network \$NETWORK \
        --output_path ${RESULTS_PATH_OR}/summary/ \
        --num_permutations ${NUM_PERMUTATIONS}
EOT
)
        fi
        # rm $tmpfile
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

    tmpfile=$(mktemp --tmpdir="$(pwd)/tmp")
    generate_network_trait_combinations ${MODULE_FILE_PATH} ${STUDY_PATH} ${tmpfile}
    NUM_ARRAY_JOBS=$( wc -l < $tmpfile )

    if [ "$SINGULARITY" = true ]; then
        if [ "$CONDA" = true ]; then
            echo "RUNNING WITH CONDA ENVIRONMENT ($CONDA_ENV)"
            JOB_STAGE2_STEP4_DEFAULT=$(sbatch --dependency=afterok:"$JOB_STAGE2_STEP3_DEFAULT_ID" <<EOT
#!/bin/bash
#SBATCH -J phase2_step4_default_${STUDY}
#SBATCH --array=1-$NUM_ARRAY_JOBS
#SBATCH --mem-per-cpu=4G
#SBATCH --cpus-per-task=1
#SBATCH -o ./logs/phase2_step4_default_%A_%a.out
NETWORK=\$( sed -n \${SLURM_ARRAY_TASK_ID}p $tmpfile | cut -f1 )
TRAIT=\$( sed -n \${SLURM_ARRAY_TASK_ID}p $tmpfile | cut -f2 )
PVALFILEPATH="${STUDY_PATH}/\${TRAIT}/"
echo "Network: \$NETWORK"

source activate $CONDA_ENV

python3 ./scripts/phase2/dc_identify_mea_passing_genes.py \
    --trait \$TRAIT \
    --geneset_input \$PVALFILEPATH \
    --FDR_threshold $FDR_THRESHOLD \
    --percentile_threshold $PERCENTILE_THRESHOLD \
    --network \$NETWORK \
    --input_path ${RESULTS_PATH_OR} \
    --num_permutations ${NUM_PERMUTATIONS}
EOT
)
        else
            echo "RUNNING WITH SINGULARITY"
            JOB_STAGE2_STEP4_DEFAULT=$(sbatch --dependency=afterok:"$JOB_STAGE2_STEP3_DEFAULT_ID" <<EOT
#!/bin/bash
#SBATCH -J phase2_step4_default_${STUDY}
#SBATCH --array=1-$NUM_ARRAY_JOBS
#SBATCH --mem-per-cpu=4G
#SBATCH --cpus-per-task=1
#SBATCH -o ./logs/phase2_step4_default_%A_%a.out
NETWORK=\$( sed -n \${SLURM_ARRAY_TASK_ID}p $tmpfile | cut -f1 )
TRAIT=\$( sed -n \${SLURM_ARRAY_TASK_ID}p $tmpfile | cut -f2 )
PVALFILEPATH="${STUDY_PATH}/\${TRAIT}/"
echo "Network: \$NETWORK"

singularity exec --no-home -B $(pwd):$(pwd) --pwd $(pwd) $container_python \
    python3 ./scripts/phase2/dc_identify_mea_passing_genes.py \
        --trait \$TRAIT \
        --geneset_input \$PVALFILEPATH \
        --FDR_threshold $FDR_THRESHOLD \
        --percentile_threshold $PERCENTILE_THRESHOLD \
        --network \$NETWORK \
        --input_path ${RESULTS_PATH_OR} \
        --num_permutations ${NUM_PERMUTATIONS}
EOT
)
        fi
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


#########################
### UTILITY FUNCTIONS ###
#########################
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
print_default_thresholding_message() {
    echo "
##########################
## DEFAULT THRESHOLDING ##
##########################
"
}
print_phase_completion() {
    echo "
########################
### PHASE $1 COMPLETE ###
########################
"
}
print_phase_completion_message() {
    if [ "$SINGULARITY" = true ]; then
        PHASE=$1
        JOBID=$2
        while squeue -j "$JOBID" | grep -q "$JOBID"; do
            sleep 5
        done
    fi
    print_phase_completion $PHASE
}
nextflow_cleanup() {
    rm -rf .nextflow* work/
}



############
### MAIN ###
############
# test
if [ "$TEST_MODE" = true ]; then
    print_test_message
fi

# pull containers
pull_docker_image

if [ "$SKIP_STAGE_1" = true ]; then
    echo "Skipping STAGE 1"
else
    ###############
    ### PHASE 1 ###
    ###############
    print_phase_message 1

    phase1_step1

    phase1_step2

    phase1_step3

    phase1_step4

    print_phase_completion_message 1 $JOB_STAGE1_STEP4_PERMUTATION_ID

    #nextflow_cleanup
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

        print_phase_completion_message 2 $JOB_STAGE2_STEP4_DEFAULT_ID

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

        print_phase_completion_message 2 $JOB_STAGE2_STEP7_ALTERNATE_ID
    fi
fi
echo "### FISHNET COMPLETE ###"
