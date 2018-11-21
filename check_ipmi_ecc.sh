#!/bin/bash
#
#
# This script uses the results from IPMI commands to check the system event log for
# instances of MCE (memory correction by ecc) and alerts if memory errors exceed threshold.
# Requires OpenIPMI and ipmitools packages be installed on executing host.
# Developed against Supermicro X9 series motherboards, may work on others.
#
# check_ipmi_ecc.sh by Michael Brown
# 2017 strictly.sysops@gmail.com
#
# V1.0.0	mb	20171114	first release
#

# global variables
export run_date=$(date '+%s')
verbose=0

# get variables from command line input
function _usage()
{
echo -e "Usage: $0 -H <Hostaddress> -U <username> -P <password> -w <warn:ing> -c <crit:ical> \n \
	warning/critical format = x:y where x = number of occurrences and y = threshold in days \n \
	i.e. -c 15:30 means program will alert when error count is 15 or greater AND the most recent error is 30 or less days old \n"
	exit "$retval"
}

retval=0
while getopts "H:U:P:w:c:v" opt; do
	case $opt in
	H ) hostaddress="$OPTARG" ;;
	U ) ipmiuser="$OPTARG" ;;
	P ) ipmipass="$OPTARG" ;;
	w ) warn="$OPTARG" ;;
	c ) crit="$OPTARG" ;;
	#v ) verbose=1 ;;
	h ) _usage ;;
	? ) _usage ;;
	esac
done

# ensure we have what we need
if [[ -z $(rpm -qa | grep ipmitool) ]]; then
	echo "ERROR: please install "ipmitool" package"
	exit 1
fi
if [[ -z $hostaddress ]]; then
	echo "ERROR:Remote host must be specified"
	eval retval=1
	_usage
fi

# sanity test thresholds
if [[ "$warn_count" -ge "$crit_count" ]]; then
	echo "ERROR:warning error count cannot be greater than critical count"
	exit 3
fi
if [[ "$crit_days" -ge "$warn_days" ]]; then
	echo "ERROR:critical days must be less than warning days"
	exit 3
fi

# break down our thresholds by the delimiter
warn_count=$(echo "$warn" | cut -d : -f 1)
crit_count=$(echo "$crit" | cut -d : -f 1)
warn_days=$(echo "$warn" | cut -d : -f 2)
crit_days=$(echo "$crit" | cut -d : -f 2)

# functions
function main()
{
	ipmi_log=$(ipmitool -H "$hostaddress" -U "$ipmiuser" -P "$ipmipass" sel list | grep "Memory")
        if [[ -z "$ipmi_log" ]]; then
           eval retval=00
           print_results
        fi

	total_count=$(echo "$ipmi_log" | wc -l)
        first_match=$(echo "$ipmi_log" | head -1)
        last_match=$(echo "$ipmi_log" | tail -1)

        end_date=$(date -d $(echo "$last_match" | awk '{print $3}') '+%s')
        days_since_error=$( echo $(( ( run_date - end_date )/(60*60*24) )))

	if [[ "$days_since_error" -le "$crit_days" ]]; then
		if [[ "$total_count" -lt "$warn_count" ]]; then
                	eval retval=0
                	print_results
		elif [[ "$total_count" -ge "$warn_count" ]] && [[ "$total_count" -lt "$crit_count" ]]; then
			eval retval=1
			print_results
		elif [[ "$total_count" -ge "$crit_count" ]]; then
			eval retval=2
			print_results
		fi
	elif [[ "$days_since_error" -le "$warn_days" ]] && [[ "$days_since_error" -gt "$crit_days" ]]; then
		if [[ "$total_count" -ge "$warn_count" ]]; then
			eval retval=1
			print_results
		else
			eval retval=0
			print_results
		fi
	elif [[ "$days_since_error" -ge "$warn_days" ]]; then
		eval retval=0
		print_results
	else
		eval retval=3
		print_results
	fi
}

function print_results()
{
	if [[ $retval == 00 ]]; then
	   echo "OK:no ECC errors found in SEL"
	   exit 0
	elif [[ $retval == 0 ]]; then
	   echo "OK:$total_count ECC errors, most recent was $days_since_error days ago"
	   exit $retval
	elif [[ $retval == 1 ]]; then
	   echo "WARN:$total_count ECC errors, most recent was $days_since_error days ago"
	   exit $retval
	elif [[ $retval == 2 ]]; then
	   echo "CRIT:$total_count ECC errors, most recent was $days_since_error days ago"
	   exit $retval
	elif [[ $retval == 3 ]]; then
	   echo "ERR:something went wrong"
	   exit $retval
	fi
}

main