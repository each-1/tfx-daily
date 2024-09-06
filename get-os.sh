#!/bin/bash
#
# define var
SH_VER="Version:20230502"
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
[[ "$1" = "--debug" ]] && DEBUG="true";
tmp_csv="$PROGRAM_DIR/tmp_$$.csv"; while [ -f "$tmp_csv" ]; do tmp_csv="$PROGRAM_DIR/tmp_r$RANDOM.csv"; done # 
TOKEN="";
ORI_TN="OS_icinga";
column_name=("DiskUsage" "MountPoint" "NTP" "Bonding" "Routing");
keyword=("Disk usage" "Mount Runtime Config" "NTP-time" "NIC Bonding Status" "Routing table");
let index=${#column_name[@]}-1;

# grep oob /etc/hosts | awk '{print $2}' | cut -d '-' -f1 | sort
HOSTS="srv1 srv2 

# update
curl -s -u "$TOKEN" -H 'Accept: application/json' -X GET "http://192.168.xxx.xxx/icingaweb2/reporting/report/download?type=csv&id=5" > "$tmp_csv";

for H in $HOSTS; do 
    record=`egrep ^"$H|ilo-$H" "$tmp_csv"`; [[ -z "$record" ]] && { logger "get-os: CSV no $H record." "DEBUG"; continue; }; # severity should be warn (?)

    # check recoed exist or not, insert / update value
    is_record_exist=`exec_sqlcmd "SELECT date FROM $ORI_TN WHERE hostname='$H'"`;
    if [[ -z "$is_record_exist" ]]; then
        query_cmd="INSERT $ORI_TN (";
        for I in `seq 0 $index`; do query_cmd="$query_cmd ${column_name[$I]},"; done
        query_cmd="$query_cmd hostname ) VALUES (";
        for I in `seq 0 $index`; do 
            value=`echo -e "$record" | grep "${keyword[$I]}" | cut -d ',' -f4`;
            [[ -n "$DEBUG" ]] && { logger "$H ${column_name[$I]}:$value" "debug"; }
            query_cmd="$query_cmd '$value',"; 
        done
        query_cmd="$query_cmd '$H' )"; # logger "$query_cmd" "debug";

        logger "insert $H to table($ORI_TN)";
    else
        query_cmd="UPDATE $ORI_TN SET";
        for I in `seq 0 $index`; do 
            value=`echo -e "$record" | grep "${keyword[$I]}" | cut -d ',' -f4`;
            [[ -n "$DEBUG" ]] && { logger "$H ${column_name[$I]}:$value" "debug"; }
            query_cmd="$query_cmd ${column_name[$I]}='$value',";
        done
        query_cmd="$query_cmd date=CURRENT_TIMESTAMP WHERE hostname='$H'";

        logger "update $H to table($ORI_TN)";
    fi
    [[ -n "$DEBUG" ]] && { logger "$H: $query_cmd" "debug"; }
    exec_sqlcmd "$query_cmd";
done

# clean up temporary file
[[ -z "$DEBUG" ]] && [[ -f "$tmp_csv" ]] && rm -f "$tmp_csv"

exit 0;
