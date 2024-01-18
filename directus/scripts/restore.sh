#!/bin/sh
#
# AUTHOR: Ankur Kumar
# GITHUB: github.com/SirJager
# PURPOSE: restore postgres database from backup file to docker container on server

USERNAME=""         # user of server
HOSTNAME=""         # hostname of server
DATABASE_NAME=""    # postgres database name running on container
DATABASE_USER=""    # postgres database user
CONTAINER_NAME=""   # container name, in which database is there
RESTORE_FILEPATH="" # local backup file path (<timestamp>.tar.gz)
ENABLE_LOGS=""

# This assings all above vars for cli args
while [ $# -gt 0 ]; do
	case "$1" in
	-u | -user | -username | --u | --user | --username)
		shift
		USERNAME="$1"
		shift
		;;
	-h | -host | -hostname | --h | --host | --hostname)
		shift
		HOSTNAME="$1"
		shift
		;;
	-cn | -container | --cn | --container)
		shift
		CONTAINER_NAME="$1"
		shift
		;;
	-db | -database | -dbname | -database-name | --db | --database | --dbname | --database-name)
		shift
		DATABASE_NAME="$1"
		shift
		;;
	-du | -dbuser | -database-user | --du | --dbuser | --database-user)
		shift
		DATABASE_USER="$1"
		shift
		;;
	-rf | -restore | -restore-file | --rf | --restore | --restore-file)
		shift
		RESTORE_FILEPATH="$1"
		shift
		;;
	-l | -log | -logs | --l | --log | --logs)
		ENABLE_LOGS="true"
		shift
		;;
	*)
		shift
		;;
	esac
done

show_usage() {
	echo "Assuming SSH is already set up for the provided username and hostname"
	echo "Make sure database container is already running on server"
	echo
	echo "Usage: $0 [options]"
	echo "Options:"
	echo "  -u, --user, --username     Specify username."
	echo "  -h, --host, --hostname     Specify hostname."
	echo "  -db, --database            Specify database name."
	echo "  -du, --dbuser              Specify database user."
	echo "  -cn, --container           Specify container name."
	echo "  -rf, --restore-file        Specify restore filepath."
	echo "  -l, --logs                 Show migration logs."
}

# Function to log messages
log() {
	echo "🚀 $(date +'%d-%m-%Y %H:%M:%S') - $1"
}

check_non_empty() {
	var_name="$1"
	var_value="$2"
	if [ -z "$var_value" ]; then
		echo "Error: $var_name is empty."
		show_usage
		exit 1
	fi
}

# Check required variables
check_non_empty "USERNAME" "$USERNAME"
check_non_empty "HOSTNAME" "$HOSTNAME"
check_non_empty "DATABASE_NAME" "$DATABASE_NAME"
check_non_empty "DATABASE_USER" "$DATABASE_USER"
check_non_empty "CONTAINER_NAME" "$CONTAINER_NAME"
check_non_empty "RESTORE_FILEPATH" "$RESTORE_FILEPATH"

if [ ! -f "$RESTORE_FILEPATH" ]; then
	log "Error: Restore file '$RESTORE_FILEPATH' does not exist."
	exit 1
fi

ADDRESS="$USERNAME@$HOSTNAME"
SQL_FILENAME=$(basename "$RESTORE_FILEPATH" .sql.tar.gz)

upload_restore_file_to_server() {
	if scp -q "$RESTORE_FILEPATH" "$ADDRESS:/tmp/"; then
		return 0
	else
		return 1
	fi
}

uncompress_restore_file_on_server() {
	if ssh "$ADDRESS" "\
    rm -rf /tmp/$SQL_FILENAME/ && \
    mkdir -p /tmp/$SQL_FILENAME && \
    tar -xf /tmp/$SQL_FILENAME.sql.tar.gz -C /tmp/$SQL_FILENAME && \
    rm -f /tmp/$SQL_FILENAME.sql.tar.gz"; then
		return 0
	else
		return 1
	fi
}

copy_rawsql_file_to_docker_container() {
	if ssh "$ADDRESS" "docker cp /tmp/$SQL_FILENAME/tmp/$SQL_FILENAME.sql $CONTAINER_NAME:/tmp && \
    rm -rf /tmp/$SQL_FILENAME*"; then
		return 0
	else
		return 1
	fi
}

make_migration_script_for_docker_container() {
	string=$(
		cat <<EOF
#!/bin/bash
psql -U \"$DATABASE_USER\" template1 -c 'DROP DATABASE IF EXISTS \"$DATABASE_NAME\";'
psql -U \"$DATABASE_USER\" template1 -c 'CREATE DATABASE \"$DATABASE_NAME\" with owner \"$DATABASE_USER\";'
psql -U \"$DATABASE_USER\" \"$DATABASE_NAME\" < /tmp/$SQL_FILENAME.sql
EOF
	)
	if ssh "$ADDRESS" "echo \"$string\" > /tmp/$SQL_FILENAME.sh && \
    docker cp /tmp/$SQL_FILENAME.sh $CONTAINER_NAME:/tmp && \
    docker exec $CONTAINER_NAME chmod +x /tmp/$SQL_FILENAME.sh && \
    rm -rf /tmp/$SQL_FILENAME*"; then
		return 0
	else
		return 1
	fi
}

run_sql_migration_on_container() {
	command="docker exec -i $CONTAINER_NAME  bash /tmp/$SQL_FILENAME.sh"
	[ $ENABLE_LOGS = "true" ] && command="$command  2> /dev/null"
	if ssh "$ADDRESS" "$command"; then
		return 0
	else
		return 1
	fi
}

run_restore() {
	if upload_restore_file_to_server; then
		log "Uploaded restore file to temporary location on server"

		if uncompress_restore_file_on_server; then
			log "Extracted raw sql file from restore file on server"

			if copy_rawsql_file_to_docker_container; then
				log "Copied raw sql file to docker container on server"

				if make_migration_script_for_docker_container; then
					log "Created a migration script inside docker container"

					if run_sql_migration_on_container "$ADDRESS" "$FILENAME"; then
						log "Successfully restored database inside docker container running on server"

					else
						log "Failed to ran sql migration on databaes inside container on server"
					fi

				else
					log "Failed to create a migration script inside docker container"
				fi

			else
				log "Failed to copy raw sql file to docker container on server"
			fi
		else
			log "Failed to extract raw sql file from restore file on server"
		fi
	else
		log "Failed to upload restore file to server"
	fi

}

run_restore
