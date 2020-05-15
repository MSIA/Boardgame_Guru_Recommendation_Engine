CONFIG_PATH=config/config.yml
OUTPUT_PATH=data/external/games.json
UPLOAD_PATH=data/external/games.json
DOWNLOAD_PATH=data/games.json
AWS_CREDENTIALS=config/aws_credentials.env
LOCAL_DATABASE_PATH="sqlite:///data/boardgames.db"

.PHONY: truncate_ingest_data ingest_data_rds ingest_data_sqlite create_db_rds create_db_sqlite download_data upload_data raw_data_from_api clean

data/external/games.json: config/config.yml
	docker run --mount type=bind,source="`pwd`",target=/app/ python_env src/acquire.py -c=${CONFIG_PATH} -o=${OUTPUT_PATH}

raw_data_from_api: data/external/games.json config/config.yml

upload_data: raw_data_from_api config/config.yml
	docker run --env-file=${AWS_CREDENTIALS} --mount type=bind,source="`pwd`",target=/app/ python_env src/upload.py -c=${CONFIG_PATH} -lfp=${UPLOAD_PATH}

data/games.json: upload_data
	docker run --env-file=${AWS_CREDENTIALS} --mount type=bind,source="`pwd`",target=/app/ python_env src/download.py -c=${CONFIG_PATH} -lfp=${DOWNLOAD_PATH}

download_data: data/games.json

data/boardgames.db: download_data
	docker run --env-file=${AWS_CREDENTIALS} --mount type=bind,source="`pwd`",target=/app/ python_env ingest.py create_db --engine_string=${LOCAL_DATABASE_PATH}

create_db_sqlite: data/boardgames.db

create_db_rds: download_data
	docker run --env-file=${AWS_CREDENTIALS} -e MYSQL_USER=${MYSQL_USER} -e MYSQL_PASSWORD=${MYSQL_PASSWORD} -e MYSQL_HOST=${MYSQL_HOST} -e MYSQL_PORT=${MYSQL_PORT} -e MYSQL_DATABASE=${MYSQL_DATABASE} --mount type=bind,source="`pwd`",target=/app/ python_env ingest.py create_db

ingest_data_sqlite: create_db_sqlite
	docker run --env-file=${AWS_CREDENTIALS}  --mount type=bind,source="`pwd`",target=/app/ python_env ingest.py ingest

ingest_data_rds: create_db_rds
	docker run --env-file=${AWS_CREDENTIALS} -e MYSQL_USER=${MYSQL_USER} -e MYSQL_PASSWORD=${MYSQL_PASSWORD} -e MYSQL_HOST=${MYSQL_HOST} -e MYSQL_PORT=${MYSQL_PORT} -e MYSQL_DATABASE=${MYSQL_DATABASE} --mount type=bind,source="`pwd`",target=/app/ python_env ingest.py ingest

truncate_ingest_data:
	docker run --env-file=${AWS_CREDENTIALS} -e MYSQL_USER=${MYSQL_USER} -e MYSQL_PASSWORD=${MYSQL_PASSWORD} -e MYSQL_HOST=${MYSQL_HOST} -e MYSQL_PORT=${MYSQL_PORT} -e MYSQL_DATABASE=${MYSQL_DATABASE} --mount type=bind,source="`pwd`",target=/app/ python_env ingest.py ingest -t

clean:
	rm data/external/games.json
	rm data/games.json
	rm data/boardgames.db