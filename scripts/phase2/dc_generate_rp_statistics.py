import numpy as np
import pandas as pd
import ast
import os
import math


#Usage in generate_rp_statistics.sbatch

def generate_rp_statistics(gene_set_path, master_summary_path, trait, module_path, go_path, output_path, threshold, network, num_permutations ):
    #print("Started")
    #print(gene_set_path)
    #print(master_summary_path)
    #print(module_path)
    #print(go_path)
    #print(output_path)
    #print(threshold)
    #print(network)
    final_df = pd.DataFrame(columns = ["threshold", "avg_mea_passing", "avgFraction_mea_passing", "FP_in_XXXX"])
    threshold = int(threshold)

    individual_stat_df = pd.DataFrame(columns = ["Rank", "MEA_passing_genes"])
    #iterate through multiple threshold of gene ranks

    #save mea_passing genes and the fraction of mea-passing genes
    mea_passing_genes_count_list= []
    fraction_of_mea_passing_genes_count_list = []

    #read master summary files
    master_summary = pd.read_csv(master_summary_path)
    #print(master_summary.columns)
    master_summary = master_summary[(master_summary["network"] == network)]    

    #read modules
    data = []

    with open(module_path, 'r') as file:
        for line in file:
            data.append(line.strip().split('\t'))
    
    # Convert the list of lists into a DataFrame
    module_df = pd.DataFrame(data)
    module_df.set_index(0, inplace=True)
    module_df.index = module_df.index.astype(int)  # Ensure the index is -an integer

    #iterate through permutation files
    #change this to 5000 after testing the pipeline
    for index in list(range(1,int(num_permutations)+1)):
        if(index % 100 == 0):
            print(index)
        gene_set_df = pd.read_csv(os.path.join(gene_set_path,f"{index}-{trait}.csv"))
        gene_set_df.columns = ["Gene", "pval"]
        gene_set_df = gene_set_df.sort_values(by = ["pval"])
        temp_gene_set_df = gene_set_df.head(threshold)
        gene_set_series = temp_gene_set_df["Gene"]
        permuted_trait = str(index) + "-" + trait
    
        #process master summary file
        temp_master_summary = master_summary[master_summary["trait"] == permuted_trait]
        temp_master_summary = temp_master_summary.reset_index(drop=True)
    
        #get the number of MEA passing genes from the queried gene set
        temp_mea_passing_genes_count = MEA_passing(module_df, permuted_trait, temp_master_summary, go_path,  gene_set_series, network )
        
        # save the outputs to the list
        mea_passing_genes_count_list.append(temp_mea_passing_genes_count)
        fraction_of_mea_passing_genes_count_list.append(temp_mea_passing_genes_count/threshold)

    #save all individual permutation mea-passing genes
    temp_stat_df = pd.DataFrame(columns = ["Rank", "MEA_passing_genes"])
    temp_stat_df["Rank"] = [threshold] * len(mea_passing_genes_count_list)
    temp_stat_df["MEA_passing_genes"] = mea_passing_genes_count_list
    #individual_stat_df = individual_stat_df.append(temp_stat_df)
    individual_stat_df = pd.concat([individual_stat_df, temp_stat_df], ignore_index=True)

    #calculate the summary statistics and save in the final df     
    average_mea_passing_genes_count_list = sum(mea_passing_genes_count_list)/ len(mea_passing_genes_count_list)
    average_fraction_of_mea_passing_genes_count_list = sum(fraction_of_mea_passing_genes_count_list)/len(fraction_of_mea_passing_genes_count_list)
    true_negatives = gene_set_df.shape[0] - average_mea_passing_genes_count_list
    FPR = average_mea_passing_genes_count_list/(average_mea_passing_genes_count_list + true_negatives)
    
    if(FPR > 0):
        FP_in_XXXX = 1/FPR
    else:
        FP_in_XXXX = -1
    
    final_df.loc[len(final_df.index)] = [threshold, average_mea_passing_genes_count_list, average_fraction_of_mea_passing_genes_count_list, FP_in_XXXX]

    #write final df to the output directory
    if not os.path.exists(output_path):
        os.makedirs(output_path, exist_ok=True)
    individual_stat_df.to_csv(os.path.join(output_path,f"{trait}_{threshold}_{network}_rp_mea_passing_across_{num_permutations}_permutations.csv"), index = None)
    final_df.to_csv(os.path.join(output_path,f"{trait}_{threshold}_{network}_rp_summary_{num_permutations}_permutations.csv"), index = None)
    #print("Completed")

def extract_module_genes_by_index(module_df, index):
    #print(index)
    genes_row = module_df.loc[index].dropna().tolist()

    # Exclude the first two columns (index and second column, assuming it's not a gene)
    genes = genes_row[2:]
    return genes

def get_GO_genes(go_df):
    go_df = go_df[["geneSet", "description", "size", "overlap", "FDR", "userId"]]
    go_df = go_df.sort_values(by = ["FDR"])
    
    #FDR threshold is set to 0.05
    go_df = go_df[go_df["FDR"] <= 0.05]

    #filter for genes annoted in enriched GO Term 
    all_go_genes = []
    for index, row in go_df.iterrows():
        temp_go_set = row["userId"].split(";")
        all_go_genes.extend(temp_go_set)
    all_go_genes_set = set(all_go_genes)
    return all_go_genes_set

def MEA_passing(module_df, permuted_trait, temp_master_summary, go_path, gene_set, network):
    if (temp_master_summary.shape[0]) > 0:
        mea_passing_genes = []
        for index in temp_master_summary.index:
     
            #find the genes that lie in enriched modules
            module_index = temp_master_summary["moduleIndex"][index]
            module_index = int(module_index)
            module_genes = extract_module_genes_by_index(module_df, module_index)

            #genes intersecting between the first criteria and the second criteria for MEA-passing genes for a given module
            module_genes_intersection_gene_set = set(gene_set).intersection(set(module_genes))

            #find the genes that also lie in enriched GO Term for the enriched module        
            go_directory = "GO_summaries_" + permuted_trait + "_" + network
            trait = permuted_trait.split("-")[1]
            go_file = "sig_" + trait + "_" + permuted_trait + "_" + network + "_" + str(module_index) + ".csv"
            go_df = pd.read_csv(os.path.join(go_path,go_directory,go_file))


            if (go_df.shape[0] > 0):
                all_go_genes_set = get_GO_genes(go_df)
                set_qualifying_genes = module_genes_intersection_gene_set.intersection(all_go_genes_set)
                mea_passing_genes.extend(list(set_qualifying_genes))


        #return the count of the number of MEA_passing genes
        set_mea_passing_genes = set(mea_passing_genes)
        # if len(set(mea_passing_genes)) > 0:
        #     print("module genes:" + str(module_genes))
        #     print("module index:" + str(module_index))
        #     print("go_genes:" + str(all_go_genes_set))
        #     print("mea_passing_genes: " + str(set(mea_passing_genes)))
        return len(set_mea_passing_genes)
    else:
        return 0

if __name__ == "__main__":
    from argparse import ArgumentParser   
    parser = ArgumentParser()
    parser.add_argument('--gene_set_path', '-gene_set_path', help='the path to the file that has genes and pvalues for a given trait')
    parser.add_argument('--master_summary_path', '-master_summary_path', help='the path to the master summary file')
    parser.add_argument('--trait', '-trait', help='trait')
    parser.add_argument('--module_path', '-module_path', help='path to the module genes')
    parser.add_argument('--go_path', '-go_path', help='path to enriched go terms')
    parser.add_argument('--output_path', '-output_path', help = "directory to store the output")
    parser.add_argument('--threshold', '-threshold', help = "top X genes to look at")
    parser.add_argument('--network', '-network', help = "network type")
    parser.add_argument('--num_permutations', help='number of permutations')

    args = parser.parse_args()
    generate_rp_statistics(gene_set_path = args.gene_set_path, master_summary_path = args.master_summary_path, trait = args.trait, module_path = args.module_path, go_path = args.go_path, output_path = args.output_path, threshold = args.threshold, network = args.network, num_permutations = args.num_permutations)
