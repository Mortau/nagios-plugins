#!/bin/bash
#
# This script uses standard SNMP queries to find the real server (slb) status on A10 -
# Thunder series application delivery controllers.
# This script can be used as a Nagios/Naemon plugin or run as a cron to email a report. By
# default the script runs in plugin mode, but if an email address is specified then the
# script will behave as a report generator. The verbose switch has no effect on output when
# results are sent in email, when used as a monitoring plugin verbose will display the names
# of the down or disabled servers.
# This script requires packages "net-snmp_utils" and "mutt" also write privileges to a 
# temporary location are needed in order to save query results and message body.
# Tested against A10 Thunder 3400 and 6400 running 2.7.1 codebase
#
# check_slb_status by Michael Brown
# version 1.2
# 2017 strictly.sysops@gmail.com
#


# set global values
enable_email=0
warnthresh=0
critthresh=0
verbose=0


# get variables terminal input
while getopts "H:C:n:w:c:v" opt;
do
case $opt in
H) host_adc=$OPTARG ;;
C) snmp_comm=$OPTARG ;;
n) notify=$OPTARG ;;
w) warnthresh=$OPTARG ;;
c) critthresh=$OPTARG ;;
v) verbose=1 ;;
*) echo "Usage: $0 -H <IP or FQDN of A10 ADC> -C <SNMP community> -n <notification email address> -w <warning> -c <critical>"; exit 1 ;;
esac
done


# set global variables
base_oid="SNMPv2-SMI::enterprises.22610.2.4.3.2.3.1"
object_name_oid="$base_oid".1.1
object_status_oid="$base_oid".1.9
temp_dir=/tmp
mailer=/usr/bin/mutt
messagefile="$temp_dir"/messagebody.txt


# set the default SNMP community
if [[ -z "$snmp_comm" ]]; then
	snmp_comm=PUBLIC
fi

if [[ -n "$notify" ]]; then
	enable_email=1
fi

# make sure thresholds are sane
if [[ "$warnthresh" -gt "$critthresh" ]]; then
	echo "ERROR: warning threshold cannot be larger numerically than critical threshold"
	exit 3;
fi

# generate the output files
rm -f $temp_dir/slb_name-list
rm -f $temp_dir/slb_status-list
rm -f $temp_dir/slb_results.txt && touch $temp_dir/slb_results.txt
snmpwalk -v 2c -c $snmp_comm $host_adc $object_name_oid > $temp_dir/slb_name-list
snmpwalk -v 2c -c $snmp_comm $host_adc $object_status_oid > $temp_dir/slb_status-list

# begin functions
function find_down_disabled()
{
IFS=$'\n'
for d in $(egrep "INTEGER: 0|INTEGER: 2" "$temp_dir"/slb_status-list); do
	slb_id=$(echo "$d" | sed -n -e 's/^.*'$object_status_oid'.//p' | cut -d " " -f 1)
	slb_name=$(grep "$slb_id" "$temp_dir"/slb_name-list | sed -n -e 's/^.*STRING: //p')
	slb_port=$(echo ${slb_id##*.})
	echo ""$slb_name" port "$slb_port" is disabled" >> $temp_dir/slb_results.txt
done
down_host_count=$(wc -l <"$temp_dir"/slb_results.txt)
if [[ $enable_email == 1 ]]; then
	generate_report;
else
	plugin_results;
fi
}

function plugin_results()
{
if [[ "$down_host_count" -ge "$critthresh" ]]; then
	echo "CRITICAL: "$down_host_count" slb servers are disabled on "$host_adc""
		if [[ "$verbose" == 1 ]]; then
			cat "$temp_dir"/slb_results.txt
		fi
	exit 2;
elif [[ "$down_host_count" -ge "$warnthresh" ]] && [[ "$down_host_count" -lt "$critthresh" ]]; then
	echo "WARNING: "$down_host_count" slb servers are disabled on "$host_adc""
		if [[ "$verbose" == 1 ]]; then
			cat "$temp_dir"/slb_results.txt
		fi
	exit 1;
elif [[ "$down_host_count" -lt "$warnthresh" ]]; then
	echo "OK: "$down_host_count" slb servers are disabled on "$host_adc""
		if [[ "$verbose" == 1 ]]; then
			cat "$temp_dir"/slb_results.txt
		fi
	exit 0;
else
	echo "ERROR: could not parse data"
	exit 3;
fi
}

function generate_report()
{
mailsubj="A10 Load Balancer - Down SLB Server Report"
echo "A10 Host ADC: "$host_adc"" > $messagefile
echo "Total Number of Down/Disabled SLB Servers: "$down_host_count"" >> $messagefile
echo "Down/Disabled SLB Server List:" >> $messagefile
cat "$temp_dir"/slb_results.txt >> $messagefile
"$mailer" -s "$mailsubj" "$notify" < "$messagefile"
rm "$messagefile"
exit 0;
}

find_down_disabled;