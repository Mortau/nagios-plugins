#!/bin/bash
#
# A Small script to check the rate of packets per second across an ethernet adapter. 
# Default interval of per second can be modified if one chooses, but this is not 
# recommended as that would mean script execution time would be be however long the 
# duration is plus a handful of milliseconds. 
# This check was designed to run on the host and be executed with NRPE.
#
# check_netpps by Michael Brown
# 2014 strictly.sysops@gmail.com

# get variables terminal input
while getopts "i:w:c:v" opt;
do
case $opt in
i) interface=$OPTARG ;;
w) warnthresh=$OPTARG ;;
c) critthresh=$OPTARG ;;
v) verbose=1 ;;
*) echo "Usage: $0 -i INTERFACE (defaults to eth0) -w WARNING -c CRITICAL -v VERBOSE" ; exit 1 ;;
esac
done

INTERVAL=1

# if no interface specified then default to eth0
if [[ -z "$interface" ]]; then
interface=eth0
fi

# make sure critical is larger than warning
if [[ $warnthresh -gt $critthresh ]]; then
	echo "ERROR: Warning threshold cannot be greater than critical threshold!"
	exit 3;
fi
	
# begin functions
function get_stats()
{
	R1=`cat /sys/class/net/"$interface"/statistics/rx_packets`
	T1=`cat /sys/class/net/"$interface"/statistics/tx_packets`
	sleep "$INTERVAL"
	R2=`cat /sys/class/net/"$interface"/statistics/rx_packets`
	T2=`cat /sys/class/net/"$interface"/statistics/tx_packets`
	TXPPS=`expr $T2 - $T1`
	RXPPS=`expr $R2 - $R1`
    present_data;
}
function present_data()
{
	if [[ $TXPPS -gt $RXPPS ]]; then
		if [[ $TXPPS -lt $warnthresh ]]; then 
			echo "OK:'$interface': TX:'$TXPPS' pkts/s RX:'$RXPPS' pkts/s"
			exit 0;
		elif [[ $TXPPS -gt $warnthresh ]] && [[ $TXPPS -lt $critthresh ]]; then
			echo "WARNING: TX '$interface': $TXPPS pkts/s RX '$interface': $RXPPS pkts/s"
			exit 1;
		elif [[ $TXPPS -gt $critthresh ]]; then
			echo "CRITICAL: TX '$interface': $TXPPS pkts/s RX '$interface': $RXPPS pkts/s"
			exit 2;
		fi
	elif [[ $RXPPS -gt $TXPPS ]]; then
		if [[ $RXPPS -lt $warnthresh ]]; then 
			echo "OK:'$interface': TX:'$TXPPS' pkts/s RX:'$RXPPS' pkts/s"
			exit 0;
		elif [[ $RXPPS -gt $warnthresh ]] && [[ $RXPPS -lt $critthresh ]]; then
			echo "WARNING: TX '$interface': $TXPPS pkts/s RX '$interface': $RXPPS pkts/s"
			exit 1;
		elif [[ $RXPPS -gt $critthresh ]]; then
			echo "CRITICAL: TX '$interface': $TXPPS pkts/s RX '$interface': $RXPPS pkts/s"
			exit 2;
		fi
	fi
}

get_stats;