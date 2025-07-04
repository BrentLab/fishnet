import numpy as np
import pandas as pd
import ast
import os
import math
import scipy.stats as stats


#New inputs
#network_connections_path -- points to the network connection input by the user in the web platform
#module_path -- module path points to data/modules/

def extract_genes_from_module(module_index, module_path, network):
    genes = []

    with open(module_path + network + ".txt", 'r') as file:
        for line in file:
            parts = line.strip().split('\t')
            if int(parts[0]) == module_index:
                genes = parts[2:]  # skip the first two columns (module_index and score)
                break
    return genes    

def concat_strings(row):
    if row['Source'].lower() < row['Target'].lower():
        return row['Source'] + row['Target']
    else:
        return row['Target'] + row['Source']

def identify_mea_passing_genes(trait, geneset_input, network, input_path, network_connections_path, module_path):
    trait = "0-" + trait
    #initialize output df
    fishnet_df = pd.DataFrame(columns = ["Threshold", "Network", "numNominal", "Trait", "NumFISHNETGenes", "FISHNETGenes"])

    #read gene set df and count the number of genes with nominal significance
    gene_set_df = pd.read_csv(os.path.join(geneset_input,f"{trait}.csv"))
    gene_set_df.columns = ["Gene", "pval"]
    gene_set_df = gene_set_df.sort_values(by = ["pval"])
    gene_set_df_nominal_signficance = gene_set_df[gene_set_df["pval"] <= 0.05].shape[0]
    gene_set_df_nominal_signficance = (gene_set_df_nominal_signficance // 10) * 10
    
    #read summary data
    summary_filepath = os.path.join(input_path, "results", "raw",  f"{network}_{trait}_{network}_or_fishnet_genes.csv")
    if  not os.path.exists(summary_filepath):
        return

    summary_df = pd.read_csv(summary_filepath)
    thresholds = [0.05]

    for threshold in thresholds: 
        #initialize output df
        fishnet_df = pd.DataFrame(columns = ["Threshold", "Network", "numNominal", "Trait", "NumFISHNETGenes", "FISHNETGenes"])
        gene_rank_picked = int(gene_set_df.shape[0] * threshold)
        gene_rank_picked = round(gene_rank_picked/10) * 10

        fishnet_genes = ast.literal_eval(summary_df[summary_df["threshold"] == gene_rank_picked]["mea_passing_genes"].iloc[0])

        new_row = {
            "Threshold": gene_rank_picked,
            "Network": network,
            "numNominal": gene_set_df_nominal_signficance,
            "Trait": trait,
            "NumFISHNETGenes": len(fishnet_genes),
            "FISHNETGenes": fishnet_genes
        }
        #print(new_row)
        fishnet_df = pd.concat([fishnet_df, pd.DataFrame([new_row])], ignore_index=True)

        # <-------- Save FISHNET genes ------->
        if len(fishnet_genes) > 0:
            fishnet_df.to_csv(os.path.join(input_path,"summary",f"{network}_{trait}_fishnet_genes_noRP.csv"), index = None)

        # <----- Save network connections ----> 

        #subset module connections from network connection edges 

        significant_modules_df = pd.read_csv(input_path + "master_summary_filtered_parsed.csv")
        significant_modules_df = significant_modules_df[(significant_modules_df["trait"] == trait) &
                                                     (significant_modules_df["network"] == network)]
        if significant_modules_df.shape[0] > 0:
            network_connections = pd.read_table(network_connections_path + network + ".txt")
            significant_modules = significant_modules_df["moduleIndex"].tolist()

            for module_index in significant_modules:
                module_genes = extract_genes_from_module(module_index, module_path, network) 

                network_temp = network_connections[(network_connections["Source"].isin(module_genes)) &
                                                     (network_connections["Target"].isin(module_genes))]
                if(network_temp.shape[0] > 0):
                    network_temp['concatenated_col'] = network_temp.apply(concat_strings, axis=1)
                    if network_temp['concatenated_col'].unique().shape[0] < network_temp.shape[0]:
                        network_temp.drop_duplicates(subset='concatenated_col', keep='first', inplace=True)
                    os.makedirs(input_path + "significant_module_connections", exist_ok=True)
                    network_temp = network_temp[["Source", "Target", "Score"]]
                    network_temp.to_csv(input_path + "significant_module_connections/" + trait + "_" + network + "_" + str(module_index) + ".txt", sep = "\t", index = None)

if __name__ == "__main__":
    from argparse import ArgumentParser   
    parser = ArgumentParser()
    parser.add_argument('--trait', '-trait', help='trait')
    parser.add_argument('--geneset_input', '-geneset_input', help='trait')
    parser.add_argument('--network', '-network')
    parser.add_argument('--input_path', '-input_path')
    parser.add_argument("--network_connections_path", '-network_connections_path')
    parser.add_argument("--module_path", '-module_path')
    
    args = parser.parse_args()
    identify_mea_passing_genes(trait = args.trait, geneset_input = args.geneset_input, network = args.network, input_path = args.input_path, network_connections_path = args.network_connections_path,module_path = args.module_path )


