import json
import logging
import pandas as pd
import yaml
import logging.config
import argparse
import sys
import pickle

from sklearn.preprocessing import StandardScaler
from sklearn.metrics import silhouette_score
from sklearn.cluster import KMeans

logging_config = './config/logging/local.conf'
try:
    logging.config.fileConfig(logging_config)
except:
    logging.basicConfig(format='%(asctime)s %(name)-12s %(levelname)-8s %(message)s',
                        datefmt='%m/%d/%Y %I:%M:%S %p',
                        level=logging.DEBUG)
logger = logging.getLogger('model.py')


def load_featurized_data(filepath):
    """Loads json data from local filepath and returns a dictionary """

    with open(filepath) as json_file:
        data = json.load(json_file)
        df = pd.DataFrame(data)
        logger.info(f'Successfully loaded unfeaturized data from {filepath}')

    return df

def extract_features(df):
    '''Drops all columns, which are not relevant features for KMeans Clustering'''

    logger.debug('Dropping columns which are not relevant features for KMeans Clustering')
    features_df = df.drop(['id', 'name', 'image', 'thumbnail', 'artists', 'publishers',
                           'designers', 'description', 'categories', 'mechanics'], axis=1)

    return features_df

def standardize_features(df):
    '''Standardize Feature Matrix. Takes pd.DataFrame and returns Numpy array'''
    logger.info('Standardizing Features')
    standardized_features = StandardScaler().fit_transform(df)

    return standardized_features

def fit_kmeans(X, k, seed):
    '''Fits KMeans clustering algorithm on provided feature matrix. Returns model object'''

    # Instantiate estimator
    kmeans = KMeans(n_clusters=k, random_state=seed)
    # Fit estimator on standardized feature data
    logger.info('Fitting KMeans Clustering algorithm to provided feature data')
    kmeans.fit(X)

    return kmeans

def model_predict(X, model):
    '''Calculates labels for feature data based on provided model'''
    logger.info('Calculating labels (clusters) for provided data')
    model.predict(X)

    return model.labels_

def evaluate_silhouette(X, labels):
    return silhouette_score(X, labels)

def combine_with_labels(df, labels):

    # Taking only the relevant columns and removing the ones with the one-hot encoded features
    cols_left = list(df.columns[:12]) + list(df.columns[-6:])
    df = df[cols_left]
    df['cluster'] = labels

    return df


if __name__ == "__main__":
    # Setup CLI argument parser
    parser = argparse.ArgumentParser(description="Trains a KMeans Clustering algorithm and applies labels to featurized data in data/games_featurized.json")
    parser.add_argument('-i', '--input',
                        help="Path to input (games_featurized.json). Default: ../data/games_featurized.json",
                        default="../data/games_featurized.json", type=str)
    parser.add_argument('-c', '--config',
                        help="Path to .yml (YAML) config file with module settings. Default: ../config/config.yml",
                        default='../config/config.yml', type=str)
    parser.add_argument('-o', '--output',
                        help="Path to output labelled (clustered) data. Default: ../data/games_clustered.json",
                        default="../data/games_clustered.json", type=str)
    parser.add_argument('-mo', '--model_output',
                        help="Path to save trained model. Default: ../models/kmeans.pkl",
                        default="../models/kmeans.pkl", type=str)

    # Parse CLI arguments
    args = parser.parse_args()

    # Load .yml config file
    try:
        with open(args.config, 'r') as f:
            config = yaml.load(f, Loader=yaml.FullLoader)
            logger.info(f'Loaded configurations from {args.config}')
    except FileNotFoundError as e:
        logger.error(f"Could not load configurations file, didn't find it at {args.config} and threw error {e}")
        logger.error('Terminating process prematurely')
        sys.exit()

    # Load unfeaturized json data into a dictionary
    featurized_data = load_featurized_data(args.input)

    # Extract relevant feature columns
    features_df = extract_features(featurized_data)

    # Standardize data and return feature matrix (numpy array)
    X = standardize_features(features_df)

    # Fit KMeans model
    model = fit_kmeans(X, **config['model']['kmeans'])

    # Calculate labels for data
    labels = model_predict(X, model)

    # Calculate Silhouette score for fitted model and labels for the training data
    silhouette_score_ = evaluate_silhouette(X, labels)

    # Combining the original df with the labels and dropping unnecessary columns (now that the modelling is done)
    df = combine_with_labels(featurized_data, labels)

    # Converting back to dictionary so I can save as json
    df_dict = df.to_dict(orient='records')

    # Saving final json data, which will be used for upload to database
    with open(args.output, 'w') as fp:
        json.dump(df_dict, fp)
        logger.info(f'Saved final json data to {args.output}')

    # Saving calculated model
    with open(args.model_output, 'wb') as output:
        pickle.dump(model, output)
        logger.info(f'Saved model to {args.model_output}')

    # Saving silhouette score
    model_silhouette_path = args.model_output[:-4] + '.txt'  # Changing the file extension from .pkl to .txt
    with open(model_silhouette_path, "w") as text_file:
        text_file.write(f"The model silhouette score is: {silhouette_score_}")
        logger.info(f'Saved silhouette score to {model_silhouette_path}')