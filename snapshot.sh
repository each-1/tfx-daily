#!/bin/bash
#
# define var
SH_VER="Version:20220415"
PROGRAM_DIR="/var/tfx-daily"
# source file
if [[ -f "$PROGRAM_DIR/common.sh" ]]; then source "$PROGRAM_DIR/common.sh"; else echo "[ERROR] please check missing file: $PROGRAM_DIR/common.sh"; exit 1; fi # logger, exec_sqlcmd
# define function
# check var # error msg
rpm -q mssql-tools &> /dev/null; [[ $? -eq 1 ]] && { echo "[Error] Cannot find mssql-tools rpm."; exit 2; };
[[ -z "`rpm -qa | grep msodbcsql`" ]] && { echo "[Error] Cannot find msodbcsql rpm."; exit 2; };
[[ -f "/opt/mssql-tools/bin/sqlcmd" ]] || { echo "[Error] Cannot find sqlcmd command."; exit 2; };
[[ -z "$DB_SRV" ]] && { echo "[Error] DB Server can't empty!"; exit 1; } # syntax error (?)
[[ -z "$DB_USR" ]] && { echo "[Error] DB Username can't empty!"; exit 1; }
[[ -z "$DB_PW" ]] && { echo "[Error] DB Password can't empty!"; exit 1; }
# main
while [ "$1" != "" ]; do
    case "$1" in
    help|--help|-h|?) # 
        echo "snapshot.sh [TABLENAME <Gen10|R740|all>] { TABLENAME .. }";
        exit 0;
    ;;
    all)
        query_cmd="SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME LIKE 'TEPL_%'";
        TN_LIST=`exec_sqlcmd "$query_cmd"`;
        break;
    ;;
    *)
        TN_LIST="$TN_LIST $1";
    esac
	shift 
done
[[ -z "$TN_LIST" ]] && { TN_LIST="Gen10"; }; # default snapshot HW
# { TN_LIST=`exec_sqlcmd "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME LIKE 'TEPL_%'"`; };

for I in $TN_LIST; do
    # reset and set ORI_TN, TEPL_TN
    ORI_TN=""; TEPL_TN=""; 
    set_tablename "$I";

    # check ORI_TN, TEPL_TN not zero
    [[ -z "$ORI_TN" ]] && { logger "var:ORI_TN empty!" "wran"; continue; };
    [[ -z "$TEPL_TN" ]] && { logger "var:TEPL_TN empty!" "wran"; continue; };

    query_cmd="TRUNCATE TABLE $TEPL_TN; INSERT INTO $TEPL_TN SELECT * FROM $ORI_TN; UPDATE $TEPL_TN SET date=CURRENT_TIMESTAMP;";
    exec_sqlcmd "$query_cmd";
done

exit 0;