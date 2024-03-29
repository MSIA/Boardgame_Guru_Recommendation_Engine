CONFIG_PATH=config/config.yml
OUTPUT_PATH=data/external/games.json
UPLOAD_PATH=data/external/games.json
DOWNLOAD_PATH=data/games.json
FEATURIZED_DATA_PATH=data/games_featurized.json
CLUSTERED_DATA_PATH=data/games_clustered.json
MODEL_OUTPUT_PATH=models/kmeans.pkl

AWS_CREDENTIALS=config/aws_credentials.env

.PHONY: tests app truncate_ingest_data ingest_data_rds ingest_data_sqlite create_db_rds create_db_sqlite model featurize download_data upload_data upload_raw_data raw_xml raw_data_from_api game_ids clean clean_raw_data

### RAW JSON DATA FETCH
data/external/games.json: config/config.yml
	docker run --mount type=bind,source="`pwd`",target=/app/ python_env src/acquire.py -c=${CONFIG_PATH} -o=${OUTPUT_PATH}

raw_data_from_api: data/external/games.json config/config.yml

### S3
upload_data: raw_data_from_api config/config.yml
	docker run --env-file=${AWS_CREDENTIALS} --mount type=bind,source="`pwd`",target=/app/ python_env src/upload.py -c=${CONFIG_PATH} -lfp=${UPLOAD_PATH}

data/games.json: upload_data
	docker run --env-file=${AWS_CREDENTIALS} --mount type=bind,source="`pwd`",target=/app/ python_env src/download.py -c=${CONFIG_PATH} -lfp=${DOWNLOAD_PATH}
download_data: data/games.json

### SINGLE DOCKER RUN COMMAND FOR DOWNLOAD, FEATURIZE, and TRAIN MODEL #######
pipeline:
	docker run -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY --mount type=bind,source="`pwd`",target=/app/ python_env run.py -lfp=${DOWNLOAD_PATH} -c=${CONFIG_PATH} -o=${CLUSTERED_DATA_PATH} -mo=${MODEL_OUTPUT_PATH}


### FEATURE GENERATION & MODELLING
data/games_featurized.json: download_data
	docker run --mount type=bind,source="`pwd`",target=/app/ python_env src/featurize.py -i=${DOWNLOAD_PATH} -c=${CONFIG_PATH} -o=${FEATURIZED_DATA_PATH}
featurize: data/games_featurized.json

data/games_clustered.json: featurize
	docker run --mount type=bind,source="`pwd`",target=/app/ python_env src/model.py -i=${FEATURIZED_DATA_PATH} -c=${CONFIG_PATH} -o=${CLUSTERED_DATA_PATH} -mo=${MODEL_OUTPUT_PATH}
model: data/games_clustered.json models/kmeans.pkl

### DATATABLES CREATION
data/boardgames.db:
	docker run -e SQLALCHEMY_DATABASE_URI=${SQLALCHEMY_DATABASE_URI} --mount type=bind,source="`pwd`",target=/app/ python_env ingest.py create_db

create_db_sqlite: data/boardgames.db

create_db_rds:
	docker run --env-file=${AWS_CREDENTIALS} -e MYSQL_USER=${MYSQL_USER} -e MYSQL_PASSWORD=${MYSQL_PASSWORD} -e MYSQL_HOST=${MYSQL_HOST} -e MYSQL_PORT=${MYSQL_PORT} -e MYSQL_DATABASE=${MYSQL_DATABASE} --mount type=bind,source="`pwd`",target=/app/ python_env ingest.py create_db


### INGESTION
ingest_data_sqlite: create_db_sqlite
	docker run  -e SQLALCHEMY_DATABASE_URI=${SQLALCHEMY_DATABASE_URI} --mount type=bind,source="`pwd`",target=/app/ python_env ingest.py ingest


ingest_data_rds: create_db_rds
	docker run --env-file=${AWS_CREDENTIALS} -e MYSQL_USER=${MYSQL_USER} -e MYSQL_PASSWORD=${MYSQL_PASSWORD} -e MYSQL_HOST=${MYSQL_HOST} -e MYSQL_PORT=${MYSQL_PORT} -e MYSQL_DATABASE=${MYSQL_DATABASE} --mount type=bind,source="`pwd`",target=/app/ python_env ingest.py ingest

### FLASK APP
app:
	docker run -it -e SQLALCHEMY_DATABASE_URI --mount type=bind,source="`pwd`",target=/app/ -p 5000:5000 --name test web_app

### UNIT TESTS
tests:
	docker run --mount type=bind,source="`pwd`",target=/app/ python_env -m pytest


### HELPER COMMANDS
truncate_ingest_data:
	docker run --env-file=${AWS_CREDENTIALS} -e MYSQL_USER=${MYSQL_USER} -e MYSQL_PASSWORD=${MYSQL_PASSWORD} -e MYSQL_HOST=${MYSQL_HOST} -e MYSQL_PORT=${MYSQL_PORT} -e MYSQL_DATABASE=${MYSQL_DATABASE} --mount type=bind,source="`pwd`",target=/app/ python_env ingest.py ingest -t

clean:
	rm data/external/games.json
	rm data/games.json
	rm data/boardgames.db
	rm data/games_clustered.json
	rm data/games_featurized.json
	rm models/kmeans.pkl
	rm models/kmeans.txt

### RAW DATA COMMANDS
data/game_ids.txt:
	docker run --mount type=bind,source="`pwd`",target=/app/ python_env src/fetch_game_ids.py -c=${CONFIG_PATH}

game_ids: data/game_ids.txt

data/raw_data.xml:
	docker run --mount type=bind,source="`pwd`",target=/app/ python_env src/fetch_raw_xml.py

raw_xml: game_ids data/raw_data.xml

upload_raw_data: data/game_ids.txt data/raw_data.xml
	docker run --env-file=${AWS_CREDENTIALS} --mount type=bind,source="`pwd`",target=/app/ python_env src/upload.py -c=config/config_raw_xml.yml -lfp=./data/raw_data.xml
	docker run --env-file=${AWS_CREDENTIALS} --mount type=bind,source="`pwd`",target=/app/ python_env src/upload.py -c=config/config_game_ids.yml -lfp=./data/game_ids.txt

clean_raw_data:
	rm data/game_ids.txt
	rm data/raw_data.xml