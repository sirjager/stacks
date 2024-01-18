#!/bin/bash
#
# AUTHOR: Ankur Kumar
# GITHUB: github.com/SirJager
# PURPOSE: backup postgres database from server running inside docker.

TAG=""                     # folder name for what project/database backup is being done
USERNAME=""                # user of server
HOSTNAME=""                # hostname of server
DATABASE_NAME=""           # postgres database name running on container
DATABASE_USER=""           # postgres database user
CONTAINER_NAME=""          # container name, in which database is there
BACKUP_DIRECTORY=""        # local backup directory, where backup is saved
BACKUP_MAX_COUNT=1024      # Total number of backups to keep in local backup directory
LOGFILE="$HOME/backup.log" # Logfile path

# This assings all above vars for cli args
while [ $# -gt 0 ]; do
	case "$1" in
	-t | -tag | --t | --tag)
		shift
		TAG="$1"
		shift
		;;

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
	-bd | -out | -backup-dir | -backup-directory | --bd | --out | --backup-dir | --backup-directory)
		shift
		BACKUP_DIRECTORY="$1"
		shift
		;;
	-bc | -count | -backup-count | --bc | --count | --backup-count)
		shift
		BACKUP_MAX_COUNT="$1"
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
	echo "  -bd, --backup-dir          Specify backup directory."
	echo "  -bc, --backup-count        Specify backup max count."
}

# Function to log messages
touch "$LOGFILE"

log() {
	echo "🔶 $(date +'%d-%m-%Y %H:%M:%S') - $1" >>"$LOGFILE"
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
check_non_empty "TAG" "$TAG"
check_non_empty "USERNAME" "$USERNAME"
check_non_empty "HOSTNAME" "$HOSTNAME"
check_non_empty "DATABASE_NAME" "$DATABASE_NAME"
check_non_empty "DATABASE_USER" "$DATABASE_USER"
check_non_empty "CONTAINER_NAME" "$CONTAINER_NAME"
check_non_empty "BACKUP_DIRECTORY" "$BACKUP_DIRECTORY"
check_non_empty "BACKUP_MAX_COUNT" "$BACKUP_MAX_COUNT"

BACKUP_DIRECTORY="$BACKUP_DIRECTORY/$HOSTNAME/$TAG"
TIMESTAMP=$(date +'%d-%m-%Y-%H-%M-%S')
BACKUP_FILE="${TIMESTAMP}.sql"

[ ! -d "$BACKUP_DIRECTORY" ] && mkdir -p "$BACKUP_DIRECTORY"
# Add a separator and three lines gap
echo "----------------------------------------" >>"$LOGFILE"
echo "🔶 $(date +'%d-%m-%Y %H:%M:%S') - $BACKUP_FILE" >>"$LOGFILE"
echo "----------------------------------------\n\n" >>"$LOGFILE"

keep_only_limited_backups_locally() {
	cd "$BACKUP_DIRECTORY" || return
	# NOTE: List all backup files, sorted by name (oldest first)
	backups=$(ls -t "$BACKUP_DIRECTORY"/*.tar.gz)
	count=$(echo "$backups" | wc -l)
	# NOTE: Checking if number of backups exceeds the backup limits
	if [ $count -gt $BACKUP_MAX_COUNT ]; then
		# NOTE: Calculate how many backups to delete
		delete_count=$((count - BACKUP_MAX_COUNT))
		# NOTE: Delete the oldest backups
		echo "$backups" | tail -n $delete_count | xargs rm
		return 0 # Deleted 1 oldest backup
	fi
	return 1 # Did not deleted any backup
}

create_backup_inside_container() {
	# 1: ssh-address 2: backupfile-path
	if ssh "$1" "docker exec $CONTAINER_NAME pg_dumpall -U $DATABASE_USER -f $2"; then
		return 0 # success
	else
		return 1 # failed
	fi
}

copy_backup_outside_container() {
	# 1: ssh-address 2: backupfile-path
	if ssh "$1" "docker cp $CONTAINER_NAME:$2 $2"; then
		# after copying backup file outside the container
		# we will delete from conatiner
		ssh "$1" "docker exec $CONTAINER_NAME rm $2"
		return 0
	else
		return 1
	fi
}

compress_backup_on_server() {
	# 1: ssh-address 2: backupfile-path
	if ssh "$1" "tar -czf $2.tar.gz $2 2>/dev/null"; then
		return 0
	else
		return 1
	fi
}

download_compressed_backup_locally() {
	# 1: ssh-address 2: backupfile-path  3: local backup directory
	if scp -q "$1:$2.tar.gz" "$3"; then
		return 0
	else
		return 1
	fi
}

perform_server_temp_cleanup() {
	# 1: ssh-address 2: backupfile-path
	if ssh "$1" "rm $2 $2.tar.gz"; then
		return 0
	else
		return 1
	fi
}

run_backup() {
	ADDRESS="$USERNAME@$HOSTNAME"
	TEMP_FILE="/tmp/$BACKUP_FILE"

	if create_backup_inside_container "$ADDRESS" "$TEMP_FILE"; then
		log "Database backup successfully exported inside container"

		if copy_backup_outside_container "$ADDRESS" "$TEMP_FILE"; then
			log "Database backup successfully copied from docker to server"

			if compress_backup_on_server "$ADDRESS" "$TEMP_FILE"; then
				log "Backup successfully compressed on server"

				if download_compressed_backup_locally "$ADDRESS" "$TEMP_FILE" "$BACKUP_DIRECTORY"; then
					# NOTE: Successfull
					log "Backup successfully copied from server to backup directory: $BACKUP_DIRECTORY"
					notify-send "Backup successfully copied from server to backup directory" "$BACKUP_DIRECTORY"
					if keep_only_limited_backups_locally; then
						# Last
						perform_server_temp_cleanup "$ADDRESS" "$TEMP_FILE"
						log "Oldest backup deleted to keep limited backups from: $BACKUP_DIRECTORY"
						return 0
					fi
				else
					log "Failed to copy backup to local backup dir: $BACKUP_DIRECTORY"
				fi
			else
				log "Failed to compress back on server: $TEMP_FILE.tar.gz"
			fi
		else
			log "Failed to copy backup file from docker to server: $CONTAINER_NAME:$TEMP_FILE"
		fi
	else
		log "Error creating database backup export: $TEMP_FILE"
	fi
	perform_server_temp_cleanup "$ADDRESS" "$TEMP_FILE"
	return 1
}

run_backup
