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
        Default: 0.99
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
PERCENTILE_THRESHOLD=0.99
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
                MODULEFILEPATH="$2"
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
    MODULEFILEPATH="./data/modules/ker_based/"
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
    if [ ! -d "$MODULEFILEPATH" ]; then
        echo "--modules $MODULEFILEPATH DIRECTORY NOT FOUND"
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
MODULEFILEPATH=$( readlink -f "$MODULEFILEPATH" )

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
NUM_MODULE_FILES=$( ls -1 ${MODULEFILEPATH}/*.txt 2>/dev/null | wc -l)
echo "# FOUND ${NUM_MODULE_FILES} module files"

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
export MODULEFILEPATH
export NUMTESTS
export GENECOLNAME
export PVALCOLNAME
export BONFERRONI_ALPHA
export RESULTS_PATH
export RESULTS_PATH_OR
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

#################
### FUNCTIONS ###
#################
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
            echo "Environment $CONDA_ENV found"
        else
            echo "Environment $CONDA_ENV not found...creating"
            conda env create -f conf/fishnet_conda_environment.yml
            echo "done"
        fi
    fi

    export PULL_PYTHON_CONTAINER
    export PULL_R_CONTAINER
    export JOB_PULL_SINGULARITY_PYTHON_ID
    export JOB_PULL_SINGULARITY_R_ID
}


phase1_step1() {

    # (4.1) nextflow (original)
    echo "# STEP 1.1: executing Nextflow MEA pipeline on original run"
    #echo $SINGULARITY
    #echo $PULL_PYTHON_CONTAINER
    #echo $PULL_R_CONTAINER
    #echo $JOB_PULL_SINGULARITY_PYTHON_ID
    #echo $JOB_PULL_SINGULARITY_R_ID
    # TODO: CHECK FOR ORIGINAL VS RANDOM PERMUTATION RUNS

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

    # (4.2) compile results (original)
    SUMMARIES_PATH_ORIGINAL="${RESULTS_PATH_OR}/masterSummaries/summaries/"
    if [ "$CONDA" = true ]; then
        JOB_STAGE1_STEP4_ORIGINAL=$(sbatch --dependency=afterok:"$JOB_STAGE1_STEP1_ID" <<EOT
#!/bin/bash
#SBATCH -J phase1_step4_original
#SBATCH -o ./logs/phase1_step4_original_%J.out
source activate $CONDA_ENV
python3 ./scripts/phase1/compile_results.py \
    --dirPath $SUMMARIES_PATH_ORIGINAL \
    --identifier $STUDY \
    --output $RESULTS_PATH_OR
EOT
)
        JOB_STAGE1_STEP4_ORIGINAL_ID=$(echo "$JOB_STAGE1_STEP4_ORIGINAL" | awk '{print $4}')
    elif [ "$SINGULARITY" = true ]; then
        JOB_STAGE1_STEP4_ORIGINAL=$(sbatch --dependency=afterok:"$JOB_STAGE1_STEP1_ID" <<EOT
#!/bin/bash
#SBATCH -J phase1_step4_original
#SBATCH -o ./logs/phase1_step4_original_%J.out
singularity exec --no-home -B $(pwd):$(pwd) --pwd $(pwd) $container_python \
python3 ./scripts/phase1/compile_results.py \
    --dirPath $SUMMARIES_PATH_ORIGINAL \
    --identifier $STUDY \
    --output $RESULTS_PATH_OR
EOT
)
        JOB_STAGE1_STEP4_ORIGINAL_ID=$(echo "$JOB_STAGE1_STEP4_ORIGINAL" | awk '{print $4}')
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
#    # (2) generate uniform p-values
#    echo "# STEP 1.2: generating uniformly distributed p-values"
#    if [ "$SINGULARITY" = true ]; then
#        JOB_STAGE1_STEP2=$(sbatch <<EOT
##!/bin/bash
##SBATCH -J phase1_step2
##SBATCH -o ./logs/phase1_step2_%J.out
#singularity exec --no-home -B $(pwd):$(pwd) --pwd $(pwd) $container_python \
#python3 ./scripts/phase1/generate_uniform_pvals.py \
#    --genes_filepath $PVALFILEPATH
#EOT
#)
#        JOB_STAGE1_STEP2_ID=$(echo "$JOB_STAGE1_STEP2" | awk '{print $4}')
#    else
#        docker run --rm -v $(pwd):$(pwd) -w $(pwd) -u $(id -u):$(id -g) $container_python  /bin/bash -c \
#            "python3 ./scripts/phase1/generate_uniform_pvals.py \
#            --genes_filepath $PVALFILEPATH"
#    fi


    # (3) nextflow random permutation run
    echo "# STEP 1.3: executing Nextflow MEA pipeline on random permutations"
    echo "executing Nextflow MEA pipeline on random permutations"
    if [ "$SINGULARITY" = true ]; then
        JOB_STAGE1_STEP3=$(sbatch --dependency=afterok:"$JOB_STAGE1_STEP2_ID" ./scripts/phase1/phase1_step3_multi.sh $(pwd))
        JOB_STAGE1_STEP3_ID=$(echo "$JOB_STAGE1_STEP3" | awk '{print $4}')
    else
        ./scripts/phase1/phase1_step3_multi.sh $(pwd)
    fi

    # (4.2)
    SUMMARIES_PATH_PERMUTATION="${RESULTS_PATH_RR}/masterSummaries_RP/summaries/"
    # dynamically set memory allocation based on number of modules and number of permutations
    # currently: 2 MB * N(modules) * N(permutations)
    MEM_ALLOCATION=$(( 2 * $NUM_MODULE_FILES * $NUM_PERMUTATIONS ))
    if [ "$CONDA" = true ]; then
        JOB_STAGE1_STEP4_PERMUTATION=$(sbatch --dependency=afterok:"$JOB_STAGE1_STEP3_ID" <<EOT
#!/bin/bash
#SBATCH -J phase1_step4_permutation
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
                --dirPath $summaries_path_permutation \
                --identifier ${TRAITRR} \
                --output $OUTPUT_DIR"
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

    #phase1_step1

    phase1_step3

    #phase1_step5

    #print_phase1_completion_message

    #nextflow_cleanup
fi

#if [ "$SKIP_STAGE_2" = true ]; then
#    echo "Skipping STAGE 2"
#else
#    ###############
#    ### PHASE 2 ###
#    ###############
#
#    print_phase_message 2
#
#    phase2_step0
#
#    if [ "$THRESHOLDING_MODE" = "$THRESHOLDING_MODE_DEFAULT" ]; then
#        ##########################
#        ## DEFAULT THRESHOLDING ##
#        ##########################
#
#        print_default_thresholding_message
#
#        phase2_step1_default
#
#        phase2_step2_default
#
#        phase2_step3_default
#
#        phase2_step4_default
#
#        print_phase2_completion_message $JOB_STAGE2_STEP4_DEFAULT_ID
#
#    else
#        ##############################
#        ## ALTERNATIVE THRESHOLDING ##
#        ##############################
#        print_alternative_thresholding_message
#
#        phase2_step1_alternate
#
#        phase2_step2_original_alternate
#
#        phase2_step2_permutation_alternate
#
#        phase2_step3_original_alternate
#
#        phase2_step3_permutation_alternate
#
#        phase2_step4_alternate
#
#        phase2_step5_alternate
#
#        phase2_step6_alternate
#
#        phase2_step7_alternate
#
#        print_phase2_completion_message $JOB_STAGE2_STEP7_ALTERNATE_ID
#    fi
#fi
echo "### FISHNET COMPLETE ###"
