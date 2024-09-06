#!/bin/bash
#
# get Server Power state
#
# define var
SH_VER="Version:20240206"
USAGE="Usage: $0 [hostname]."
PROGRAM_DIR="/var/tfx-daily"
# source file
if [[ -f "$PROGRAM_DIR/common.sh" ]]; then source "$PROGRAM_DIR/common.sh"; else echo "[ERROR] please check missing file: $PROGRAM_DIR/common.sh"; exit 1; fi # logger, exec_sqlcmd
if [[ -f "$PROGRAM_DIR/redfish-func.sh" ]]; then source "$PROGRAM_DIR/redfish-func.sh"; else logger "please check missing file: $PROGRAM_DIR/redfish-func.sh" "ERROR"; exit 1; fi

# check var # error msg
#[[ -z "$1" ]] && { echo "need \$1 as parameter."; exit 1; }
[[ "`jq --version`" =~ jq* ]] || { echo "[Error] Cannot find jq command."; exit 2; } # env err

# main
[[ -z "$1" ]] && { logger "get-power-stat.sh need 1 parameters" "debug"; return 1; } # $1 as hostname
_stat=`get_redfish "$1" "/redfish/v1/Systems/1/" ".Status.State"`; # get power state method
if [[ "$_stat" = "\"Enabled\"" ]]; then printf '[%-15s: %-10s]' "$1" "$_stat"; else printf '[\033[91m%-15s: %-10s\033[0m]' "$1" "$_stat"; fi; # print result

exit 0;
