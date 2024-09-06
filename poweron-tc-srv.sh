#!/bin/bash
#
# PowerOn TC Server 
#
# define var
SH_VER="Version:20240202"
USAGE="Usage: $0 [hostname]."
PROGRAM_DIR="/var/tfx-daily"
admin_usr="oooo";
admin_pw="xxxx";
# source file
if [[ -f "$PROGRAM_DIR/common.sh" ]]; then source "$PROGRAM_DIR/common.sh"; else echo "[ERROR] please check missing file: $PROGRAM_DIR/common.sh"; exit 1; fi # logger, exec_sqlcmd
if [[ -f "$PROGRAM_DIR/redfish-func.sh" ]]; then source "$PROGRAM_DIR/redfish-func.sh"; else logger "please check missing file: $PROGRAM_DIR/redfish-func.sh" "ERROR"; exit 1; fi

# check var # error msg
#[[ -z "$1" ]] && { echo "need \$1 as parameter."; exit 1; }
[[ "`jq --version`" =~ jq* ]] || { echo "[Error] Cannot find jq command."; exit 2; } # env err

# main
tc24_hostslist; # define hosts list
for _index in `seq 0 $_GROUPS_INDEX`; do
    for _srv in ${_SRV_GROUPS[$_index]}; do 
        logger "PowerOn $_srv" "info";
        set_power_type "$_srv" "On"; 
    done;
    sleep 60; # staggered boot sequence
done

exit 0;
