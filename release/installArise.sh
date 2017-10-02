#!/bin/bash
#
# arisebank/arise-build
# Copyright (C) 2017 Arise Foundation
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
######################################################################

# Variable Declaration
UNAME=$(uname)-$(uname -m)
DEFAULT_ARISE_LOCATION=$(pwd)
DEFAULT_RELEASE=main
DEFAULT_SYNC=no
LOG_FILE=installArise.out

# Setup logging
exec > >(tee -ia $LOG_FILE)
exec 2>&1

export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export LANGUAGE=en_US.UTF-8

# Verification Checks
if [ "$USER" == "root" ]; then
	echo "Error: Arise should not be installed be as root. Exiting."
	exit 1
fi

prereq_checks() {
	echo -e "Checking prerequisites:"

	if [ -x "$(command -v curl)" ]; then
		echo -e "curl is installed.\t\t\t\t\t$(tput setaf 2)Passed$(tput sgr0)"
	else
		echo -e "\ncurl is not installed.\t\t\t\t\t$(tput setaf 1)Failed$(tput sgr0)"
			echo -e "\nPlease follow the Prerequisites at: https://docs.arisecoin.com/docs/core-pre-installation-binary"
		exit 2
	fi

	if [ -x "$(command -v tar)" ]; then
		echo -e "Tar is installed.\t\t\t\t\t$(tput setaf 2)Passed$(tput sgr0)"
	else
		echo -e "\ntar is not installed.\t\t\t\t\t$(tput setaf 1)Failed$(tput sgr0)"
			echo -e "\nPlease follow the Prerequisites at: https://docs.arisecoin.com/docs/core-pre-installation-binary"
		exit 2
	fi

	if [ -x "$(command -v wget)" ]; then
		echo -e "Wget is installed.\t\t\t\t\t$(tput setaf 2)Passed$(tput sgr0)"
	else
		echo -e "\nWget is not installed.\t\t\t\t\t$(tput setaf 1)Failed$(tput sgr0)"
		echo -e "\nPlease follow the Prerequisites at: https://docs.arisecoin.com/docs/core-pre-installation-binary"
		exit 2
	fi

	if sudo -n true 2>/dev/null; then
		echo -e "Sudo is installed and authenticated.\t\t\t$(tput setaf 2)Passed$(tput sgr0)"
	else
		echo -e "Sudo is installed.\t\t\t\t\t$(tput setaf 2)Passed$(tput sgr0)"
		echo "Please provide sudo password for validation"
		if sudo -Sv -p ''; then
			echo -e "Sudo authenticated.\t\t\t\t\t$(tput setaf 2)Passed$(tput sgr0)"
		else
			echo -e "Unable to authenticate Sudo.\t\t\t\t\t$(tput setaf 1)Failed$(tput sgr0)"
			echo -e "\nPlease follow the Prerequisites at: https://docs.arisecoin.com/docs/core-pre-installation-binary"
			exit 2
		fi
	fi

	echo -e "$(tput setaf 2)All preqrequisites passed!$(tput sgr0)"
}

# Adding LC_ALL LANG and LANGUAGE to user profile
# shellcheck disable=SC2143
if [[ -f ~/.bash_profile && ! "$(grep "en_US.UTF-8" ~/.bash_profile)" ]]; then
	{ echo "LC_ALL=en_US.UTF-8";  echo "LANG=en_US.UTF-8";  echo "LANGUAGE=en_US.UTF-8"; } >> ~/.profile

elif [[ -f ~/.bash_profile && ! "$(grep "en_US.UTF-8" ~/.bash_profile)" ]]; then
	{ echo "LC_ALL=en_US.UTF-8";  echo "LANG=en_US.UTF-8";  echo "LANGUAGE=en_US.UTF-8"; } >> ~/.bash_profile
fi

user_prompts() {
	[ "$ARISE_LOCATION" ] || read -r -p "Where do you want to install Arise to? (Default $DEFAULT_ARISE_LOCATION): " ARISE_LOCATION
	ARISE_LOCATION=${ARISE_LOCATION:-$DEFAULT_ARISE_LOCATION}
	if [[ ! -r "$ARISE_LOCATION" ]]; then
		echo "$ARISE_LOCATION is not valid, please check and re-execute"
		exit 2;
	fi

	[ "$RELEASE" ] || read -r -p "Would you like to install the Main or Test Client? (Default $DEFAULT_RELEASE): " RELEASE
	RELEASE=${RELEASE:-$DEFAULT_RELEASE}
	if [[ ! "$RELEASE" == "main" && ! "$RELEASE" == "test" && ! "$RELEASE" == "dev" ]]; then
		echo "$RELEASE is not valid, please check and re-execute"
		exit 2;
	fi

	[ "$SYNC" ] || read -r -p "Would you like to synchronize from the Genesis Block? (Default $DEFAULT_SYNC): " SYNC
	SYNC=${SYNC:-$DEFAULT_SYNC}
	if [[ ! "$SYNC" == "no" && ! "$SYNC" == "yes" ]]; then
		echo "$SYNC is not valid, please check and re-execute"
		exit 2;
	fi
	ARISE_INSTALL="$ARISE_LOCATION"'/arise-'"$RELEASE"
}

ntp_checks() {
	# Install NTP or Chrony for Time Management - Physical Machines only
	if [[ "$(uname)" == "Linux" ]]; then
		if [[ -f "/etc/debian_version" &&  ! -f "/proc/user_beancounters" ]]; then
			if sudo pgrep -x "ntpd" > /dev/null; then
				echo "√ NTP is running"
			else
				echo "X NTP is not running"
				[ "$INSTALL_NTP" ] || read -r -n 1 -p "Would like to install NTP? (y/n): " REPLY
				if [[ "$INSTALL_NTP" || "$REPLY" =~ ^[Yy]$ ]]; then
					echo -e "\nInstalling NTP, please provide sudo password.\n"
					sudo apt-get install ntp ntpdate -yyq
					sudo service ntp stop
					sudo ntpdate pool.ntp.org
					sudo service ntp start
					if sudo pgrep -x "ntpd" > /dev/null; then
						echo "√ NTP is running"
					else
						echo -e "\nArise requires NTP running on Debian based systems. Please check /etc/ntp.conf and correct any issues."
						exit 0
					fi
				else
					echo -e "\nArise requires NTP on Debian based systems, exiting."
					exit 0
				fi
			fi # End Debian Checks
		elif [[ -f "/etc/redhat-RELEASE" &&  ! -f "/proc/user_beancounters" ]]; then
			if sudo pgrep -x "ntpd" > /dev/null; then
				echo "√ NTP is running"
			else
				if sudo pgrep -x "chronyd" > /dev/null; then
					echo "√ Chrony is running"
				else
					echo "X NTP and Chrony are not running"
					[ "$INSTALL_NTP" ] || read -r -n 1 -p "Would like to install NTP? (y/n): " REPLY
					if [[ "$INSTALL_NTP" || "$REPLY" =~ ^[Yy]$ ]]; then
						echo -e "\nInstalling NTP, please provide sudo password.\n"
						sudo yum -yq install ntp ntpdate ntp-doc
						sudo chkconfig ntpd on
						sudo service ntpd stop
						sudo ntpdate pool.ntp.org
						sudo service ntpd start
						if pgrep -x "ntpd" > /dev/null; then
							echo "√ NTP is running"
							else
							echo -e "\nArise requires NTP running on Debian based systems. Please check /etc/ntp.conf and correct any issues."
							exit 0
						fi
					else
						echo -e "\nArise requires NTP or Chrony on RHEL based systems, exiting."
						exit 0
					fi
				fi
			fi # End Redhat Checks
		elif [[ -f "/proc/user_beancounters" ]]; then
			echo "_ Running OpenVZ VM, NTP and Chrony are not required"
		fi
	elif [[ "$(uname)" == "Darwin" ]]; then
		if pgrep -x "ntpd" > /dev/null; then
			echo "√ NTP is running"
		else
			sudo launchctl load /System/Library/LaunchDaemons/org.ntp.ntpd.plist
			sleep 1
			if pgrep -x "ntpd" > /dev/null; then
				echo "√ NTP is running"
			else
				echo -e "\nNTP did not start, Please verify its configured on your system"
				exit 0
			fi
		fi  # End Darwin Checks
	fi # End NTP Checks
}

download_arise() {
	ARISE_VERSION=arise-$UNAME.tar.gz

	ARISE_DIR=$(echo "$ARISE_VERSION" | cut -d'.' -f1)

	rm -f "$ARISE_VERSION" "$ARISE_VERSION".SHA256 &> /dev/null

	echo -e "\nDownloading current Arise binaries: ""$ARISE_VERSION"

	curl --progress-bar -o "$ARISE_VERSION" "https://downloads.arise.io/arise/$RELEASE/$ARISE_VERSION"

	curl -s "https://downloads.arise.io/arise/$RELEASE/$ARISE_VERSION.SHA256" -o "$ARISE_VERSION".SHA256

	if [[ "$(uname)" == "Linux" ]]; then
		SHA256=$(sha256sum -c "$ARISE_VERSION".SHA256 | awk '{print $2}')
	elif [[ "$(uname)" == "Darwin" ]]; then
		SHA256=$(shasum -a 256 -c "$ARISE_VERSION".SHA256 | awk '{print $2}')
	fi

	if [[ "$SHA256" == "OK" ]]; then
		echo -e "\nChecksum Passed!"
	else
		echo -e "\nChecksum Failed, aborting installation"
		rm -f "$ARISE_VERSION" "$ARISE_VERSION".SHA256
		exit 0
	fi
}

install_arise() {
	echo -e '\nExtracting Arise binaries to '"$ARISE_INSTALL"

	tar -xzf "$ARISE_VERSION" -C "$ARISE_LOCATION"

	mv "$ARISE_LOCATION/$ARISE_DIR" "$ARISE_INSTALL"

	echo -e "\nCleaning up downloaded files"
	rm -f "$ARISE_VERSION" "$ARISE_VERSION".SHA256
}

configure_arise() {
	cd "$ARISE_INSTALL" || exit 2

	echo -e "\nColdstarting Arise for the first time"
	if ! bash arise.sh coldstart -f "$ARISE_INSTALL"/etc/blockchain.db.gz; then
		echo "Installation failed. Cleaning up..."
		cleanup_installation
	fi

	sleep 5 # Allow the DApp password to generate and write back to the config.json

	echo -e "\nStopping Arise to perform database tuning"
	bash arise.sh stop

	echo -e "\nExecuting database tuning operation"
	bash tune.sh
}

cleanup_installation() {
	echo -e "\nStopping Arise components before cleanup"
	bash arise.sh stop

	cd ../ || exit 2

	echo -e "\nRemoving Arise directory and installation files"
	rm -rf "$ARISE_INSTALL"
	rm -f "$ARISE_VERSION" "$ARISE_VERSION".SHA256

	if [[ "$FRESH_INSTALL" == false ]]; then
		echo -e "\Restoring old Arise installation"
		cp "$ARISE_BACKUP" "$ARISE_INSTALL"
		bash "$ARISE_INSTALL/arise.sh" start
	fi

	echo -e "\nPlease check installArise.out for more details on the failure. See here for troubleshooting steps: https://docs.arisecoin.com/docs/core-troubleshooting"
	echo -e "\nIf no steps resolve your issue, please log an issue at: https://github.com/arisebank/arise-build/issues"
	exit 1
}

backup_arise() {
	echo -e "\nStopping Arise to perform a backup"
	cd "$ARISE_INSTALL" || exit 2
	bash arise.sh stop

	echo -e "\nCleaning up PM2"
	bash arise.sh cleanup

	echo -e "\nBacking up existing Arise Folder"

	ARISE_BACKUP="$ARISE_LOCATION"'/backup/arise-'"$RELEASE"
	ARISE_OLD_PG="$ARISE_BACKUP"'/pgsql/'
	ARISE_NEW_PG="$ARISE_INSTALL"'/pgsql/'

	if [[ -d "$ARISE_BACKUP" ]]; then
		echo -e "\nRemoving old backup folder"
		rm -rf "$ARISE_BACKUP" &> /dev/null
	fi

	mkdir -p "$ARISE_LOCATION"/backup/ &> /dev/null
	mv -f "$ARISE_INSTALL" "$ARISE_LOCATION"/backup/ &> /dev/null
	cd "$ARISE_LOCATION" || exit 2
}

start_arise() { # Parse the various startup flags
	if [[ "$REBUILD" == true ]]; then
		if [[ "$URL" ]]; then
			echo -e "\nStarting Arise with specified snapshot"
			cd "$ARISE_INSTALL" || exit 2
			bash arise.sh rebuild -u "$URL"
		else
			echo -e "\nStarting Arise with official snapshot"
			cd "$ARISE_INSTALL" || exit 2
			bash arise.sh rebuild
		fi
	elif [[ "$FRESH_INSTALL" == true && "$SYNC" == "no" ]]; then
		echo -e "\nStarting Arise with official snapshot"
		cd "$ARISE_INSTALL" || exit 2
		bash arise.sh rebuild
	else
		if [[ "$SYNC" == "yes" ]]; then
				echo -e "\nStarting Arise from genesis"
				bash arise.sh rebuild -f etc/blockchain.db.gz
		 else
			 echo -e "\nStarting Arise with current blockchain"
			 cd "$ARISE_INSTALL" || exit 2
			 bash arise.sh start
		fi
	fi
}

upgrade_arise() {
	echo -e "\nRestoring Database to new Arise Install"
	mkdir -m700 "$ARISE_INSTALL"/pgsql/data

	if [[ "$("$ARISE_OLD_PG"/bin/postgres -V)" != "postgres (PostgreSQL) 9.6".* ]]; then
		echo -e "\nUpgrading database from PostgreSQL 9.5 to PostgreSQL 9.6"
		# Disable SC1090 - Its unable to resolve the file but we know its there.
		# shellcheck disable=SC1090
		. "$ARISE_INSTALL"/shared.sh
		# shellcheck disable=SC1090
		. "$ARISE_INSTALL"/env.sh
		# shellcheck disable=SC2129
		pg_ctl initdb -D "$ARISE_NEW_PG"/data &> $LOG_FILE
		# shellcheck disable=SC2129
		"$ARISE_NEW_PG"/bin/pg_upgrade -b "$ARISE_OLD_PG"/bin -B "$ARISE_NEW_PG"/bin -d "$ARISE_OLD_PG"/data -D "$ARISE_NEW_PG"/data &> $LOG_FILE
		bash "$ARISE_INSTALL"/arise.sh start_db &> $LOG_FILE
		bash "$ARISE_INSTALL"/analyze_new_cluster.sh &> $LOG_FILE
		rm -f "$ARISE_INSTALL"/*cluster*
	else
		cp -rf "$ARISE_OLD_PG"/data/* "$ARISE_NEW_PG"/data/
	fi

	echo -e "\nCopying config.json entries from previous installation"
	"$ARISE_INSTALL"/bin/node "$ARISE_INSTALL"/updateConfig.js -o "$ARISE_BACKUP"/config.json -n "$ARISE_INSTALL"/config.json
}

log_rotate() {
	if [[ "$(uname)" == "Linux" ]]; then
		echo -e "\nConfiguring Logrotate for Arise"
		sudo bash -c "cat > /etc/logrotate.d/arise-$RELEASE-log << EOF_arise-logrotate
		$ARISE_LOCATION/arise-$RELEASE/logs/*.log {
		create 666 $USER $USER
		weekly
		size=100M
		dateext
		copytruncate
		missingok
		rotate 2
		compress
		delaycompress
		notifempty
		}
EOF_arise-logrotate" &> /dev/null
		fi
}

usage() {
	echo "Usage: $0 <install|upgrade> [-d <directory] [-r <main|test|dev>] [-n] [-h [-u <URL>] ] "
	echo "install         -- install Arise"
	echo "upgrade         -- upgrade Arise"
	echo " -d <DIRECTORY> -- install location"
	echo " -r <RELEASE>   -- choose main or test"
	echo " -n             -- install ntp if not installed"
	echo " -h             -- rebuild instead of copying database"
	echo " -u <URL>       -- URL to rebuild from - Requires -h"
	echo " -0 <yes|no>    -- Forces sync from 0"
}

parse_option() {
	OPTIND=2
	while getopts :d:r:u:hn0: OPT; do
		 case "$OPT" in
			 d) ARISE_LOCATION="$OPTARG" ;;
			 r) RELEASE="$OPTARG" ;;
			 n) INSTALL_NTP=1 ;;
			 h) REBUILD=true ;;
			 u) URL="$OPTARG" ;;
			 0) SYNC="$OPTARG" ;;
		 esac
	 done

 if [ "$SYNC" ]; then
		if [[ "$SYNC" != "no" && "$SYNC" != "yes" ]]; then
			echo "-0 <yes|no>"
			usage
			exit 1
		fi
	fi

	if [ "$RELEASE" ]; then
		if [[ "$RELEASE" != test && "$RELEASE" != "main" && "$RELEASE" != "dev" ]]; then
			echo "-r <test|main|dev>"
			usage
			exit 1
		fi
	fi
}

case "$1" in
"install")
	FRESH_INSTALL='true'
	parse_option "$@"
	prereq_checks
	user_prompts
	ntp_checks
	download_arise
	install_arise
	configure_arise
	log_rotate
	start_arise
	;;
"upgrade")
	FRESH_INSTALL='false'
	parse_option "$@"
	user_prompts
	download_arise
	backup_arise
	install_arise
	upgrade_arise
	start_arise
	;;
*)
	echo "Error: Unrecognized command."
	echo ""
	echo "Available commands are: install upgrade"
	usage
	exit 1
	;;
esac
