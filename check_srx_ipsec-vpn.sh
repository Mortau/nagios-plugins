#!/bin/bash
#
# A Small script to check IPSEC VPN tunnel phases on the Juniper SRX 
# Tested on Juniper SRX3400 Requires net-snmp-tools
#
# check_srx_ipsec-vpn.sh by Michael Brown
# 2016 strictly.sysops@gmail.com

verbose=0

# get variables terminal input
while getopts "H:c:g:v" opt;
do
case $opt in
H) hostaddress=$OPTARG ;;
c) community=$OPTARG ;;
g) gateway=$OPTARG ;;
v) verbose=1 ;;
*) echo "Usage: $0 -H <Hostaddress> -c <SNMP Community> -g <Remote Gateway> -v VERBOSE" ; exit 1 ;;
esac
done


# Ensure required variables 
if [[ -z "$community" ]]; then
   echo "ERROR: SNMP community required"
   exit 3
elif [[ -z "$gateway" ]]; then
   echo "ERROR: Remote Gateway IP required"
   exit 3
fi


# begin functions
function get_snmp_data()
{
   walk_ipsec=$(/usr/bin/snmpwalk -v 2c -c $community $hostaddress 1.3.6.1.4.1.2636.3.52.1.2.3.1.14)
   walk_ike=$(/usr/bin/snmpwalk -v 2c -c $community $hostaddress 1.3.6.1.4.1.2636.3.52.1.1.2.1.6)

   match_ipsec=$(echo "$walk_ipsec" | grep "$gateway" | awk '{print $4}')
   match_ike=$(echo "$walk_ike" | grep "$gateway" | awk '{print $4}')

   present_results;
}


function present_results()
{
   if [[ "$match_ipsec" == 1 ]] && [[ "$match_ike" == 1 ]]; then
      echo "OK: VPN established to $gateway"
      exit 0;
   elif [[ "$match_ipsec" =~ ^[0,2-9]+$ ]] && [[ "$match_ike" == 1 ]]; then
      echo "CRITICAL: $gateway not established in IPSEC table"
      exit 2;
   elif [[ "$match_ike" =~ ^[0,2-9]+$ ]] && [[ "$match_ipsec" == 1 ]]; then
      echo "CRITICAL: $gateway not established in IKE table"
      exit 2;
   elif [[ "$match_ipsec" =~ ^[0,2-9]+$ ]] && [[ "$match_ike" =~ ^[0,2-9]+$ ]]; then
      echo "CRITICAL: No IPSEC and IKE establishment for $gateway"
      exit 2;     
   elif [[ -z "$match_ipsec" ]] || [[ -z "$match_ike" ]]; then
      echo "UNKOWN: Gateway not found in query results"
      exit 3;
   else echo "UNKNOWN: Invalid data returned from query"
      exit 3;
   fi  
}


get_snmp_data;