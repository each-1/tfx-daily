#!/bin/bash
#
# check RemoteSyslogServer 
#
# define var
SH_VER="Version:20240411"
USAGE="Usage: $0 [hostname]."
PROGRAM_DIR="/var/tfx-daily"
_result_path="/tmp/chk-rsyslog.csv";
# source file
if [[ -f "$PROGRAM_DIR/common.sh" ]]; then source "$PROGRAM_DIR/common.sh"; else echo "[ERROR] please check missing file: $PROGRAM_DIR/common.sh"; exit 1; fi # logger, exec_sqlcmd
if [[ -f "$PROGRAM_DIR/redfish-func.sh" ]]; then source "$PROGRAM_DIR/redfish-func.sh"; else logger "please check missing file: $PROGRAM_DIR/redfish-func.sh" "ERROR"; exit 1; fi
# check var # error msg
# main
_hosts=`grep -e ^192.168.xxx -e ^192.168.ooo /var/tfx-daily/oa-hosts.txt | awk '{print $2}'`; # oa 

[[ -f "$_result_path" ]] && { rm -f "$_result_path"; };
echo "hostname, model, enabled, rsyslogsrv_ip" > "$_result_path";
for I in $_hosts; do 
    set_rsyslog "$I"; # $2 null as check mode 
done

exit 0;
