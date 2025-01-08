import numpy as np
import pandas as pd
import ast
import os
from pathlib import Path
import math
import scipy.stats as stats

# python dc_rp_genes.py --genes_filepath /scratch/mblab/acharyas/fishnet/pipeline/data/pvals/maleWC/0-maleWC.csv

def dc_rp_genes(genes_filepath):
    # Read the CSV file into a DataFrame
    df = pd.read_csv(genes_filepath)

    # Check if the required columns exist
    if "Genes" not in df.columns or "p_vals" not in df.columns:
        raise ValueError("The input file must contain 'genes' and 'p_vals' columns.")

    # Replace 'p_vals' column with uniformly distributed values
    num_rows = len(df)
    df["p_vals"] = np.random.uniform(0, 1, num_rows)

    # Extract directory name from the input path
    input_dir = os.path.dirname(genes_filepath)
    parent_dir = os.path.dirname(input_dir)
    new_dir_name = os.path.basename(input_dir) + "RR"
    new_dir = os.path.join(parent_dir, new_dir_name)
    os.makedirs(new_dir, exist_ok=True)

    # Define the new file path
    new_file_name = Path(genes_filepath).stem + "RR"
    new_file_name = f"{new_file_name}.csv"
    new_file_path = os.path.join(new_dir, new_file_name)

    # Save the updated DataFrame to the new file
    df.to_csv(new_file_path, index=False)

    return new_file_path
 
if __name__ == "__main__":
    from argparse import ArgumentParser   
    parser = ArgumentParser()
    parser.add_argument('--genes_filepath', '-genes_filepath')
    args = parser.parse_args()
    dc_rp_genes(genes_filepath = args.genes_filepath)


 
