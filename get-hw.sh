#!/bin/bash
#
# define var
SH_VER="Version:20220414"
USAGE="Usage: $0 [hostname]."
PROGRAM_DIR="/var/tfx-daily"
# source file
if [[ -f "$PROGRAM_DIR/common.sh" ]]; then source "$PROGRAM_DIR/common.sh"; else echo "[ERROR] please check missing file: $PROGRAM_DIR/common.sh"; exit 1; fi # logger, exec_sqlcmd
if [[ -f "$PROGRAM_DIR/redfish-func.sh" ]]; then source "$PROGRAM_DIR/redfish-func.sh"; else logger "please check missing file: $PROGRAM_DIR/redfish-func.sh" "ERROR"; exit 1; fi
# check var # error msg
[[ -z "$1" ]] && { echo "need \$1 as parameter."; exit 1; }
[[ "`jq --version`" =~ jq* ]] || { echo "[Error] Cannot find jq command."; exit 2; } # env err
rpm -qa | grep mssql &> /dev/null; [[ $? -eq 1 ]] && { echo "[Error] Cannot find mssql-tools rpm."; exit 2; }; # rpm -q mssql-tools # pkg name change mssql-tools18
[[ -z "`rpm -qa | grep msodbcsql`" ]] && { echo "[Error] Cannot find msodbcsql rpm."; exit 2; };
[[ -f "/opt/mssql-tools/bin/sqlcmd" ]] || { echo "[Error] Cannot find sqlcmd command."; exit 2; };
[[ -z $DB_SRV ]] && { echo "[Error] DB Server can't empty!"; exit 1; } # syntax error (?)
[[ -z $DB_USR ]] && { echo "[Error] DB Username can't empty!"; exit 1; }
[[ -z $DB_PW ]] && { echo "[Error] DB Password can't empty!"; exit 1; }
# main
srv_model=`get_model $(get_srv_ip "$1")`; # echo "[DEBUG] var:srv_model $srv_model";
set_var "$srv_model";

[[ -z "$RF_Path" ]] && { logger "$1 var:RF_Path null." "error"; exit 1; };
[[ -z "$RF_Key" ]] && { logger "$1 var:RF_Key null." "error"; exit 1; };
[[ -z "$table_postfix" ]] && { logger "$1 var:table_postfix null." "error"; exit 1; };
[[ -z "$column_name" ]] && { logger "$1 var:column_name null." "error"; exit 1; };
[[ -z "$index" ]] && { logger "$1 var:index null." "error"; exit 1; };

is_table_exist=`exec_sqlcmd "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME='HW_$table_postfix'"`;
[[ -z "$is_table_exist" ]] && { logger "table:HW_$table_postfix not exist!" "ERROR"; exit 1; }; 

# check recoed exist or not, insert / update value	
is_record_exist=`exec_sqlcmd "SELECT date FROM HW_$table_postfix WHERE hostname='$1'"`;
if [[ -z "$is_record_exist" ]]; then
	query_cmd="INSERT HW_$table_postfix (";
	# column_name
	for I in `seq 0 $index`; do query_cmd="$query_cmd ${column_name[$I]},"; done 
	query_cmd="$query_cmd hostname ) VALUES (";
	# key value
	for I in `seq 0 $index`; do query_cmd="$query_cmd '`get_redfish "$1" "${RF_Path[$I]}" "${RF_Key[$I]}"`',"; done 
	query_cmd="$query_cmd '$1' )";

	logger "insert $1 to table(HW_$table_postfix)"; # "insert table(HW_$table_postfix) query_cmd=$query_cmd" "debug";
else
	query_cmd="UPDATE HW_$table_postfix SET";
	for I in `seq 0 $index`; do 
		query_cmd="$query_cmd ${column_name[$I]}='`get_redfish "$1" "${RF_Path[$I]}" "${RF_Key[$I]}"`',";
	done
	query_cmd="$query_cmd date=CURRENT_TIMESTAMP WHERE hostname='$1'";
	
	logger "update $1 to table(HW_$table_postfix)"; # "update table(HW_$table_postfix) query_cmd=$query_cmd" "debug";
fi
exec_sqlcmd "$query_cmd";

exit 0;
