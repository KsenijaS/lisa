#!/bin/bash
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.

# This script starts pktgen and checks XDP_TX forwarding performance by starting xdpdump application
# in forwarding configuration on forwarder VM and checks how many packets received at the receiver interface
# by running xdpdump application in drop configuration (number of packets received == number of packets dropped).


packetCount=10000000
nicName='eth1'
packetFwdThreshold=90

function download_pktgen_scripts(){
        local ip=$1
        local dir=$2
        if [ "${core}" = "multi" ];then
                ssh $ip "wget https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/samples/pktgen/pktgen_sample05_flow_per_thread.sh?h=v5.7.8 -O ${dir}/pktgen_sample.sh"
        else
                ssh $ip "wget https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/samples/pktgen/pktgen_sample01_simple.sh?h=v5.7.8 -O ${dir}/pktgen_sample.sh"
        fi
        ssh $ip "wget https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/samples/pktgen/functions.sh?h=v5.7.8 -O ${dir}/functions.sh"
        ssh $ip "wget https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/samples/pktgen/parameters.sh?h=v5.7.8 -O ${dir}/parameters.sh"
        ssh $ip "chmod +x ${dir}/*.sh"
}

function calculate_packets_drop(){
        local vfName=$1
        local synthDrop=0
        IFS=$'\n' read -r -d '' -a xdp_packet_array < <(ethtool -S $nicName | grep 'xdp' | cut -d':' -f2)
        for i in "${xdp_packet_array[@]}";
        do
                synthDrop=$((synthDrop+i))
        done
        vfDrop=$(ethtool -S $vfName | grep rx_xdp_drop | cut -d':' -f2)
        if [ $? -ne 0 ]; then
                echo "$((synthDrop))"
        else
                echo "$((vfDrop + synthDrop))"
        fi

}

function convert_MAC_to_HEXArray(){
        while IFS=':' read -ra ADDR; do
                size=$((${#ADDR[@]} - 1))
                MACarr=$(printf '0x%s\n' ${ADDR[$i]})
                for i in $(seq 1 $size);
                do
                        MACarr="$MACarr, $(printf '0x%s\n' ${ADDR[$i]})";
                done
        done <<< "$1"
        echo "$MACarr"
}

function configure_XDPDUMP_TX(){
        LogMsg "Configuring TX Setup"
        get_ip_command="/sbin/ifconfig $nicName | grep 'inet' | cut -d: -f2"
        get_mac_command="/sbin/ifconfig $nicName | grep -o -E '([[:xdigit:]]{1,2}:){5}[[:xdigit:]]{1,2}'"
        forwarderIP=$((ssh $forwarder $get_ip_command) | awk '{print $2}')
        LogMsg "Forwarder IP: $forwarderIP"
        receiverIP=$((ssh $receiver $get_ip_command) | awk '{print $2}')
        LogMsg "Receiver IP: $receiverIP"
        forwarderMAC=$(ssh $forwarder $get_mac_command)
        LogMsg "Forwarder MAC: $forwarderMAC"
        receiverMAC=$(ssh $receiver $get_mac_command)
        LogMsg "Receiver MAC: $receiverMAC"

        #formatting MAC and IP address as needed in xdpdump file.
        forwarderIP1=$(echo $forwarderIP | sed "s/\./\, /g")
        receiverIP1=$(echo $receiverIP | sed "s/\./\, /g")
        forwarderMAC1=$(convert_MAC_to_HEXArray $forwarderMAC)
        receiverMAC1=$(convert_MAC_to_HEXArray $receiverMAC)
        xdpdumpFileName=bpf-samples/xdpdump/xdpdump_kern.c

        LogMsg "Updating $xdpdumpFileName file with forwarding setup on $forwarder"
        commandMACS="sed -i 's/unsigned char newethsrc \[\] = { 0x00, 0x22, 0x48, 0x4c, 0xc4, 0x4d };/unsigned char newethsrc \[\] = { ${forwarderMAC1} };/g' ${xdpdumpFileName}"
        ssh $forwarder $commandMACS
        commandMACD="sed -i 's/unsigned char newethdest \[\] = { 0x00, 0x22, 0x48, 0x4c, 0xc0, 0xfd };/unsigned char newethdest \[\] = { ${receiverMAC1} };/g' ${xdpdumpFileName}"
        ssh $forwarder $commandMACD
        LogMsg "Updated Source &  Destination MAC address in $xdpdumpFileName on $forwarder"
        commandIPS="sed -i 's/__u8 newsrc \[\] = { 10, 0, 1, 5 };/__u8 newsrc \[\] = { ${forwarderIP1} };/g' ${xdpdumpFileName}"
        ssh $forwarder $commandIPS
        commandIPD="sed -i 's/__u8 newdest \[\] = { 10, 0, 1, 4 };/__u8 newdest \[\] = { ${receiverIP1} };/g' ${xdpdumpFileName}"
        ssh $forwarder $commandIPD
        LogMsg "Updated Source &  Destination IP address in $xdpdumpFileName on $forwarder"
}

UTIL_FILE="./utils.sh"

# Source utils.sh
. ${UTIL_FILE} || {
    echo "ERROR: unable to source ${UTIL_FILE}!"
    echo "TestAborted" > state.txt
    exit 0
}

XDPUTIL_FILE="./XDPUtils.sh"

# Source utils.sh
. ${XDPUTIL_FILE} || {
    echo "ERROR: unable to source ${XDPUTIL_FILE}!"
    echo "TestAborted" > state.txt
    exit 0
}

# Source constants file and initialize most common variables
UtilsInit
# Script start from here
LogMsg "*********INFO: Script execution Started********"
LogMsg "forwarder : ${forwarder}"
LogMsg "receiver : ${receiver}"
LogMsg "nicName: ${nicName}"
bash ./XDPDumpSetup.sh ${forwarder} ${nicName}
check_exit_status "XDPDumpSetup on ${forwarder}" "exit"
SetTestStateRunning
bash ./XDPDumpSetup.sh ${receiver} ${nicName}
check_exit_status "XDpDUMPSetup on ${receiver}" "exit"
SetTestStateRunning
configure_XDPDUMP_TX

LogMsg "XDP Setup Completed"

# Setup pktgen on Sender
LogMsg "Configure pktgen on ${sender}"
pktgenDir=~/pktgen
ssh ${sender} "mkdir -p ${pktgenDir}"
download_pktgen_scripts ${sender} ${pktgenDir}
# Configure XDP_TX on Forwarder
LogMsg "Build XDPDump with TX Action on ${forwarder}"
ssh ${forwarder} "cd bpf-samples/xdpdump && make clean && CFLAGS='-D __TX_FWD__ -D __PERF__ -I../libbpf/src/root/usr/include' make"
check_exit_status "Build xdpdump with TX Action on ${forwarder}"
# Configure XDP_DROP on receiver
LogMsg "Build XDPDump with DROP Action on ${receiver}"
ssh ${receiver} "cd bpf-samples/xdpdump && make clean && CFLAGS='-D __PERF_DROP__ -D __PERF__ -I../libbpf/src/root/usr/include' make"
check_exit_status "Build xdpdump with DROP Action on ${receiver}"

# Calculate packet drops before tests
packetDropBefore=$(ssh ${receiver} ". XDPUtils.sh && calculate_packets_drop ${nicName}")
LogMsg "Before test, Packet drop count on ${receiver} is ${packetDropBefore}"
# Calculate packets forwarded before tests
pktForwardBefore=$(ssh ${forwarder} ". XDPUtils.sh && calculate_packets_forward ${nicName}")
LogMsg "Before test, Packet forward count on ${forwarder} is ${pktForwardBefore}"

# Start XDPDump on receiver
xdpdumpCommand="cd bpf-samples/xdpdump && ./xdpdump -i ${nicName} > ~/xdpdumpout_${receiver}.txt"
LogMsg "Starting xdpdump on ${receiver} with command: ${xdpdumpCommand}"
ssh -f ${receiver} "sh -c '${xdpdumpCommand}'"
# Start XDPDump on forwarder
xdpdumpCommand="cd bpf-samples/xdpdump && ./xdpdump -i ${nicName} > ~/xdpdumpout_${forwarder}.txt"
LogMsg "Starting xdpdump on ${forwarder} with command: ${xdpdumpCommand}"
ssh -f ${forwarder} "sh -c '${xdpdumpCommand}'"

# Start pktgen on Sender
forwarderSecondMAC=$((ssh ${forwarder} "ip link show ${nicName}") | grep ether | awk '{print $2}')
LogMsg "Forwarder second MAC: ${forwarderSecondMAC}"
if [ "${core}" = "single" ];then
        startCommand="cd ${pktgenDir} && ./pktgen_sample.sh -i ${nicName} -m ${forwarderSecondMAC} -d ${forwarderSecondIP} -v -n${packetCount}"
        LogMsg "Starting pktgen on sender: $startCommand"
        ssh ${sender} "modprobe pktgen; lsmod | grep pktgen"
        result=$(ssh ${sender} "${startCommand}")
else
        startCommand="cd ${pktgenDir} && ./pktgen_sample.sh -i ${nicName} -m ${forwarderSecondMAC} -d ${forwarderSecondIP} -v -n${packetCount} -t8"
        LogMsg "Starting pktgen on sender: ${startCommand}"
        ssh ${sender} "modprobe pktgen; lsmod | grep pktgen"
        result=$(ssh ${sender} "${startCommand}")
fi
sleep 10
# Kill XDPDump on reciever & forwarder
LogMsg "Killing xdpdump on receiver and forwarder"
ssh ${receiver} "killall xdpdump"
ssh ${forwarder} "killall xdpdump"
# Calculate: Sender PPS, Forwarder # packets, receiver # packets
# Calculate packet drops before tests
packetDropAfter=$(ssh ${receiver} ". XDPUtils.sh && calculate_packets_drop ${nicName}")
packetDrop=$(($packetDropAfter - $packetDropBefore))
LogMsg "After test, Packet drop count on ${receiver} is ${packetDrop}"
# Calculate packets forwarded before tests
pktForwardAfter=$(ssh ${forwarder} ". XDPUtils.sh && calculate_packets_forward ${nicName}")
pktForward=$((pktForwardAfter - pktForwardBefore))
LogMsg "After test, Packet forward count on ${forwarder} is ${pktForward}"
pps=$(echo $result | grep -oh '[0-9]*pps' | cut -d'p' -f 1)
LogMsg "Sender PPS: $pps"
LogMsg "Forwarder forwarded ${pktForward} packets and Receiver received ${packetDrop} packets"
# threshold value check
fwdLimit=$(( packetCount*packetFwdThreshold/100 ))
if [ $packetDrop -lt $fwdLimit ]; then
        LogErr "receiver did not receive enough packets. Receiver received ${packetDrop} which is lower than threshold" \
                "of ${packetFwdThreshold}% of ${packetCount}. Please check logs"
        SetTestStateAborted
fi
if [ $pps -ge 1000000 ]; then
        LogMsg "pps is greater than 1 Mpps"
        SetTestStateCompleted
else
        LogErr "pps is lower than 1 Mpps"
        SetTestStateFailed
fi
# Success
LogMsg "Testcase successfully completed"