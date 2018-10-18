#!/bin/bash
#######################################################################
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.
#
# nobarrier.sh
# Description:
#    Download and run No barrier Disk Test.
# Supported Distros:
#    Ubuntu, SUSE, RedHat, CentOS
#######################################################################
HOMEDIR=`pwd`
CONSTANTS_FILE="./constants.sh"
. ${CONSTANTS_FILE} || {
	echo "ERROR: unable to source constants.sh!"
	echo "TestAborted" > state.txt
	exit 1
}
UTIL_FILE="./utils.sh"
. ${UTIL_FILE} || {
	echo "ERROR: unable to source utils.sh!"
	echo "TestAborted" > state.txt
	exit 2
}
# Source constants file and initialize most common variables
UtilsInit
#Install required packages for raid
packages=("gcc" "git" "tar" "wget" "dos2unix" "mdadm")
case "$DISTRO_NAME" in
	oracle|rhel|centos)
		install_epel
		;;
	ubuntu|debian)
		update_repos
		;;
	suse|opensuse|sles)
		add_sles_network_utilities_repo
		;;
	*)
		echo "Unknown distribution"
		SetTestStateAborted
		exit 1
esac
install_package "${packages[@]}"
# Raid Creation
create_raid_and_mount $deviceName $mountDir $diskformat $mount_option
mount -l | grep "$mountDir"
if [ $? -ne 0 ]; then
	LogErr "Error: ${deviceName} not mounted with ${mount_option}"
	SetTestStateFailed
else
	LogMsg "${deviceName} mounted with ${mount_option}"
	SetTestStateCompleted
fi