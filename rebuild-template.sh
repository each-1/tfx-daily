#!/bin/bash
#
# Rebuild template table
#
# define var
SH_VER="Version:20240219"
USAGE="Usage: $0 [hostname]."
PROGRAM_DIR="/var/tfx-daily"
# source file
if [[ -f "$PROGRAM_DIR/common.sh" ]]; then source "$PROGRAM_DIR/common.sh"; else echo "[ERROR] please check missing file: $PROGRAM_DIR/common.sh"; exit 1; fi # logger, exec_sqlcmd
if [[ -f "$PROGRAM_DIR/redfish-func.sh" ]]; then source "$PROGRAM_DIR/redfish-func.sh"; else logger "please check missing file: $PROGRAM_DIR/redfish-func.sh" "ERROR"; exit 1; fi

# check var # error msg
[[ -z "$1" ]] && { echo "need \$1 as parameter."; exit 1; }
[[ "`jq --version`" =~ jq* ]] || { echo "[Error] Cannot find jq command."; exit 2; } # env err

# main
while [ ! -z "$1" ]; do # [ "$1" != "" ]
    _srv_model=`get_model $(get_srv_ip "$1")`; # echo "[DEBUG] var:srv_model $srv_model"; 
    set_tablename "$_srv_model"; # get table name (ORI_TN, TEPL_TN, SUMMARY_TN ...)
    #if [[ -z "$_srv_list" ]]; then _srv_list="\'$1\'"; else _srv_list="$_srv_list, \'$1\'"; fi # _srv_model maybe different 
    [[ -z "$TEPL_TN" ]] && { logger "$1($_srv_model) var:TEPL_TN empty!" "Error"; };
    [[ -z "$ORI_TN" ]] && { logger "$1($_srv_model) var:ORI_TN empty!" "Error"; };
    [[ -n "$DEBUG" ]] && { logger "($1, $_srv_model, $TEPL_TN, $ORI_TN)" "Debug"; };
    
    # rebuild sql query
    [[ -n "$TEPL_TN" ]] && [[ -n "$ORI_TN" ]] && { exec_sqlcmd "delete from $TEPL_TN where hostname in ( '$1' ); INSERT INTO $TEPL_TN SELECT * FROM $ORI_TN where hostname in ( '$1' ); UPDATE $TEPL_TN SET date=CURRENT_TIMESTAMP where hostname in ( '$1' );"; logger "Rebuilded $1." "info"; }; 
    
    shift # let $1=next 
done

exit 0;
