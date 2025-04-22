nextflow.enable.dsl=2

process RANDOM_PERMUTATION {

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/mulled-v2-9d836da785124bb367cbe6fbfc00dddd2107a4da:b033d6a4ea3a42a6f5121a82b262800f1219b382-0' :
        'quay.io/biocontainers/mulled-v2-9d836da785124bb367cbe6fbfc00dddd2107a4da:b033d6a4ea3a42a6f5121a82b262800f1219b382-0' }"

    label "process_low"
    publishDir "./results/${params.pipeline}", mode: 'copy'

    output:
    path("RPscores/${params.trait}/*.csv"), emit: rp_scores

    script:
    """
    python3 ${projectDir}/bin/randomPermutation.py \
        ${params.pvalFileName} \
        "RPscores/${params.trait}/" \
        ${params.geneColName} \
        ${params.numRP}
    """

}

process PREPROCESS_FOR_PASCAL {

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/mulled-v2-9d836da785124bb367cbe6fbfc00dddd2107a4da:b033d6a4ea3a42a6f5121a82b262800f1219b382-0' :
        'quay.io/biocontainers/mulled-v2-9d836da785124bb367cbe6fbfc00dddd2107a4da:b033d6a4ea3a42a6f5121a82b262800f1219b382-0' }"

    label "process_low"
    publishDir "./results/${params.pipeline}/", pattern: "pascalInput/*", mode: 'copy'

    input:
    path pvalFile

    output:
    path("pascalInput/GS_*"),       emit: gs
    path("pascalInput/Module_*"),   emit: module
    path("pascalInput/GO_*"),       emit: go

    script:
    """
    python3 ${projectDir}/bin/preProcessForPascal.py \
        ${pvalFile} \
        ${params.moduleFileDir} \
        "pascalInput/" \
        ${params.pipeline} \
        ${params.trait} \
        ${params.geneColName} \
        ${params.pvalColName}
    """
}

process RUN_PASCAL {

    container 'jungwooseok/mea_pascal:1.1' // TODO: add to biocontainers
    label "process_low"
    publishDir "./results/${params.pipeline}/", pattern: "pascalOutput/*", mode: 'copy'

    input:
    path(geneScoreFile)
    path(moduleFile)
    path(goFile)

    output:
    path("pascalOutput/*"), emit: pascaloutput
    path(geneScoreFile),    emit: genescorefile
    path(goFile),           emit:gofile

    script:
    """
    python3 ${projectDir}/bin/runPascal.py \
        ${geneScoreFile} \
        ${moduleFile} \
        "pascalOutput/" \
        ${params.pipeline} \
        ${params.trait}
    """
}


process POSTPROCESS_PASCAL_OUTPUT {

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/mulled-v2-9d836da785124bb367cbe6fbfc00dddd2107a4da:b033d6a4ea3a42a6f5121a82b262800f1219b382-0' :
        'quay.io/biocontainers/mulled-v2-9d836da785124bb367cbe6fbfc00dddd2107a4da:b033d6a4ea3a42a6f5121a82b262800f1219b382-0' }"
    label "process_low"
    publishDir "./results/${params.pipeline}/", pattern: "significantModules/*", mode: 'copy'

    input:
    path(pascalOutputFile)
    path(geneScoreFilePascalInput) // used to decide number of tests
    path(goFile)

    output:
    path("masterSummaryPiece/master_summary_slice_*"),  emit:summaryslice
    path("significantModules/"),                        emit:sigmodules
    path(goFile),                                       emit:gofile

    """
    python3 ${projectDir}/bin/processPascalOutput.py \
        ${pascalOutputFile} \
        ${params.bonferroni_alpha} \
        "masterSummaryPiece/" \
        ${geneScoreFilePascalInput} \
        "significantModules/" \
        ${params.numTests}
    """
}

process GO_ANALYSIS {

    container 'jungwooseok/r-webgestaltr:1.0' // TODO: add to biocontainers
    publishDir "./results/${params.pipeline}/", pattern: "${params.GO_summaries_path}/${params.trait}/*", mode: 'copy' // copy ORA results to current location.
    label "process_low"

    input:
    path(masterSummarySlice)
    path(sigModuleDir)
    path(goFile)

    output:
    path(masterSummarySlice),   emit: mastersummaryslice
    path("${params.GO_summaries_path}/${params.trait}/GO_summaries_${goFile.baseName.split('_')[2]}_${goFile.baseName.split('_')[3]}/"),   emit: gosummaries
    path(goFile),               emit: gofile

    script:
    def oraSummaryDir = "${params.GO_summaries_path}/${params.trait}/GO_summaries_${goFile.baseName.split('_')[2]}_${goFile.baseName.split('_')[3]}/"
    """
    Rscript ${projectDir}/bin/ORA_cmd.R --sigModuleDir ${sigModuleDir} --backGroundGenesFile ${goFile} \
        --summaryRoot "${oraSummaryDir}" --reportRoot "GO_reports/"

    """
}

process MERGE_RESULTS {

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/pandas:1.1.5' :
        'quay.io/biocontainers/pandas:1.1.5' }"
    label "process_low"
    publishDir "./results/${params.pipeline}/${params.masterSummaries_path}/", mode: 'copy'

    input:
    path(masterSummaryPiece)
    path(oraSummaryDir)
    path(goFile)

    output:
    path("summaries/*"), emit: summaries

    """
    python3 ${projectDir}/bin/mergeORAandSummary.py \
        ${masterSummaryPiece} \
        ${oraSummaryDir} \
        "summaries/" \
        ${goFile}
    """

}

