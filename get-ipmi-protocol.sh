#!/bin/bash
#
# check IPMI ProtocolEnabled via Redfish API.
#
# define var
SH_VER="Version:202310"
USAGE="Usage: $0 [hostname]."
PROGRAM_DIR="/var/tfx-daily"
_OUTPUT_FORMAT="csv";
_OUPPUT_FILENAME="$PROGRAM_DIR/`date +%Y%m%d`-check-ipmi";
#TOKEN=""
# source file
if [[ -f "$PROGRAM_DIR/common.sh" ]]; then source "$PROGRAM_DIR/common.sh"; else echo "[ERROR] please check missing file: $PROGRAM_DIR/common.sh"; exit 1; fi # logger, exec_sqlcmd
if [[ -f "$PROGRAM_DIR/redfish-func.sh" ]]; then source "$PROGRAM_DIR/redfish-func.sh"; else logger "please check missing file: $PROGRAM_DIR/redfish-func.sh" "ERROR"; exit 1; fi
# check var # error msg
[[ -z "$1" ]] && { echo "need \$1 as parameter."; exit 1; }
[[ "`jq --version`" =~ jq* ]] || { echo "[Error] Cannot find jq command."; exit 2; } # env err
# main
srv_model=`get_model $(get_srv_ip "$1")`; # echo "[DEBUG] var:srv_model $srv_model";

# check model, set var
case $srv_model in
"ProLiant DL380 Gen10")
	RF_Path="/redfish/v1/Managers/1/NetworkProtocol/";
	RF_Key=".IPMI.ProtocolEnabled";
;;
"ProLiant DL380 Gen9")
	RF_Path="/redfish/v1/Managers/1/NetworkService/";
	RF_Key=".IPMI.Enabled";
;;
"PowerEdge R740xd"|"PowerEdge R740"|"PowerEdge R640"|"PowerEdge R730")
	RF_Path="/redfish/v1/Managers/iDRAC.Embedded.1/NetworkProtocol";
	RF_Key=".IPMI.ProtocolEnabled";
;;
*)
    logger "Not define $1 model type($srv_model)!" "warn";
    exit 1;
esac

[[ -z "$RF_Path" ]] && { logger "$1 var:RF_Path null." "error"; exit 1; };
[[ -z "$RF_Key" ]] && { logger "$1 var:RF_Key null." "error"; exit 1; };

# check IPMI ProtocolEnabled	
_is_enabled=`get_redfish "$1" "$RF_Path" "$RF_Key"`; # get ProtocolEnabled value
[[ -z "$_is_enabled" ]] && { logger "$1 API return null." "error"; exit 1; }

# print result
case $_OUTPUT_FORMAT in
"csv")
    [[ -f "$_OUPPUT_FILENAME.csv" ]] || { echo "\"Hostname\", \"IP\", \"Model\", \"IPMI ProtocolEnabled\" " >> "$_OUPPUT_FILENAME.csv"; };
	echo "\"$1\", \"$(get_srv_ip $1)\", \"$srv_model\", \"$_is_enabled\" " >> "$_OUPPUT_FILENAME.csv";
;;
*)
    echo "$1 ProtocolEnabled: $_is_enabled";
    return 0;
esac

exit 0;
