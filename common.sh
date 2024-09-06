#!/bin/bash
#
# define var
SH_VER="Version:20240215"
T_STAMP="date +%Y-%m-%d-%H:%M:%S"	# timestamp format
LOG_PATH="/var/log/tfx-daily"
PATH="/home/cose/.local/bin:/home/cose/bin:/usr/share/Modules/bin:/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin"
# default DB connection info
[[ -z "$DB_SRV" ]] && { DB_SRV="SYSCHKDB"; };
DB_USR="oooo"
DB_PW="xxxx"

# define function 
function log2file {
	[[ -z "$1" ]] && { echo "log2file need 1 parameter"; return 1; } # $1 as log msg
	local level="$2";
	[[ -z "$level" ]] && { level="info"; } # default log level 
	echo -e "`$T_STAMP` `hostname 2> /dev/null || hostid` `echo $0 | sed -e s%$PROGRAM_DIR/%%g 2> /dev/null`[$$]: [$level] $1" >> "$LOG_PATH";
	return 0;
}
function logger {
	[[ -z "$1" ]] && { echo "logger need 1 parameter"; return 1; } # $1 as log msg
	log2file "$1" "$2"
	if [[ -z "$2" ]]; then echo -e "[info] $1" > /dev/tty; else echo -e "[$2] $1" > /dev/tty; fi
	return 0;
}
function get_hostname {
	[[ -z $1 ]] && { echo "get_hostname need 1 parameter"; return 1; } # $1 as server ip
	# ip to hostname
	local res=$(grep -w "$1" /etc/hosts | awk '{print $2}'); 
	[[ -z $res ]] && res="$1";

	echo "$res"
}
function get_srv_ip {
	[[ -z $1 ]] && { echo "get_srv_ip need 1 parameter"; return 1; } # $1 as hostname
	# ip to hostname
	local res=$(grep -w "$1" /etc/hosts | awk '{print $1}' | head -n1); 
	[[ -z $res ]] && { logger "get_srv_ip: Can NOT find $1 IP! Please check hosts file." "warn"; res="$1"; } #exit 1;

	echo "$res"
}
function byte_h { # byte to human readable (MB, GB, TB)
	[[ "$1" =~ ^[0-9]+$ ]] || { echo "byte_h need 1 int parameter"; return 1; } # $1 as byte number
	res="`expr $1 / 1024`"; # KB
	if [[ "$res" -ge "1073741824" ]]; then res="`echo "$res 1073741824" | awk '{printf "%.2f", $1/$2}'` TB"; # 1024*1024*1024 = 1,073,741,824
	elif [[ "$res" -ge "1048576" ]]; then res="`echo "$res 1048576" | awk '{printf "%.2f", $1/$2}'` GB"; # 1024*1024 = 1,048,576 
    elif [[ "$res" -ge "1024" ]]; then res="`echo "$res 1024" | awk '{printf "%.2f", $1/$2}'` MB";
    else res="$res KB"; fi

	echo "$res";
}
function exec_sqlcmd { # "SELECT redfish_path, jq_filter, date FROM rule_table WHERE module='ProLiant DL380 Gen10'"
	[[ -z $1 ]] && { echo "exec_sqlcmd need 1 parameter"; return 1; } # $1 as sqlcmd query
	local SQL_CMD="/opt/mssql-tools/bin/sqlcmd -D -S $DB_SRV"; # sqlcmd default option
	[[ "$DB_SRV" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] && SQL_CMD="/opt/mssql-tools/bin/sqlcmd -S $DB_SRV -d SYSCHKDB"; # check (-d) db name 
	local res=`$SQL_CMD -U $DB_USR -P $DB_PW -h -1 -s ',' -W -Q "SET NOCOUNT ON; $1" || { logger "exec_sqlcmd: DB($DB_SRV) connection fail." "ERROR"; return 4; }`;
	echo -e "$res" | grep -v -E "^[[:space:]]*$|^\("; # | awk '{if(NR>2)print}'; 
}
function set_tablename { # keyword -> table name (ORI_TN, TEPL_TN, SUMMARY_TN, HISTORY_TN)
	[[ -z "$1" ]] && { logger "set_tablename need 1 parameter" "ERROR"; return 1; } # $1 as keyword
    case "$1" in
    TEPL_Gen10|HW_Gen10|Gen10|gen10|g10|"ProLiant DL380 Gen10")
        ORI_TN="HW_Gen10"; TEPL_TN="TEPL_Gen10"; SUMMARY_TN="HW_Summary_Gen10"; HISTORY_TN="HW_History_Gen10";
    ;;
    TEPL_R740|HW_R740|R740|r740|R740xd|r740xd|"PowerEdge R740xd"|"PowerEdge R740"|"PowerEdge R640")
        ORI_TN="HW_R740"; TEPL_TN="TEPL_R740"; SUMMARY_TN="HW_Summary_R740"; HISTORY_TN="HW_History_R740";
    ;;
    HW_SanSwitch|TEPL_SanSwitch|SanSwitch|sanswitch)
        ORI_TN="HW_SanSwitch"; TEPL_TN="TEPL_SanSwitch"; SUMMARY_TN="HW_Summary_SanSwitch"; HISTORY_TN="HW_History_SanSwitch";
    ;;
    TEPL_NetApp|HW_NetApp|NA|na|netapp|NetApp)
        ORI_TN="HW_NetApp"; TEPL_TN="TEPL_NetApp"; SUMMARY_TN="HW_Summary_NetApp"; HISTORY_TN="HW_History_NetApp";
    ;;
    OS_icinga|TEPL_icinga|OS|icinga|os)
        ORI_TN="OS_icinga"; TEPL_TN="TEPL_icinga"; SUMMARY_TN="OS_Summary_icinga"; HISTORY_TN="OS_History_icinga";
    ;;
    TEPL_Gen9|HW_Gen9|Gen9|gen9|g9|"ProLiant DL380 Gen9")
        ORI_TN="HW_Gen9"; TEPL_TN="TEPL_Gen9"; SUMMARY_TN="HW_Summary_Gen9"; HISTORY_TN="HW_History_Gen9";
    ;;
    TEPL_R730|HW_R730|R730|r730|"PowerEdge R730")
        ORI_TN="HW_R730"; TEPL_TN="TEPL_R730"; SUMMARY_TN="HW_Summary_R730"; HISTORY_TN="HW_History_R730";
    ;;
    *)
        logger "set_tablename: Not define keyword($1)." "warn";
        return 1;
    esac
    return 0;
}

