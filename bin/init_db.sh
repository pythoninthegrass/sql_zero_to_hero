#!/usr/bin/env bash

set -e

# env vars
POSTGRES_HOST=${DB_URL:-localhost}
POSTGRES_DB=${DB_NAME:-postgres}
POSTGRES_USER=${DB_USER:-postgres}
POSTGRES_PASSWORD=${DB_PASSWORD:-postgres}
POSTGRES_PORT=${DB_PORT:-5432}
DB_NAME="${POSTGRES_DB}"
DB_FILENAME="${DB_FILENAME:-/backup/exercises.tar}"
DROP_DB=${DROP_DB:-false}

# help message
help() {
	cat <<-DESCRIPTION >&2
	USAGE:
	    $(basename $0) [OPTIONS]

	OPTIONS:
	    -d --drop      Drop the database before restoring
	    -f --file      Specify the backup file to restore
	    -h --help      Show this help message
	DESCRIPTION
}

# trap 2, 3, 15 signals
trap 'exit' SIGINT SIGQUIT SIGTERM

# backup files
mapfile -t backups < <(ls /backup/*.tar)

found=false
for backup in "${backups[@]}"; do
	if [[ "$backup" == "$DB_FILENAME" ]]; then
		found=true
		break
	fi
done

if [[ ! "$found" ]]; then
	backups+=("${DB_FILENAME}")
fi

conn() {
	PGPASSWORD="$POSTGRES_PASSWORD" \
	psql \
		-U "$POSTGRES_USER" \
		-h "$POSTGRES_HOST" \
		-p "$POSTGRES_PORT" \
		-d "$POSTGRES_DB" \
		"$@"
}

# Check if the database is empty
is_db_empty() {
	local db_name
	local table_count
	local query

	db_name="$1"
	query=$(cat <<-EOF
		SELECT COUNT(*)
		FROM information_schema.tables
		WHERE table_schema = 'public'
	EOF
	)

	table_count=$(conn -tAc "$query")

	[ "$table_count" -eq 0 ]
}

# Wait for the database to be ready
health_check() {
	local interval
	local timeout
	local retries
	local cmd

	retries=5
	interval=10
	timeout=5

	cmd="PGPASSWORD=$POSTGRES_PASSWORD \
		pg_isready \
			-U $POSTGRES_USER \
			-h $POSTGRES_HOST \
			-p $POSTGRES_PORT \
			-d $POSTGRES_DB \
			-t $timeout"

	while ! eval "$cmd"; do
		echo "Waiting for database to be ready..."
		sleep "$interval"
		retries=$((retries - 1))
		if [ "$retries" -eq 0 ]; then
			echo "Timeout reached. Database is not ready."
			exit 1
		fi
	done
	echo "Database is ready."
}

create_db() {
	local db_name

	db_name="$1"

	echo "Creating database $db_name..."
	conn <<< "CREATE DATABASE $db_name;"
	echo "Database $db_name created successfully."
}

drop_db() {
	local db_name

	db_name="$1"

	if [[ "${DROP_DB,,}" =~ ^(true|yes|y|1)$ ]]; then
		echo "Dropping database $db_name..."
		conn <<< "DROP DATABASE IF EXISTS $db_name;"
		echo "Database $db_name dropped successfully."
		create_db "$db_name"
	else
		echo "Skipping database drop (DROP_DB is not set to true)."
	fi
}

restore_db() {
	local file_path
	local db_name

	file_path="$1"
	db_name="$2"

	if [[ "${DROP_DB,,}" =~ ^(true|yes|y|1)$ ]]; then
		drop_db "$db_name"
	else
		create_db "$db_name"
	fi

	echo "Restoring backup to $db_name..."
	if [ -f "$file_path" ]; then
		conn <<< "DROP SCHEMA IF EXISTS public CASCADE; CREATE SCHEMA public;"

		# Check if the file is a custom-format dump
		if file "$file_path" | grep -q "PostgreSQL custom database dump"; then
			echo "Detected custom-format dump. Using pg_restore..."
			PGPASSWORD="$POSTGRES_PASSWORD" \
			pg_restore \
				-U "$POSTGRES_USER" \
				-h "$POSTGRES_HOST" \
				-p "$POSTGRES_PORT" \
				-d "$db_name" \
				-v "$file_path"
		else
			echo "Detected plain SQL dump. Using psql..."
			conn -d "$db_name" < "$file_path"
		fi

		echo "Database restored successfully to $db_name."
	else
		echo "No backup file found at $file_path. Skipping restore."
	fi
}

parse_options() {
	local args=()

	for arg in "$@"; do
		case "$arg" in
			--drop)
				args+=(-d)
				;;
			--file)
				args+=(-f)
				;;
			--help)
				args+=(-h)
				;;
			*)
				args+=("$arg")
				;;
		esac
	done

	set -- "${args[@]}"

	while getopts ":df:h" opt; do
		case ${opt} in
			d )
				DROP_DB=true
				;;
			f )
				DB_FILENAME=$OPTARG
				;;
			h )
				help
				exit 0
				;;
			\? )
				echo "Invalid option: $OPTARG" 1>&2
				help
				exit 1
				;;
			: )
				echo "Invalid option: $OPTARG requires an argument" 1>&2
				help
				exit 1
				;;
		esac
	done
	shift $((OPTIND -1))
}

main() {
	parse_options "$@"
	health_check
	for backup in "${backups[@]}"; do
		backup_name=$(basename "$backup")
		backup_db_name=$(echo "$backup_name" | cut -d'.' -f1)
		restore_db "$backup" "$backup_db_name"
	done
}

main "$@"
