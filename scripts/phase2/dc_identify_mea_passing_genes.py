import numpy as np
import pandas as pd
import ast
import os
import math
import scipy.stats as stats


def identify_mea_passing_genes(trait, geneset_input, FDR_threshold, percentile_threshold, network, input_path ):
    trait = "0-" + trait
    #print(trait)
    #print(geneset_input)
    #print(FDR_threshold)
    #print(percentile_threshold)
    #print(network)


    #initialize output df
    fishnet_df = pd.DataFrame(columns = ["Threshold", "Network", "numNominal", "Trait", "NumFISHNETGenes", "FISHNETGenes"])

    #read gene set df and count the number of genes with nominal significance
    gene_set_df = pd.read_csv(os.path.join(geneset_input,f"{trait}.csv"))
    gene_set_df.columns = ["Gene", "pval"]
    gene_set_df = gene_set_df.sort_values(by = ["pval"])
    gene_set_df_nominal_signficance = gene_set_df[gene_set_df["pval"] <= 0.05].shape[0]
    gene_set_df_nominal_signficance = (gene_set_df_nominal_signficance // 10) * 10
    
    #read summary data

    summary_filepath = os.path.join(input_path, "summary", f"{trait}_{network}_summary.csv")
    if  not os.path.exists(summary_filepath):
        return

    summary_df = pd.read_csv(summary_filepath)
    thresholds = [0.05]

    start = 0.01
    end = float(FDR_threshold)
    step = 0.01
    fdr_thresholds = [FDR_threshold]
    #print(fdr_thresholds)

    for threshold in thresholds: 
        #initialize output df
        for fdr in fdr_thresholds:
            fishnet_df = pd.DataFrame(columns = ["Threshold", "Network", "numNominal", "Trait", "NumFISHNETGenes", "FISHNETGenes"])
            gene_rank_picked = int(gene_set_df.shape[0] * threshold)
            temp_summary_df = summary_df[summary_df["Ranks"] <= gene_rank_picked]
            #filter for FDR and percentile threshold from the remaining df
            filtered_df = temp_summary_df[(temp_summary_df['original_run_percentile'] >= float(percentile_threshold)) & (temp_summary_df['FDR'] <= fdr)]
            
            if filtered_df.empty:
                continue 
            #print("Sandeep")
            largest_rank = filtered_df['Ranks'].max()
            
            #retrieve MEA passing genes
            mea_passing_genes = pd.read_csv(os.path.join(input_path,"results","raw",f"{network}_{trait}_{network}_or_fishnet_genes.csv"))
            mea_passing_genes = mea_passing_genes[mea_passing_genes["threshold"] == largest_rank]
            mea_passing_list = mea_passing_genes['mea_passing_genes'].tolist()[0]
            num_mea_passing = filtered_df[filtered_df["Ranks"] == largest_rank]["num_MEA_passing"].tolist()[0]

            new_row = {
                "Threshold": largest_rank,
                "Network": network,
                "numNominal": gene_set_df_nominal_signficance,
                "Trait": trait,
                "NumFISHNETGenes": num_mea_passing,
                "FISHNETGenes": mea_passing_list
            }
            #print(new_row)
            fishnet_df = pd.concat([fishnet_df, pd.DataFrame([new_row])], ignore_index=True)
            fishnet_df.to_csv(os.path.join(input_path,"summary",f"{network}_{trait}_fishnet_genes_{fdr}.csv"), index = None)


if __name__ == "__main__":
    from argparse import ArgumentParser   
    parser = ArgumentParser()
    parser.add_argument('--trait', '-trait', help='trait')
    parser.add_argument('--geneset_input', '-geneset_input', help='trait')
    parser.add_argument('--FDR_threshold', '-FDR_threshold')
    parser.add_argument('--percentile_threshold', '-percentile_threshold')
    parser.add_argument('--network', '-network')
    parser.add_argument('--input_path', '-input_path')
    
    args = parser.parse_args()
    identify_mea_passing_genes(trait = args.trait, geneset_input = args.geneset_input, FDR_threshold = args.FDR_threshold, percentile_threshold = args.percentile_threshold, network = args.network, input_path = args.input_path)


