import numpy as np
import pandas as pd
import ast
import os
import math
import scipy.stats as stats


def summary_statistics_rp(trait, input_path, or_id, input_file_rr_id, rr_id, network, output_path, num_permutations):
    #load original and rp_all_output dataframes
    trait = "0-" + trait
    original_run_summary_filepath = os.path.join(input_path,or_id,"results","raw",f"{network}_{trait}_{network}_or_summary.csv")
    if os.path.exists(original_run_summary_filepath):
        original_run_summary_df = pd.read_csv(original_run_summary_filepath)
    else:
        print(f"FILE-NOT-FOUND: {original_run_summary_filepath}")
        return     
    summary_df = pd.DataFrame(columns = ["Ranks", "Average", "Median", "sd", "confidence_interval_95", "90_percentile", "95_percentile", "FDR", "num_MEA_passing", "original_run_percentile"])

    #rp_all_output_df["Rank"].unique()
    for rank in original_run_summary_df["threshold"]:
        # rank = (rank // 5) * 5 

        rank = int(rank)
        rp_file = os.path.join(input_path, rr_id, "results/raw", f"{input_file_rr_id}_{rank}_{network}_rp_mea_passing_across_{num_permutations}_permutations.csv")
        if os.path.exists(rp_file):
            rp_all_output_df = pd.read_csv(rp_file)
        else:
            print(f"FILE-NOT-FOUND: {rp_file}")
            continue

        temp_data = np.array(rp_all_output_df["MEA_passing_genes"]) 
        new_row = [rank]
        #calculate mean, median, sd
        mean = np.mean(temp_data)
        new_row.append(mean)
        median = np.median(temp_data)
        new_row.append(median)
        std_dev = np.std(temp_data)
        new_row.append(std_dev)
        #calculate confidence interval
        confidence_level = 0.95
        degrees_freedom = len(temp_data) - 1
        sample_mean = np.mean(temp_data)
        sample_standard_error = stats.sem(temp_data)
        confidence_interval = stats.t.interval(
            confidence_level,
            degrees_freedom,
            sample_mean,
            sample_standard_error
        )
        new_row.append(str(confidence_interval[0]) + ":" + str(confidence_interval[1]))

        #calculate 90 percent and 95 percent confidence interval
        ninety_percentile = np.percentile(temp_data, 90)
        new_row.append(ninety_percentile)
        ninety_five_percentile = np.percentile(temp_data, 95)
        new_row.append(ninety_five_percentile)

        #calculate original run percentile
        original_number_MEA_passing_genes = original_run_summary_df[original_run_summary_df["threshold"] == rank]["mea_passing_genes"].tolist()[0]
        #calculate FDR
        if (original_number_MEA_passing_genes != 0):
            FDR = mean/original_number_MEA_passing_genes
        else:
            FDR = np.nan
        new_row.append(FDR)
        new_row.append(original_number_MEA_passing_genes)
        or_percentile = stats.percentileofscore(temp_data, original_number_MEA_passing_genes)
        new_row.append(or_percentile)
        # print(len(new_row))
        summary_df.loc[len(summary_df.index)] = new_row

    if not os.path.exists(output_path):
        os.makedirs(output_path)
    summary_df.to_csv(os.path.join(output_path,f"{trait}_{network}_summary_{num_permutations}_permutations.csv"), index = None)

if __name__ == "__main__":
    from argparse import ArgumentParser   
    parser = ArgumentParser()
    parser.add_argument('--trait', '-trait', help='trait')
    parser.add_argument('--input_path', '-input_path')
    parser.add_argument('--or_id', '-or_id')
    parser.add_argument('--input_file_rr_id', '-input_file_rr_id')
    parser.add_argument('--rr_id', '-rr_id')
    parser.add_argument('--network', '-network')
    parser.add_argument('--output_path', '-output_path')
    parser.add_argument("--num_permutations")
    
    args = parser.parse_args()
    summary_statistics_rp(trait = args.trait, input_path = args.input_path, or_id = args.or_id, input_file_rr_id = args.input_file_rr_id, rr_id = args.rr_id, network = args.network, output_path = args.output_path, num_permutations = args.num_permutations)


