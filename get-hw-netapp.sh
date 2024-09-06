#!/bin/bash
#
# define var
SH_VER="Version:20230614"
PROGRAM_DIR="/var/tfx-daily"
MGT_IP_LIST="srv-a1 srv-a2 srv-b1 srv-b2" 
_API_PASSWD="xxxx"
TOKEN="xxxx:$_API_PASSWD"
_na_cluster_name=""; #
_exception_volume="vol1 vol2 bkvol datavol";
# source file
if [[ -f "$PROGRAM_DIR/common.sh" ]]; then source "$PROGRAM_DIR/common.sh"; else echo "[ERROR] please check missing file: $PROGRAM_DIR/common.sh"; exit 1; fi # logger, exec_sqlcmd
# define function
function is_exception_volume {
    [[ -z "$1" ]] && { logger "is_exception_volume need 1 parameters" "debug"; return 4; } # $1 as volume name
    #[[ -n "$DEBUG" ]] && logger "is_exception_volume: input var1($1)" "debug"; echo "$1, $I";
	res=0;
    for I in $_exception_volume; do [[ "`echo $1 | cut -d '"' -f2`" = "$I" ]] && { [[ -n "$DEBUG" ]] && logger "is_exception_volume: ExceptionVolume($1)" "debug"; res="1"; }; done
    echo $res;
}
# check var # error msg
[[ "`jq --version`" =~ jq* ]] || { echo "[Error] Cannot find jq command."; exit 2; }
rpm -q mssql-tools &> /dev/null; [[ $? -eq 1 ]] && { echo "[Error] Cannot find mssql-tools rpm."; exit 2; };
[[ -z "`rpm -qa | grep msodbcsql`" ]] && { echo "[Error] Cannot find msodbcsql rpm."; exit 2; };
[[ -f "/opt/mssql-tools/bin/sqlcmd" ]] || { echo "[Error] Cannot find sqlcmd command."; exit 2; };
[[ -z "$DB_SRV" ]] && { echo "[Error] DB Server can't empty!"; exit 1; } # syntax error (?)
[[ -z "$DB_USR" ]] && { echo "[Error] DB Username can't empty!"; exit 1; }
[[ -z "$DB_PW" ]] && { echo "[Error] DB Password can't empty!"; exit 1; }
# main
tmp_json="$PROGRAM_DIR/tmp_$$.json"; while [ -f "$tmp_json" ]; do tmp_json="$PROGRAM_DIR/tmp_r$RANDOM.json"; done # 
ORI_TN="HW_NetApp"; # set tablename
[[ "$1" = "--debug" ]] && DEBUG="true";

# check table exist 
is_table_exist=`exec_sqlcmd "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME='INFO_NetApp_Volume'"`;
[[ -z "$is_table_exist" ]] && { logger "table:INFO_NetApp_Volume not exist!" "ERROR"; exit 1; }; 
exec_sqlcmd "TRUNCATE TABLE INFO_NetApp_Volume"; # INFO_NetApp_Volume table keep usage, iops
is_table_exist=`exec_sqlcmd "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME='$ORI_TN'"`;
[[ -z "$is_table_exist" ]] && { logger "table:$ORI_TN not exist!" "ERROR"; exit 1; }; 
exec_sqlcmd "TRUNCATE TABLE $ORI_TN"; # 

for HOST in $MGT_IP_LIST; do 
    query_cmd="INSERT $ORI_TN ("; 
    for COL in `exec_sqlcmd "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME='$ORI_TN'"`; do # COL name
        [[ "$COL" = "hostname" ]] && continue; 
        [[ "$COL" = "date" ]] && continue; # auto CURRENT_TIMESTAMP
        query_cmd="$query_cmd $COL,";
    done
    query_cmd="$query_cmd hostname ) VALUES (";

    # Chassis
    value["Chassis"]=`curl -X GET -ku "$TOKEN" "https://$HOST/api/cluster/chassis?fields=state" | jq '.records[0]|.state'`;
    query_cmd="$query_cmd '${value["Chassis"]}',";

    # Power
    LINK=`curl -X GET -ku "$TOKEN" "https://$HOST/api/cluster/chassis/" | jq '.records[0]|._links.self.href' | cut -d '"' -f2`;
    curl -X GET -ku "$TOKEN" "https://$HOST$LINK?fields=frus,state" > "$tmp_json";
    power_state=(`jq '.frus[8,9,10,11]|.state' "$tmp_json"`); # get Power state
    [[ -n "$DEBUG" ]] && { power_id=(`jq '.frus[8,9,10,11]|.id' "$tmp_json"`); };
    let index=${#power_state[@]}-1;
    for I in `seq 0 $index`; do
        query_cmd="$query_cmd '${power_state["$I"]}',";
        [[ -n "$DEBUG" ]] && { logger "$HOST Power:{ ${power_id["$I"]}:${power_state["$I"]} }" "debug"; }
    done
    # Fan
    fan_state=(`jq '.frus[0,1,2,3,4,5,6,7]|.state' "$tmp_json"`); # get Fan state
    [[ -n "$DEBUG" ]] && { fan_id=(`jq '.frus[0,1,2,3,4,5,6,7]|.id' "$tmp_json"`); };
    let index=${#fan_state[@]}-1;
    for I in `seq 0 $index`; do
        query_cmd="$query_cmd '${fan_state["$I"]}',";
        [[ -n "$DEBUG" ]] && { logger "$HOST Fan:{ ${fan_id["$I"]}:${fan_state["$I"]} }" "debug"; }
    done

    # Disk
    LINK=`curl -X GET -ku "$TOKEN" "https://$HOST/api/storage/shelves/" | jq '.records[0]|._links.self.href' | cut -d '"' -f2`;
    curl -X GET -ku "$TOKEN" "https://$HOST$LINK?fields=state,disk_count" > "$tmp_json";
    disk_state=`jq '.state' "$tmp_json"`; # get Disk_State
    disk_count=`jq '.disk_count' "$tmp_json"`; # get Disk_Count
    query_cmd="$query_cmd '$disk_state', '$disk_count',";
    [[ -n "$DEBUG" ]] && logger "$HOST $LINK Disk_State($disk_state) Disk_Count($disk_count)" "debug";

    # Node
    curl -X GET -ku "$TOKEN" "https://$HOST/api/cluster/nodes?fields=name,state" > "$tmp_json";
    node_name=`jq '.records[0]|.name' "$tmp_json"`; # get Node0
    node_state=`jq '.records[0]|.state' "$tmp_json"`;
    [[ -n "$DEBUG" ]] && { logger "$HOST Node0:{ $node_name:$node_state }" "debug"; }
    query_cmd="$query_cmd '$node_name', '$node_state',";
    node_name=`jq '.records[1]|.name' "$tmp_json"`; # get Node1
    node_state=`jq '.records[1]|.state' "$tmp_json"`;
    [[ -n "$DEBUG" ]] && { logger "$HOST Node1:{ $node_name:$node_state }" "debug"; }
    query_cmd="$query_cmd '$node_name', '$node_state',";
    [[ "`jq '.num_records' $tmp_json`" -gt "2" ]] && { logger "$HOST NodeNumber(`jq '.num_records' $tmp_json`) more than ArrayNumber(2)" "warn"; };

    # Interface (Ethernet)
    curl -X GET -ku "$TOKEN" "https://$HOST/api/network/ethernet/ports?fields=name,state" > "$tmp_json";
    eth_state=(`jq '.records[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25]|.state' "$tmp_json"`); # get Eth statue
    [[ -n "$DEBUG" ]] && { eth_name=(`jq '.records[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25]|.name' "$tmp_json"`); };
    [[ "`jq '.num_records' $tmp_json`" -gt "${#eth_state[@]}" ]] && { logger "$HOST EthNumber(`jq '.num_records' $tmp_json`) more than ArrayNumber(${#eth_state[@]})" "warn"; };
    let index=${#eth_state[@]}-1;
    for I in `seq 0 $index`; do
        query_cmd="$query_cmd '${eth_state["$I"]}',";
        [[ -n "$DEBUG" ]] && { logger "$HOST Eth$I:{ ${eth_name["$I"]}:${eth_state["$I"]} }" "debug"; }
    done

    # Interface (FC)
    curl -X GET -ku "$TOKEN" "https://$HOST/api/network/fc/ports?fields=name,state" > "$tmp_json";
    fc_state=(`jq '.records[0,1,2,3,4,5,6,7]|.state' "$tmp_json"`); # get fc state
    [[ "`jq '.num_records' $tmp_json`" -gt "${#fc_state[@]}" ]] && { logger "$HOST FC_Number(`jq '.num_records' $tmp_json`) more than ArrayNumber(${#fc_state[@]})" "warn"; };
    let index=${#fc_state[@]}-1;
    for I in `seq 0 $index`; do
        query_cmd="$query_cmd '${fc_state["$I"]}',";
    done

    # HA
    curl -X GET -ku "$TOKEN" "https://$HOST/api/cluster/nodes?fields=name,ha" > "$tmp_json";
    ha_name=(`jq '.records[0,1]|.name' "$tmp_json"`);
    ha_giveback=(`jq '.records[0,1]|.ha.giveback.state' "$tmp_json"`);
    ha_takeover=(`jq '.records[0,1]|.ha.takeover.state' "$tmp_json"`);
    ha_port0_state=(`jq '.records[0,1]|.ha.ports[0]|.state' "$tmp_json"`);
    ha_port1_state=(`jq '.records[0,1]|.ha.ports[1]|.state' "$tmp_json"`);
    query_cmd="$query_cmd '${ha_name[0]}', '${ha_giveback[0]}', '${ha_takeover[0]}', '${ha_port0_state[0]}', '${ha_port1_state[0]}',";
    query_cmd="$query_cmd '${ha_name[1]}', '${ha_giveback[1]}', '${ha_takeover[1]}', '${ha_port0_state[1]}', '${ha_port1_state[1]}',";

    # Service IP 
    curl -X GET -ku "$TOKEN" "https://$HOST/api/network/ip/interfaces?fields=name,state" > "$tmp_json";
    sip_state=(`jq '.records[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29]|.state' "$tmp_json"`); # get SIP statue
    [[ -n "$DEBUG" ]] && { sip_name=(`jq '.records[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29]|.name' "$tmp_json"`); };
    [[ "`jq '.num_records' $tmp_json`" -gt "${#sip_state[@]}" ]] && { logger "$HOST SIP_Number(`jq '.num_records' $tmp_json`) more than ArrayNumber(${#sip_state[@]})" "warn"; };
    let index=${#sip_state[@]}-1;
    for I in `seq 0 $index`; do
        query_cmd="$query_cmd '${sip_state["$I"]}',";
        [[ -n "$DEBUG" ]] && { logger "$HOST SIP$I:{ ${sip_name["$I"]}:${sip_state["$I"]} }" "debug"; }
    done

    # San Path
    curl -X GET -ku "$TOKEN" "https://$HOST/api/network/fc/interfaces?fields=name,state" > "$tmp_json";
    san_path=(`jq '.records[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15]|.state' "$tmp_json"`); # get San Path statue
    [[ -n "$DEBUG" ]] && { san_name=(`jq '.records[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15]|.name' "$tmp_json"`); };
    [[ "`jq '.num_records' $tmp_json`" -gt "${#san_path[@]}" ]] && { logger "$HOST SanPathNumber(`jq '.num_records' $tmp_json`) more than ArrayNumber(${#san_path[@]})" "warn"; };
    let index=${#san_path[@]}-1;
    for I in `seq 0 $index`; do
        query_cmd="$query_cmd '${san_path["$I"]}',";
        [[ -n "$DEBUG" ]] && { logger "$HOST San_Path$I:{ ${san_name["$I"]}:${san_path["$I"]} }" "debug"; }
    done

    # NFS
    curl -X GET -ku "$TOKEN" "https://$HOST/api/protocols/nfs/services?fields=state" > "$tmp_json";
    nfs_state=(`jq '.records[0,1,2,3,4,5,6,7,8,9]|.state' "$tmp_json"`); # get NFS statue
    [[ -n "$DEBUG" ]] && { nfs_name=(`jq '.records[0,1,2,3,4,5,6,7,8,9]|.svm.name' "$tmp_json"`); };
    [[ "`jq '.num_records' $tmp_json`" -gt "${#nfs_state[@]}" ]] && { logger "$HOST NFS_Number(`jq '.num_records' $tmp_json`) more than ArrayNumber(${#nfs_state[@]})" "warn"; };
    let index=${#nfs_state[@]}-1;
    for I in `seq 0 $index`; do
        query_cmd="$query_cmd '${nfs_state["$I"]}',";
        [[ -n "$DEBUG" ]] && { logger "$HOST NFS$I:{ ${nfs_name["$I"]}:${nfs_state["$I"]} }" "debug"; }
    done

    # CIFS
	_num_cifs_col=10; # update value while add new colume
    cifs_state=(`sshpass -p $_API_PASSWD ssh apiuser@$HOST vserver cifs server show | grep WORKGROUP | awk '{print $3}'`); # grep -E "_na1|_na2"
    [[ -n "$DEBUG" ]] && { cifs_name=(`sshpass -p xxxx ssh apiuser@$HOST vserver cifs server show | grep WORKGROUP | awk '{print $2}'`); };
    let index=${#cifs_state[@]}-1;
    for I in `seq 0 $index`; do
        query_cmd="$query_cmd '${cifs_state["$I"]}',";
        [[ -n "$DEBUG" ]] && { logger "$HOST CIFS$I:{ ${cifs_name["$I"]}:${cifs_state["$I"]} }" "debug"; }
    done
    [[ -n "$DEBUG" ]] && { logger "Check CIFS Colume: var number_cifs_state(${#cifs_state[@]}), _num_cifs_col($_num_cifs_col)" "debug"; }
    if [[ "${#cifs_state[@]}" -gt "$_num_cifs_col" ]]; then
        logger "$HOST CIFS_Number(${#cifs_state[@]}) more than ArrayNumber($_num_cifs_col)" "warn";
    elif [[ "${#cifs_state[@]}" -ne "$_num_cifs_col" ]]; then
        # fill un-use colume with null
		let _start_index="${#cifs_state[@]}"+1; # skip last array index (?
        for I in `seq "$_start_index" "$_num_cifs_col"`; do query_cmd="$query_cmd 'null',"; 
        [[ -n "$DEBUG" ]] && { logger "Check CIFS: var I($I), _num_cifs_col($_num_cifs_col)" "debug"; }; done 
    fi
    #while [ "$I" -lt "$_num_cifs_col" ]; do query_cmd="$query_cmd '',"; logger "CIFS: check null $I" "debug"; let I=$I+1; done # fill un-use colume with null

    # Volume Usage
    curl -X GET -ku "$TOKEN" "https://$HOST/api/private/cli/volume?fields=size,available,percent-used&pretty=false" > "$tmp_json";
    vol_usage=(`jq '.records[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49]|.percent_used' "$tmp_json"`); # get Volume Usage
    vol_name=(`jq '.records[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49]|.volume' "$tmp_json"`); # get Volume Name
    _exception_num=0; # number of exception volume
    let index=${#vol_usage[@]}-1;
    for I in `seq 0 $index`; do
	    _is_exception=`is_exception_volume ${vol_name["$I"]}`; #logger "_is_exception($_is_exception)" "debug"; 
	    if [[ "$_is_exception" -eq 1 ]]; then 
		    let _exception_num=$_exception_num+1;
		    logger "$HOST Exception Volume($_exception_num): ${vol_name["$I"]}" "debug";
		    query_cmd="$query_cmd 'Exception',"; # Exception Volume insert 'Exception' to Usage colume
		else
		    query_cmd="$query_cmd '${vol_usage["$I"]}',";
		fi
        
        [[ -n "$DEBUG" ]] && { logger "$HOST Volume$I:{ ${vol_name["$I"]} percent_used:${vol_usage["$I"]} }" "debug"; }
    done
	# num_records < #vol_usage -> ok
    [[ "`jq '.num_records' $tmp_json`" -gt "${#vol_usage[@]}" ]] && { logger "$HOST VolumeNumber(`jq '.num_records' $tmp_json`) more than ArrayNumber(${#vol_usage[@]})" "warn"; };
    # Volume Usage - size available to info table (INFO_NetApp_Volume)
    index=`jq '.num_records' $tmp_json`; let index=$index-1;
    for I in `seq 0 $index`; do
        record_json="`jq .records[$I] $tmp_json`"
        vol_path="`echo $record_json | jq '.vserver' | cut -d '"' -f2`:`echo $record_json | jq '.volume' | cut -d '"' -f2`";
        vol_size="`echo $record_json | jq '.size'`"; # api get vol_size with byte
        vol_size="`byte_h $vol_size`";
        vol_available="`echo $record_json | jq '.available'`";
        vol_available="`byte_h $vol_available`";
        vol_percent="`echo $record_json | jq '.percent_used'`";

        [[ -n "$DEBUG" ]] && { logger "Host($HOST) - $vol_path Size:$vol_size Available:$vol_available ($vol_percent%)" "debug"; };
        exec_sqlcmd "INSERT INFO_NetApp_Volume ( VserverVolume, Size, Available, Usage, hostname ) VALUES ( '$vol_path', '$vol_size', '$vol_available', '$vol_percent', '$HOST' );";
    done

    query_cmd="$query_cmd '$HOST' )";
    exec_sqlcmd "$query_cmd"; logger "insert $HOST to table($ORI_TN)";
    #[[ -n "$DEBUG" ]] && { logger "query_cmd: $query_cmd" "debug"; }; # final check query_cmd

    # clean up temporary file
    [[ -z "$DEBUG" ]] && [[ -f "$tmp_json" ]] && rm -f "$tmp_json";
done

# iops to info table (INFO_NetApp_Volume)
for _CN in $_na_cluster_name; do 
    # get vol name and key
	_vol_name=(`curl -sk -X GET "https://192.168.xxx.xxx/api/datacenter/storage/volumes?cluster.name=$_CN" -H "accept: application/json" --user $TOKEN | jq -r '.records[] | .name'`);
    _vol_key=(`curl -sk -X GET "https://192.168.xxx.xxx/api/datacenter/storage/volumes?cluster.name=$_CN" -H "accept: application/json" --user $TOKEN | jq -r '.records[] | .key'`); #
    # get iops data
    let _index=${#_vol_key[@]}-1; 
    for I in `seq 0 $_index`; do 
        [[ "${_vol_name[$I]}" =~ .*_root ]] && { [[ -n "$DEBUG" ]] && logger "iops: skip volume(${_vol_name[$I]})." "debug"; continue; };
        _iops_data=`curl -sk -X GET "https://192.168.xxx.xxx/api/datacenter/storage/volumes/${_vol_key[$I]}/metrics?interval=1d" -H "accept: application/json" --user $TOKEN | jq -r ".samples[] | .timestamp,.iops.total" | sed '$!N;s/\n/ /g' | sort -rn -k2 | head -n 1`; 
        [[ -z "$_iops_data" ]] && { logger "iops: $_CN ${_vol_name[$I]} no IOPS data."; continue; }
        _iops_timestamp=`echo $_iops_data | awk '{print $1}' | cut -d '.' -f1`;
        _iops_data=`echo $_iops_data | awk '{print $2}' | cut -d '.' -f1`; # int only (?
        
        query_cmd="UPDATE INFO_NetApp_Volume SET IOPS='$_iops_data', io_timestamp='$_iops_timestamp' where VserverVolume like '%:${_vol_name[$I]}';"; # and hostname like '$_CN%' , p_a400ah_mgt p_a400_ah # ah name different
        exec_sqlcmd "$query_cmd"; #[[ -n "$DEBUG" ]] && { logger "iops: exec: $query_cmd key: ${_vol_key[$I]}" "debug"; };
    done;
    logger "Update $_CN iops data.";
done;

exit 0;
