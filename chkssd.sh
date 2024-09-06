#!/bin/bash
#
# check SSD 
#
# define var
SH_VER="Version:20240219"
USAGE="Usage: $0 [hostname]."
PROGRAM_DIR="/var/tfx-daily"
# source file
# check var # error msg
# main
#grep -E '^[0-9]{1,3}\.[0-9]{1,3}\."175||75||29||91"\.[0-9]{1,3}' /var/tfx-daily/oa-hosts.txt | awk '{print $2}' | xargs -d '\n' -n1 -P4 -I {} "/var/tfx-daily/get-ssd-percent.sh" {} ; # oa 
grep -iE "iLO|iDrac|iRMC|IMM" /etc/hosts | grep -E '^[0-9]{1,3}\.[0-9]{1,3}\."125||195"\.[0-9]{1,3}' | awk '{print $2}' | xargs -d '\n' -n1 -P4 -I {} "/var/tfx-daily/get-ssd-percent.sh" {} ; # prod

exit 0;
