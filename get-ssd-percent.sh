#!/bin/bash
#
# check SSD Percent via Redfish API.
#
# define var
SH_VER="Version:202401"
USAGE="Usage: $0 [hostname]."
PROGRAM_DIR="/var/tfx-daily"
_RESULT_FORMAT="csv";
[[ "$_RESULT_FORMAT" = "sql" ]] && { _TABLE_NAME="CHK_SSD"; };
_OUTPUT_FILENAME="$PROGRAM_DIR/`date +%Y%m%d`-check-ssd";

# source file
if [[ -f "$PROGRAM_DIR/common.sh" ]]; then source "$PROGRAM_DIR/common.sh"; else echo "[ERROR] please check missing file: $PROGRAM_DIR/common.sh"; exit 1; fi # logger, exec_sqlcmd
if [[ -f "$PROGRAM_DIR/redfish-func.sh" ]]; then source "$PROGRAM_DIR/redfish-func.sh"; else logger "please check missing file: $PROGRAM_DIR/redfish-func.sh" "ERROR"; exit 1; fi
# check var # error msg
[[ -z "$1" ]] && { echo "need \$1 as parameter."; exit 1; }
[[ "`jq --version`" =~ jq* ]] || { echo "[Error] Cannot find jq command."; exit 2; } # env err
# main
srv_model=`get_model $(get_srv_ip "$1" | head -n1)`; # echo "[DEBUG] var:srv_model $srv_model";

# check model, set var
case $srv_model in
"ProLiant DL380 Gen10"|"ProLiant DL380 Gen9")
    RF_Path="/redfish/v1/Systems/1/SmartStorage/ArrayControllers/0/DiskDrives/";
    RF_Key=".SSDEnduranceUtilizationPercentage";
    RF_Path=`get_redfish "$1" "$RF_Path" "."`; #echo $RF_Path;
    RF_Path=`echo "$RF_Path" | jq ".Members[].\"@odata.id\""`;
    #let index=${#RF_Path[@]}-1;
;;
"PowerEdge R740xd"|"PowerEdge R740"|"PowerEdge R640"|"PowerEdge R730")
    RF_Path="/redfish/v1/Systems/System.Embedded.1/Storage/RAID.Slot.6-1/";
    RF_Key=".PredictedMediaLifeLeftPercent";
    RF_Path=`get_redfish "$1" "$RF_Path" "."`;
    RF_Path=`echo "$RF_Path" | jq ".Drives[].\"@odata.id\""`;
    #let index=${#RF_Path[@]}-1;
;;
*)
    logger "Not define $1 model type($srv_model)!" "warn";
    exit 1;
esac

[[ -z "$RF_Path" ]] && { logger "$1 var:RF_Path null." "error"; exit 1; };
[[ -z "$RF_Key" ]] && { logger "$1 var:RF_Key null." "error"; exit 1; };

# get SSD Percent 
_result_str=""; # output result in one line
case $_RESULT_FORMAT in
"csv")
    _is_all_null="true"; # if all ssd value was null then dont show
    for _path in $RF_Path; do 
        _path=`echo $_path | tr -d '"'`;
        _ssd_value=`get_redfish "$1" "$_path" "$RF_Key"`;
        [[ "$_ssd_value" = "null" ]] || { _is_all_null="false"; }; 
        
        _result_str="$_result_str, $_ssd_value"; 
    done; 
    [[ "$_is_all_null" = "true" ]] && { logger "$1 no SSD device." "info"; exit 0; };
;;
"sql")
    _is_record_exist=`exec_sqlcmd "SELECT date FROM $_TABLE_NAME WHERE hostname='$1'"`; # 
    [[ -z "$_is_record_exist" ]] || { exec_sqlcmd "DELETE FROM $_TABLE_NAME WHERE hostname='$1'"; };
    
    _path_num=0;
    _is_all_null="true"; # if all ssd value was null then dont insert to table
    for _path in $RF_Path; do # get all ssd value
        _path=`echo $_path | tr -d '"'`;
        _ssd_value=`get_redfish "$1" "$_path" "$RF_Key"`;
        [[ "$_ssd_value" = "null" ]] || { _is_all_null="false"; }; 
		
        _result_str="$_result_str '$_ssd_value',"; 
        let _path_num=$_path_num+1;
    done; 
	[[ "$_is_all_null" = "true" ]] && { logger "$1 no SSD device." "info"; exit 0; };
	
    _result_str="hostname, IP, Model ) VALUES ($_result_str '$1', '$(get_srv_ip $1)', '$srv_model' )";
    for I in `seq -w $_path_num -1 1`; do # column_name
        if [[ "$_path_num" -lt 10 ]]; then _result_str="D0$I, $_result_str"; else _result_str="D$I, $_result_str"; fi
    done;
    _result_str="INSERT $_TABLE_NAME ( $_result_str";
    #[[ -n $DEBUG ]] && { logger "query_cmd($_result_str)" "DEBUG"; };
;;
*)
    logger "Not define _RESULT_FORMAT($_RESULT_FORMAT)!" "DEBUG";
    return 1;
esac

# proc result
[[ -z "$_result_str" ]] && { logger "$1 _result_str null." "error"; exit 1; }
case $_RESULT_FORMAT in
"csv")
    [[ -f "$_OUTPUT_FILENAME.csv" ]] || { echo "\"Hostname\", IP, Model, SSD Percent" >> "$_OUTPUT_FILENAME.csv"; };
    echo "$1, $(get_srv_ip $1), \"$srv_model\" $_result_str " >> "$_OUTPUT_FILENAME.csv";
;;
"sql")
    exec_sqlcmd "$_result_str";
;;
*)
    logger "Not define _RESULT_FORMAT($_RESULT_FORMAT)!" "DEBUG";
    return 1;
esac

exit 0;
