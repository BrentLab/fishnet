import pandas as pd
import argparse
import os

# after including Coexpression network in the pipeline, the number of summary slices causes some issue
# hence, I decided to run this script separately after the pipeline is finished to generate a summary file.

def get_csv_files(dirPath):
    """Return a list of all csv files in the given directory path."""
    return [os.path.join(dirPath, filename) for filename in os.listdir(dirPath) if filename.endswith('.csv')]

def concatenate_csv(dirPath, identifier:str, output_dir="."):
    # List all CSV files in the given directory
    file_paths = get_csv_files(dirPath)

    # Read the CSV files and store them in a list
    data_frames = [pd.read_csv(file_path) for file_path in file_paths]

    # Concatenate the data frames vertically
    concatenated_df = pd.concat(data_frames, ignore_index=True)

    # Sort the concatenated dataframe by 'moduleBonPval' in ascending order
    concatenated_df = concatenated_df.sort_values(by="moduleBonPval", ascending=True)

    # Define name of the output
    outputFileName = f"master_summary_{identifier}.csv"

    # Save the concatenated data frame to an output CSV file
    concatenated_df.to_csv(os.path.join(output_dir, f"{outputFileName}"), index=False)

if __name__ == "__main__":
    # Argument parsing
    parser = argparse.ArgumentParser(description='Concatenate CSV files vertically.')
    parser.add_argument('dirPath', type=str, help='path to a parent directory containing all the CSV files to be concatenated')
    parser.add_argument("identifier", type=str, help='string to identify the run, ex) cmaLLFS, cmaFHS')
    args = parser.parse_args()


    # Call the concatenate_csv function with the read file paths
    concatenate_csv(args.dirPath, args.identifier)
