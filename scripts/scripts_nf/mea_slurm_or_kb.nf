nextflow.enable.dsl=2

// params.pvalFileName = '' // Placeholder for the command-line argument

// FIX BELOW PARAMS BEFORE RUNNING IT -> Now, sbatch script takes "trait" and "numTests" then pass it here. 
// pvalFilenName is made in the sbatch script, so it is REQUIRED that the gene score file's basename matches trait
// params.pipeline = "cmaRPLLFS"


process PreProcessForPascal{
    //container 'mea_latest.sif'
    label "process_low"

    input:
    path pvalFile // Change this line to accept a path

    output:
    path("pascalInput/GS_*")
    path("pascalInput/Module_*")
    path("pascalInput/GO_*")

    script:
    """
    python3 /app/scripts/scripts_nf/preProcessForPascal.py \
        ${pvalFile} \
        ${params.moduleFileDir} \
        "pascalInput/" \
        ${params.pipeline} \
        ${params.trait} \
        ${params.geneColName} \
        ${params.pvalColName}
    """
}

process RunPascal{
    //container 'pascalx_latest.sif'
    label "process_low"

    input:
    path(geneScoreFile)
    path(moduleFile)
    path(goFile)

    output:
    path("pascalOutput/*")
    path(geneScoreFile)
    path(goFile)

    script:
    """
    python3 /app/scripts/scripts_nf/runPascal.py \
        ${geneScoreFile} \
        ${moduleFile} \
        "pascalOutput/" \
        ${params.pipeline} \
        ${params.trait}
        
    """
}

process ProcessPascalOutput{
    //container 'mea_latest.sif'
    label "process_low"

    input:
    path(pascalOutputFile)
    path(geneScoreFilePascalInput) // used to decide number of tests
    path(goFile)

    output:
    path("masterSummaryPiece/master_summary_slice_*")
    path("significantModules/")
    path(goFile)

    """
    python3 /app/scripts/scripts_nf/processPascalOutput.py \
        ${pascalOutputFile} \
        0.05 \
        "masterSummaryPiece/" \
        ${geneScoreFilePascalInput} \
        "significantModules/" \
        ${params.numTests}
    """
}

process GoAnalysis{
    //container 'webgestalt_latest.sif'
    publishDir "./results/", pattern: "GO_summaries/${params.trait}/*", mode: 'copy' // copy ORA results to current location.
    label "process_low"

    input:
    path(masterSummarySlice)
    path(sigModuleDir)
    path(goFile)

    output:
    path(masterSummarySlice)
    path("GO_summaries/${params.trait}/GO_summaries_${goFile.baseName.split('_')[2]}_${goFile.baseName.split('_')[3]}/")
    path(goFile)

    script:
    def oraSummaryDir = "GO_summaries/${params.trait}/GO_summaries_${goFile.baseName.split('_')[2]}_${goFile.baseName.split('_')[3]}/"
    """
    Rscript /app/scripts/scripts_nf/ORA_cmd.R --sigModuleDir ${sigModuleDir} --backGroundGenesFile ${goFile} \
        --summaryRoot "${oraSummaryDir}" --reportRoot "GO_reports/"

    """
}

process MergeORAsummaryAndMasterSummary{
    //container 'mea_latest.sif'
    label "process_low"
    publishDir "./results//masterSummaries/", mode: 'copy'
    input:
    path(masterSummaryPiece)
    path(oraSummaryDir)
    path(goFile)

    output:
    path("summaries/*")

    """
    python3 /app/scripts/scripts_nf/mergeORAandSummary.py \
        ${masterSummaryPiece} \
        ${oraSummaryDir} \
        "summaries/" \
        ${goFile}
    """

}

workflow {
    print(params)
    // For each module file in the module directory, preprocess the data for pascal.
    preProcessedFiles = PreProcessForPascal(params.pvalFileName)
    pascalOut = RunPascal(preProcessedFiles[0]|flatten, preProcessedFiles[1]|flatten, preProcessedFiles[2]|flatten)
    processedPascalOutput = ProcessPascalOutput(pascalOut[0]|flatten, pascalOut[1]|flatten, pascalOut[2]|flatten)
    goAnalysisOut = GoAnalysis(processedPascalOutput[0]|flatten, processedPascalOutput[1]|flatten, processedPascalOutput[2]|flatten)
    horizontallyMergedOut = MergeORAsummaryAndMasterSummary(goAnalysisOut[0]|flatten, goAnalysisOut[1]|flatten, goAnalysisOut[2]|flatten)
}
