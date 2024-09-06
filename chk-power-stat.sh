#!/bin/bash
#
# check Server Power state
#
# define var
SH_VER="Version:20240206"
USAGE="Usage: $0 [hostname]."
PROGRAM_DIR="/var/tfx-daily"
#_SRV_GROUPS=(); # split servers into different groups for staggered boot sequence
#_OUTPUT_FILENAME="/tmp/`date +%Y%m%d-%H%M`-power-stat.txt"; # txt format
# source file
if [[ -f "$PROGRAM_DIR/common.sh" ]]; then source "$PROGRAM_DIR/common.sh"; else echo "[ERROR] please check missing file: $PROGRAM_DIR/common.sh"; exit 1; fi # logger, exec_sqlcmd
if [[ -f "$PROGRAM_DIR/redfish-func.sh" ]]; then source "$PROGRAM_DIR/redfish-func.sh"; else logger "please check missing file: $PROGRAM_DIR/redfish-func.sh" "ERROR"; exit 1; fi

# check var # error msg
tc24_hostslist; # define hosts list
#[[ -z "$1" ]] && { echo "need \$1 as parameter."; exit 1; }
[[ "`jq --version`" =~ jq* ]] || { echo "[Error] Cannot find jq command."; exit 2; } # env err
[[ -z "$_GROUPS_INDEX" ]] && { logger "Not define var: _GROUPS_INDEX (or check hosts list function)" "error"; exit 1; };

# main
for _index in `seq 0 $_GROUPS_INDEX`; do
    #for _srv in ${_SRV_GROUPS[$_index]}; do "$PROGRAM_DIR/get-power-stat.sh" "$_srv"; done;
    echo -e "\n- Server Group$_index:";
    echo "${_SRV_GROUPS[$_index]}" | xargs -d '\n' -n1 -P4 -I {} "$PROGRAM_DIR/get-power-stat.sh" {}; # | tee -a "$_OUTPUT_FILENAME";
done

exit 0;
