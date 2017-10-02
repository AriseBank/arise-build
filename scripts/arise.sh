#!/bin/bash

# shellcheck disable=SC2129

cd "$(cd -P -- "$(dirname -- "$0")" && pwd -P)" || exit 2

if [ ! -f "$(pwd)/app.js" ]; then
	echo "Error: Arise installation was not found. Exiting."
	exit 1
fi

if [ "$USER" == "root" ]; then
	echo "Error: Arise should not be run be as root. Exiting."
	exit 1
fi

# shellcheck disable=SC1090
. "$(pwd)/shared.sh"
# shellcheck disable=SC1090
. "$(pwd)/env.sh"


PM2_CONFIG="$(pwd)/etc/pm2-arise.json"
PM2_APP="$(grep "name" "$PM2_CONFIG" | cut -d'"' -f4)" >> /dev/null
ARISE_CONFIG="$(grep "config" "$PM2_CONFIG" | cut -d'"' -f4 | cut -d' ' -f2)" >> /dev/null
ARISE_LOGS="$(grep "logFileName" "$ARISE_CONFIG" | cut -f 4 -d'"')"

LOGS_DIR="$(pwd)/logs"

# Allocates variables for use later, reusable for changing pm2 config.
config() {
DB_NAME="$(grep "database" "$ARISE_CONFIG" | cut -f 4 -d '"')"
DB_PORT="$(grep "port" "$ARISE_CONFIG" -m2 | tail -n1 |cut -f 1 -d ',' | cut -f 2 -d ':')"
DB_USER="$USER"
DB_PASS="password"
DB_DATA="$(pwd)/pgsql/data"
DB_LOG_FILE="$LOGS_DIR/pgsql.log"
DB_SNAPSHOT="blockchain.db.gz"
DB_DOWNLOAD=Y

REDIS_CONFIG="$(pwd)/etc/redis.conf"
REDIS_BIN="$(pwd)/bin/redis-server"
REDIS_CLI="$(pwd)/bin/redis-cli"
REDIS_ENABLED="$(grep "cacheEnabled" "$ARISE_CONFIG" | cut -f 2 -d ':' |  sed 's: ::g' | cut -f 1 -d ',')"
REDIS_PORT="$(grep "port" "$ARISE_CONFIG" -m3 | sed -n 3p | cut -f 2 -d':' | sed 's: ::g' | cut -f 1 -d ',')"
REDIS_PASSWORD="$(grep "password" "$ARISE_CONFIG" -m2 | sed -n 2p | cut -f 2 -d ":" | cut -f 1 -d ',' | sed 's: ::g')"
REDIS_PID="$(pwd)/redis/redis_6380.pid"
}

#sets all of the variables
config

SH_LOG_FILE="$LOGS_DIR/arise.out"


# Setup logging
exec > >(tee -ia "$SH_LOG_FILE")
exec 2>&1

################################################################################

blockheight() {
	DB_HEIGHT="$(psql -d "$DB_NAME" -t -p "$DB_PORT" -c 'select height from blocks order by height desc limit 1;')"
	HEIGHT="${DB_HEIGHT:- Unavailable}"
	echo -e "Current Block Height:" "$HEIGHT"
}

network() {
	# shellcheck disable=SC2143
	if [ "$(grep "da3ed6a45429278bac2666961289ca17ad86595d33b31037615d4b8e8f158bba" "$ARISE_CONFIG" )" ];then
		NETWORK="test"
	elif [ "$(grep "6cb2ba846e876f5dc68d95b28b292b81f9c538b99fd9c968eee5d94c3d4dc3a6" "$ARISE_CONFIG")" ];then
		NETWORK="main"
	else
		NETWORK="local"
	fi
	echo -e 'Arise configured for '"$NETWORK"' network\n' >> "$SH_LOG_FILE" 2>&1
}

create_user() {
	# shellcheck disable=SC2129
	dropuser --if-exists "$DB_USER" >> "$SH_LOG_FILE" 2>&1
	createuser --createdb "$DB_USER" >> "$SH_LOG_FILE" 2>&1
	if ! psql -qd postgres -c "ALTER USER $DB_USER WITH PASSWORD '$DB_PASS';" >> "$SH_LOG_FILE" 2>&1; then
		echo "X Failed to create Postgresql user."
		exit 1
	else
		echo "√ Postgresql user created successfully."
	fi
}

create_database() {
	# shellcheck disable=SC2129
	dropdb --if-exists "$DB_NAME" >> "$SH_LOG_FILE" 2>&1

	if ! createdb "$DB_NAME" >> "$SH_LOG_FILE" 2>&1; then
		echo "X Failed to create Postgresql database."
		exit 1
	else
		echo "√ Postgresql database created successfully."
	fi
}

populate_database() {

	if psql -ltAq | grep -q "^$DB_NAME|" >> "$SH_LOG_FILE" 2>&1; then
		download_blockchain
		restore_blockchain
	fi
}

download_blockchain() {
	if [ "$DB_DOWNLOAD" = "Y" ]; then
		rm -f "$DB_SNAPSHOT"
		if [ "$BLOCKCHAIN_URL" = "" ]; then
			BLOCKCHAIN_URL="https://downloads.arise.io/arise/$NETWORK"
		fi
		echo '√ Downloading '"$DB_SNAPSHOT"' from '"$BLOCKCHAIN_URL"

		if ! curl --progress-bar -o "$DB_SNAPSHOT" "$BLOCKCHAIN_URL/$DB_SNAPSHOT"; then
			rm -f "$DB_SNAPSHOT"
			echo "X Failed to download blockchain snapshot."
			exit 1
		else
			# Required to clean up ugly curl output in the logs
			sed -i -e '/[#]/d' "$SH_LOG_FILE"
			echo "√ Blockchain snapshot downloaded successfully."
		fi
	else
		echo -e "√ Using Local Snapshot."
	fi
}

restore_blockchain() {
	echo 'Restoring blockchain with '"$DB_SNAPSHOT"

	if ! gunzip -fcq "$DB_SNAPSHOT" | psql -q -U "$DB_USER" -d "$DB_NAME" >> "$SH_LOG_FILE" 2>&1; then
		echo "X Failed to restore blockchain."
		exit 1
	else
		echo "√ Blockchain restored successfully."
	fi
}

autostart_cron() {
	local cmd="crontab"

	if ! command -v "$cmd" > /dev/null 2>&1; then
		echo "X Failed to execute crontab."
		return 1
	fi

	crontab=$($cmd -l 2> /dev/null | sed '/arise\.sh start/d' 2> /dev/null)

	crontab=$(cat <<-EOF
		$crontab
		@reboot $(command -v "bash") $(pwd)/arise.sh start > $(pwd)/cron.log 2>&1
EOF
	)

	if ! printf "%s\n" "$crontab" | $cmd - >> "$SH_LOG_FILE" 2>&1; then
		echo "X Failed to update crontab."
		return 1
	else
		echo "√ Crontab updated successfully."
		return 0
	fi
}

coldstart_arise() {
	stop_arise >> "$SH_LOG_FILE" 2>&1
	stop_postgresql >> "$SH_LOG_FILE" 2>&1
	rm -rf "$DB_DATA"
	pg_ctl initdb -D "$DB_DATA" >> "$SH_LOG_FILE" 2>&1
	sleep 2
	start_postgresql
	sleep 1
	create_user
	create_database
	populate_database
	autostart_cron
	start_arise
}

start_postgresql() {
	if pgrep -x "postgres" > /dev/null 2>&1; then
		echo "√ Postgresql is running."
	else
		if ! pg_ctl -D "$DB_DATA" -l "$DB_LOG_FILE" start >> "$SH_LOG_FILE" 2>&1; then
			echo "X Failed to start Postgresql."
			exit 1
		else
			echo "√ Postgresql started successfully."
		fi
	fi
}

stop_postgresql() {
	if ! pgrep -x "postgres" > /dev/null 2>&1; then
		echo "√ Postgresql is not running."
	else
		if pg_ctl -D "$DB_DATA" -l "$DB_LOG_FILE" stop >> "$SH_LOG_FILE" 2>&1; then
			echo "√ Postgresql stopped successfully."
			else
			echo "X Postgresql failed to stop."
		fi
		if pgrep -x "postgres" >> "$SH_LOG_FILE" 2>&1; then
			pkill -x postgres -9 >> "$SH_LOG_FILE" 2>&1;
			echo "√ Postgresql Killed."
		fi
	fi
}

start_redis() {
	if [[ "$REDIS_ENABLED" == 'true' ]]; then
		if [[ "$REDIS_PORT" == '6379' ]]; then
			echo "√ Using OS Redis-Server, skipping startup"
		elif [[ ! -f "$REDIS_PID" ]]; then

			if "$REDIS_BIN" "$REDIS_CONFIG"; then
				echo "√ Redis-Server started successfully."
			else
				echo "X Failed to start Redis-Server."
				exit 1
			fi
		else
			echo "√ Redis-Server is already running"
		fi
	fi
}

stop_redis() {
	if [[ "$REDIS_ENABLED" == 'true' ]]; then
		if [[ "$REDIS_PORT" == '6379' ]]; then
			echo "√ OS Redis-Server detected, skipping shutdown"
		elif [[ -f "$REDIS_PID" ]]; then

			if stop_redis_cmd; then
				echo "√ Redis-Server stopped successfully."
			else
				echo "X Failed to stop Redis-Server."
				REDIS_PID="$(tail -n1 "$REDIS_PID")"
				pkill -9 "$REDIS_PID"
				echo "√ Redis-Server killed"
			fi
		else
			echo "√ Redis-Server already stopped"
		fi
	fi
}

stop_redis_cmd(){
	# Necessary to pass the right password string to redis
	if [[ "$REDIS_PASSWORD" != null ]]; then
		"$REDIS_CLI" -p "$REDIS_PORT" "-a $REDIS_PASSWORD" shutdown
	else
		"$REDIS_CLI" -p "$REDIS_PORT" shutdown
	fi
}

start_arise() {
	start_redis
	if pm2 start "$PM2_CONFIG"  >> "$SH_LOG_FILE"; then
		echo "√ Arise started successfully."
		sleep 3
		check_status
	else
		echo "X Failed to start Arise."
	fi
}

stop_arise() {
	pm2 delete "$PM2_CONFIG" >> "$SH_LOG_FILE"
	echo "√ Arise stopped successfully."
	stop_redis
}

reload_arise() {
	echo "Stopping Arise to reload PM2 config"
	stop_arise
	start_arise
}

rebuild_arise() {
	create_database
	download_blockchain
	restore_blockchain
}

pm2_cleanup() {
	pm2 delete all
	pm2 kill
}

check_status() {
	PM2_PID="$(pm2 describe "$PM2_APP" | grep "pid path" | cut -d' ' -f14)" >> "$SH_LOG_FILE" 2>&1> /dev/null

	pm2 describe "$PM2_APP" >> "$SH_LOG_FILE"

	check_pid
	if [ "$STATUS" -eq 0  ]; then
		echo "√ Arise is running as PID: $PID"
		blockheight
	else
		echo "X Arise is not running"
		exit 1
	fi
}

check_pid() {
	if [ -f "$PM2_PID" ]; then
	read -r PID < "$PM2_PID" 2>&1 > /dev/null
	fi
	if [ ! -z "$PID" ]; then
		ps -p "$PID" > /dev/null 2>&1
		STATUS=$?
	else
		STATUS=1
	fi
}

tail_logs() {
	tail -f "$ARISE_LOGS"
}

help() {
	echo -e "\nCommand Options for Arise.sh"
	echo -e "\nAll options may be passed [-p <PM2-config.json>]"
	echo -e "\nstart_node                            Starts a Nodejs process for Arise"
	echo -e "start                                 Starts the Nodejs process and PostgreSQL Database for Arise"
	echo -e "stop_node                             Stops a Nodejs process for Arise"
	echo -e "stop                                  Stop the Nodejs process and PostgreSQL Database for Arise"
	echo -e "reload                                Restarts the Nodejs process for Arise"
	echo -e "rebuild [-u URL] [-f file.db.gz] [-0] Rebuilds the PostgreSQL database"
	echo -e "start_db                              Starts the PostgreSQL database"
	echo -e "stop_db                               Stops the PostgreSQL database"
	echo -e "coldstart                             Creates the PostgreSQL database and configures config.json for Arise"
	echo -e "logs                                  Displays and tails logs for Arise"
	echo -e "status                                Displays the status of the PID associated with Arise"
	echo -e "help                                  Displays this message"
}


parse_option() {
	OPTIND=2
	while getopts ":p:f:u:l:0" OPT; do
		case "$OPT" in
			p)
				if [ -f "$OPTARG" ]; then
					PM2_CONFIG="$OPTARG"
					PM2_APP="$(grep "name" "$PM2_CONFIG" | cut -d'"' -f4)"
					ARISE_CONFIG="$(grep ".json" "$PM2_CONFIG" | cut -d'"' -f4 | cut -d' ' -f2)" >> /dev/null
					# Resets all of the variables
					config
				else
					echo "PM2-config.json not found. Please verify the file exists and try again."
					exit 1
				fi ;;

			u)
				BLOCKCHAIN_URL="$OPTARG"
				;;

			f)
				DB_SNAPSHOT="$OPTARG"
				if [ -f "$OPTARG" ]; then
					DB_DOWNLOAD=N
				fi ;;

			0)
				DB_SNAPSHOT="$(pwd)/etc/blockchain.db.gz"
				DB_DOWNLOAD=N
				;;

			 :) echo 'Missing option argument for -'"$OPTARG" >&2; exit 1;;

			 *) echo 'Unimplemented option: -'"$OPTARG" >&2; exit 1;;
		esac
	done
}

parse_option "$@"
network

case $1 in
"coldstart")
	coldstart_arise
	;;
"start_node")
	start_arise
	;;
"start")
	start_postgresql
	sleep 2
	start_arise
	;;
"stop_node")
	stop_arise
	;;
"stop")
	stop_arise
	stop_postgresql
	;;
"reload")
	reload_arise
	;;
"rebuild")
	stop_arise
	sleep 1
	start_postgresql
	sleep 1
	rebuild_arise
	start_arise
	;;
"start_db")
	start_postgresql
	;;
"stop_db")
	stop_postgresql
	;;
"cleanup")
	pm2_cleanup
	;;
"status")
	check_status
	;;
"logs")
	tail_logs
	;;
"help")
	help
	;;
*)
	echo "Error: Unrecognized command."
	echo ""
	echo "Available commands are: start stop start_node stop_node start_db stop_db reload rebuild coldstart logs status help"
	help
	;;
esac

# Required to clean up colour characters that don't translate well from tee
sed -i -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g" "$SH_LOG_FILE"
