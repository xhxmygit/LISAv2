#!/bin/bash

#######################################################################
#
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.
#
#######################################################################

#######################################################################
#
# nested_kvm_ntttcp_private_bridge.sh
# Description:
#   This script runs ntttcp test on two nested VMs on same L1 guest connected with private bridge
#
#######################################################################

while echo $1 | grep -q ^-; do
	declare $( echo $1 | sed "s/^-//" )=$2
	shift
	shift
done

#
# Constants/Globals
#
UTIL_FILE="./nested_vm_utils.sh"
CONSTANTS_FILE="./constants.sh"

CLIENT_IMAGE="nestedclient.qcow2"
SERVER_IMAGE="nestedserver.qcow2"
CLIENT_HOST_FWD_PORT=60022
SERVER_HOST_FWD_PORT=60023
BR_NAME="br0"
BR_ADDR="192.168.1.10"
CLIENT_IP_ADDR="192.168.1.11"
SERVER_IP_ADDR="192.168.1.12"
CLIENT_TAP="tap1"
SERVER_TAP="tap2"
NIC_NAME="ens4"

. ${CONSTANTS_FILE} || {
	errMsg="Error: missing ${CONSTANTS_FILE} file"
	LogMsg "${errMsg}"
	Update_Test_State $ICA_TESTABORTED
	exit 10
}
. ${UTIL_FILE} || {
	errMsg="Error: missing ${UTIL_FILE} file"
	LogMsg "${errMsg}"
	Update_Test_State $ICA_TESTABORTED
	exit 10
}

if [ -z "$NestedImageUrl" ]; then
	echo "Please mention -NestedImageUrl next"
	exit 1
fi
if [ -z "$NestedUser" ]; then
	echo "Please mention -NestedUser next"
	exit 1
fi
if [ -z "$NestedUserPassword" ]; then
	echo "Please mention -NestedUserPassword next"
	exit 1
fi
if [ -z "$NestedCpuNum" ]; then
	echo "Please mention -NestedCpuNum next"
	exit 1
fi
if [ -z "$NestedMemMB" ]; then
	echo "Please mention -NestedMemMB next"
	exit 1
fi
if [ -z "$NestedNetDevice" ]; then
	echo "Please mention -NestedNetDevice next"
	exit 1
fi
if [ -z "$testDuration" ]; then
	echo "Please mention -testDuration next"
	exit 1
fi
if [ -z "$testConnections" ]; then
	echo "Please mention -testConnections next"
	exit 1
fi
if [ -z "$logFolder" ]; then
	logFolder="."
	echo "-logFolder is not mentioned. Using ."
else
	echo "Using Log Folder $logFolder"
fi

touch $logFolder/state.txt
log_file=$logFolder/`basename "$0"`.log
touch $log_file

Setup_Bridge() {
	ip link show $BR_NAME
	if [ $? -eq 0 ]; then
		Log_Msg "Bridge $BR_NAME is already up" $log_file
		return
	fi
	Log_Msg "Setting up bridge $BR_NAME" $log_file
	ip link add $BR_NAME type bridge
	ifconfig $BR_NAME $BR_ADDR netmask 255.255.255.0 up
	check_exit_status "Setup bridge $BR_NAME"
}

Prepare_Client() {
	Setup_Tap $CLIENT_TAP $BR_NAME
	mac_addr1=$(generate_random_mac_addr)
	mac_addr2=$(generate_random_mac_addr)
	cmd="qemu-system-x86_64 -cpu host -smp $NestedCpuNum -m $NestedMemMB -hda $CLIENT_IMAGE \
		-device $NestedNetDevice,netdev=net0,mac=$mac_addr1 -netdev user,id=net0,hostfwd=tcp::$CLIENT_HOST_FWD_PORT-:22 \
		-device $NestedNetDevice,netdev=net1,mac=$mac_addr2,mq=on,vectors=10 \
		-netdev tap,id=net1,ifname=$CLIENT_TAP,script=no,vhost=on,queues=4 -display none -enable-kvm -daemonize"

	Start_Nested_VM -user $NestedUser -passwd $NestedUserPassword -port $CLIENT_HOST_FWD_PORT $cmd
	Enable_Root -user $NestedUser -passwd $NestedUserPassword -port $CLIENT_HOST_FWD_PORT
	Remote_Copy_Wrapper "root" $CLIENT_HOST_FWD_PORT "./enablePasswordLessRoot.sh" "put"
	Remote_Copy_Wrapper "root" $CLIENT_HOST_FWD_PORT "./utils.sh" "put"
	Remote_Exec_Wrapper "root" $CLIENT_HOST_FWD_PORT "chmod a+x *.sh"
	Remote_Exec_Wrapper "root" $CLIENT_HOST_FWD_PORT "rm -rf /root/sshFix"
	Remote_Exec_Wrapper "root" $CLIENT_HOST_FWD_PORT "/root/enablePasswordLessRoot.sh"
	Remote_Copy_Wrapper "root" $CLIENT_HOST_FWD_PORT "sshFix.tar" "get"
	check_exit_status "Download key from the client VM"

	Remote_Exec_Wrapper "root" $CLIENT_HOST_FWD_PORT "md5sum /root/.ssh/id_rsa > /root/clientmd5sum.log"
	Remote_Copy_Wrapper "root" $CLIENT_HOST_FWD_PORT "clientmd5sum.log" "get"

	echo "server=$SERVER_IP_ADDR" >> ${CONSTANTS_FILE}
	echo "client=$CLIENT_IP_ADDR" >> ${CONSTANTS_FILE}
	echo "nicName=$NIC_NAME" >> ${CONSTANTS_FILE}
	Remote_Copy_Wrapper "root" $CLIENT_HOST_FWD_PORT "${CONSTANTS_FILE}" "put"
	Log_Msg "Reboot the nested client VM" $log_file
	Remote_Exec_Wrapper "root" $CLIENT_HOST_FWD_PORT "reboot"
	Bring_Up_Nic_With_Private_Ip $CLIENT_IP_ADDR $CLIENT_HOST_FWD_PORT
}

Prepare_Server() {
	Setup_Tap $SERVER_TAP $BR_NAME
	mac_addr1=$(generate_random_mac_addr)
	mac_addr2=$(generate_random_mac_addr)
	cmd="qemu-system-x86_64 -cpu host -smp $NestedCpuNum -m $NestedMemMB -hda $SERVER_IMAGE \
	    -device $NestedNetDevice,netdev=net0,mac=$mac_addr1 -netdev user,id=net0,hostfwd=tcp::$SERVER_HOST_FWD_PORT-:22 \
	    -device $NestedNetDevice,netdev=net1,mac=$mac_addr2,mq=on,vectors=10 \
	    -netdev tap,id=net1,ifname=$SERVER_TAP,script=no,vhost=on,queues=4 -display none -enable-kvm -daemonize"
	Start_Nested_VM -user $NestedUser -passwd $NestedUserPassword -port $SERVER_HOST_FWD_PORT $cmd
	Enable_Root -user $NestedUser -passwd $NestedUserPassword -port $SERVER_HOST_FWD_PORT
	Remote_Copy_Wrapper "root" $SERVER_HOST_FWD_PORT "./enablePasswordLessRoot.sh" "put"
	Remote_Copy_Wrapper "root" $SERVER_HOST_FWD_PORT "./utils.sh" "put"
	Remote_Exec_Wrapper "root" $SERVER_HOST_FWD_PORT "chmod a+x *.sh"
	Remote_Copy_Wrapper "root" $SERVER_HOST_FWD_PORT "./sshFix.tar" "put"
	check_exit_status "Copy key to the server VM"

	Remote_Exec_Wrapper "root" $SERVER_HOST_FWD_PORT "/root/enablePasswordLessRoot.sh"
	Remote_Exec_Wrapper "root" $SERVER_HOST_FWD_PORT "md5sum /root/.ssh/id_rsa > /root/servermd5sum.log"
	Remote_Copy_Wrapper "root" $SERVER_HOST_FWD_PORT "servermd5sum.log" "get"
	Log_Msg "Reboot the nested server VM" $log_file
	Remote_Exec_Wrapper "root" $SERVER_HOST_FWD_PORT "reboot"
	Bring_Up_Nic_With_Private_Ip $SERVER_IP_ADDR $SERVER_HOST_FWD_PORT
}

Prepare_Nested_VMs() {
	Prepare_Client
	Prepare_Server
	client_md5sum=$(cat ./clientmd5sum.log)
	server_md5sum=$(cat ./servermd5sum.log)

	if [[ $client_md5sum == $server_md5sum ]]; then
		Log_Msg "md5sum check success for .ssh/id_rsa" $log_file
	else
		Log_Msg "md5sum check failed for .ssh/id_rsa" $log_file
		Update_Test_State $ICA_TESTFAILED
		exit 1
	fi
}

Bring_Up_Nic_With_Private_Ip() {
	ip_addr=$1
	host_fwd_port=$2
	retry_times=20
	exit_status=1
	while [ $exit_status -ne 0 ] && [ $retry_times -gt 0 ];
	do
		retry_times=$(expr $retry_times - 1)
		if [ $retry_times -eq 0 ]; then
			Log_Msg "Timeout to connect to the nested VM" $log_file
			Update_Test_State $ICA_TESTFAILED
			exit 0
		else
			sleep 10
			Log_Msg "Try to bring up the nested VM NIC with private IP, left retry times: $retry_times" $log_file
			Remote_Exec_Wrapper "root" $host_fwd_port "ifconfig $NIC_NAME $ip_addr netmask 255.255.255.0 up"
			exit_status=$?
		fi
	done
	if [ $exit_status -ne 0 ]; then
		Update_Test_State $ICA_TESTFAILED
		exit 1
	fi
}

Run_Ntttcp_On_Client() {
	Log_Msg "Copy test scripts to nested VM" $log_file
	Remote_Copy_Wrapper "root" $CLIENT_HOST_FWD_PORT "./perf_ntttcp.sh" "put"
	Remote_Exec_Wrapper "root" $CLIENT_HOST_FWD_PORT "chmod a+x *.sh"
	Log_Msg "Start to run perf_ntttcp.sh on nested client VM" $log_file
	Remote_Exec_Wrapper "root" $CLIENT_HOST_FWD_PORT "/root/perf_ntttcp.sh > ntttcpConsoleLogs"
}

Collect_Logs() {
	Log_Msg "Finished running perf_ntttcp.sh, start to collect logs" $log_file
	Remote_Exec_Wrapper "root" $CLIENT_HOST_FWD_PORT "mv ./ntttcp-${testType}-test-logs ./ntttcp-${testType}-test-logs-sender"
	Remote_Exec_Wrapper "root" $CLIENT_HOST_FWD_PORT "tar -cf ./ntttcp-test-logs-sender.tar ./ntttcp-${testType}-test-logs-sender"
	Remote_Exec_Wrapper "root" $CLIENT_HOST_FWD_PORT ". utils.sh  && collect_VM_properties nested_properties.csv"
	Remote_Copy_Wrapper "root" $CLIENT_HOST_FWD_PORT "ntttcp-test-logs-sender.tar" "get"
	Remote_Copy_Wrapper "root" $CLIENT_HOST_FWD_PORT "ntttcpConsoleLogs" "get"
	Remote_Copy_Wrapper "root" $CLIENT_HOST_FWD_PORT "ntttcpTest.log" "get"
	Remote_Copy_Wrapper "root" $CLIENT_HOST_FWD_PORT "nested_properties.csv" "get"
	Remote_Exec_Wrapper "root" $SERVER_HOST_FWD_PORT "mv ./ntttcp-${testType}-test-logs ./ntttcp-${testType}-test-logs-receiver"
	Remote_Exec_Wrapper "root" $SERVER_HOST_FWD_PORT "tar -cf ./ntttcp-test-logs-receiver.tar ./ntttcp-${testType}-test-logs-receiver"
	Remote_Copy_Wrapper "root" $SERVER_HOST_FWD_PORT "ntttcp-test-logs-receiver.tar" "get"
	Remote_Copy_Wrapper "root" $CLIENT_HOST_FWD_PORT "report.log" "get"
	check_exit_status "Get the NTTTCP report"
}

Update_Test_State $ICA_TESTRUNNING
Install_KVM_Dependencies
Download_Image_Files -destination_image_name $CLIENT_IMAGE -source_image_url $NestedImageUrl
cp $CLIENT_IMAGE $SERVER_IMAGE
Setup_Bridge
Prepare_Nested_VMs
Run_Ntttcp_On_Client
Collect_Logs
Stop_Nested_VM
Update_Test_State $ICA_TESTCOMPLETED
