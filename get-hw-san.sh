#!/bin/bash
#
# define var
SH_VER="Version:20230607"
PROGRAM_DIR="/var/tfx-daily"
# source file
if [[ -f "$PROGRAM_DIR/common.sh" ]]; then source "$PROGRAM_DIR/common.sh"; else echo "[ERROR] please check missing file: $PROGRAM_DIR/common.sh"; exit 1; fi # logger, exec_sqlcmd
# define function

# check var # error msg
[[ "`jq --version`" =~ jq* ]] || { echo "[Error] Cannot find jq command."; exit 2; }
rpm -q mssql-tools &> /dev/null; [[ $? -eq 1 ]] && { echo "[Error] Cannot find mssql-tools rpm."; exit 2; };
[[ -z "`rpm -qa | grep msodbcsql`" ]] && { echo "[Error] Cannot find msodbcsql rpm."; exit 2; };
[[ -f "/opt/mssql-tools/bin/sqlcmd" ]] || { echo "[Error] Cannot find sqlcmd command."; exit 2; };
[[ -z "$DB_SRV" ]] && { echo "[Error] DB Server can't empty!"; exit 1; } # syntax error (?)
[[ -z "$DB_USR" ]] && { echo "[Error] DB Username can't empty!"; exit 1; }
[[ -z "$DB_PW" ]] && { echo "[Error] DB Password can't empty!"; exit 1; }
# main
MGT_IP_LIST="san-switch1 san-switch2"; 
TOKEN="";
tmp_json="$PROGRAM_DIR/tmp_$$.json"; while [ -f "$tmp_json" ]; do tmp_json="$PROGRAM_DIR/tmp_r$RANDOM.json"; done #
ORI_TN="HW_SanSwitch"; # set tablename
[[ "$1" = "--debug" ]] && DEBUG="true";

is_table_exist=`exec_sqlcmd "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME='$ORI_TN'"`;
[[ -z "$is_table_exist" ]] && { logger "table:$ORI_TN not exist!" "ERROR"; exit 1; }; 
exec_sqlcmd "TRUNCATE TABLE $ORI_TN"; 
for HOST in $MGT_IP_LIST; do 
    query_cmd="INSERT $ORI_TN ( Overall, PowerSupply, Fan, Temp,"; 
    for I in `seq 0 63`; do query_cmd="$query_cmd FC$I,"; done
    query_cmd="$query_cmd hostname ) VALUES (";
    # get switch-status-policy-report
    curl -X GET -ku "$TOKEN" -H "Accept: application/yang-data+json" "https://$HOST/rest/running/brocade-maps/switch-status-policy-report" > "$tmp_json";
    value["Overall"]=`jq '.Response."switch-status-policy-report"."switch-health"' "$tmp_json"`;
    value["PowerSupply"]=`jq '.Response."switch-status-policy-report"."power-supply-health"' "$tmp_json"`;
    value["Fan"]=`jq '.Response."switch-status-policy-report"."fan-health"' "$tmp_json"`;
    value["Temp"]=`jq '.Response."switch-status-policy-report"."temperature-sensor-health"' "$tmp_json"`;
    query_cmd="$query_cmd '${value["overall"]}', '${value["power"]}', '${value["fan"]}', '${value["temperature"]}',";
    [[ -n "$DEBUG" ]] && { logger "check($HOST) status: ${value["overall"]}, ${value["power"]}, ${value["fan"]}, ${value["temperature"]} " "debug"; }
    # get fc port
    curl -X GET -ku "$TOKEN" -H "Accept: application/yang-data+json" "https://$HOST/rest/running/brocade-interface/fibrechannel" > "$tmp_json";
    for I in `seq 0 63`; do 
        item=".Response.fibrechannel|.[$I].\"physical-state\"";
        value["FC$I"]=`jq "$item" "$tmp_json"`;
        query_cmd="$query_cmd '${value["FC$I"]}',"
        [[ -n "$DEBUG" ]] && { logger "I($I) : value:${value["FC$I"]}" "debug"; }
    done
    #[[ -n "$DEBUG" ]] && { logger "check($HOST) status: ${value["overall"]}, ${value["power"]}, ${value["fan"]}, ${value["temperature"]} " "debug"; } # access wrong value
    #[[ -n "$DEBUG" ]] && { for I in `seq 0 63`; do logger "I($I) : value:${value["FC$I"]}" "debug"; done }; # access wrong value
    query_cmd="$query_cmd '$HOST' )"
    #[[ -n "$DEBUG" ]] && logger "$query_cmd" "debug";
    exec_sqlcmd "$query_cmd"; logger "insert $HOST to table($ORI_TN)";

    # clean up temporary file
	[[ -z "$DEBUG" ]] && [[ -f "$tmp_json" ]] && rm -f "$tmp_json"
done

exit 0;
