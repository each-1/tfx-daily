#!/bin/bash
#
# check-login:
#   grep login record, counting and insert to database
#
# define var
_version="Version:20221128";
_script_dir="/ws/tfx-daily";
_exception_host="192.168.xxx.xxx|192.168.ooo.ooo";
_login_ok=`egrep "$(date -d '1 days ago' '+%h %_d')" /var/log/secure | egrep -i sshd | grep -v COMMAND | egrep -i 'Accepted password|Accepted publickey' | egrep -v "$_exception_host" | awk '{print $4,$9}' | egrep -v 'for' | egrep -iv '[0-9].[0-9].[0-9].[0-9]' | sort | sed 's/://g' | uniq -c`;
_login_fail=`egrep "$(date -d '1 days ago' '+%h %_d')" /var/log/secure | egrep -i sshd | grep -v COMMAND | egrep -i 'Failed' | egrep -v "$_exception_host" | awk '{print $4,$9}' | egrep -v 'for|stat|invalid|create|socket' | egrep -iv '[0-9].[0-9].[0-9].[0-9]' | sort | sed 's/://g' | uniq -c`;
# source file
if [[ -f "$_script_dir/common.sh" ]]; then source "$_script_dir/common.sh"; else echo "[ERROR] please check missing file: $_script_dir/common.sh"; exit 1; fi # logger, exec_sqlcmd
# check var # error msg
rpm -q mssql-tools &> /dev/null; [[ $? -eq 1 ]] && { echo "[Error] Cannot find mssql-tools rpm."; exit 2; };
[[ -z "`rpm -qa | grep msodbcsql`" ]] && { echo "[Error] Cannot find msodbcsql rpm."; exit 2; };
[[ -f "/opt/mssql-tools/bin/sqlcmd" ]] || { echo "[Error] Cannot find sqlcmd command."; exit 2; };
[[ -z "$DB_SRV" ]] && { echo "[Error] DB Server can't empty!"; exit 1; } # syntax error (?)
[[ -z "$DB_USR" ]] && { echo "[Error] DB Username can't empty!"; exit 1; }
[[ -z "$DB_PW" ]] && { echo "[Error] DB Password can't empty!"; exit 1; }
# main

# check table exist
is_table_exist=`exec_sqlcmd "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME='Login_Count'"`;
[[ -z "$is_table_exist" ]] && { logger "check-login table:Login_Count not exist!" "ERROR"; exit 4; };
is_table_exist=`exec_sqlcmd "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME='Login_Fail'"`;
[[ -z "$is_table_exist" ]] && { logger "check-login table:Login_Fail not exist!" "ERROR"; exit 4; };

# truncate login table
exec_sqlcmd "TRUNCATE TABLE Login_Count";
exec_sqlcmd "TRUNCATE TABLE Login_Fail";

# -u 9; choose file descriptor 9 (8, 7 ..)
if [[ -z "$_login_ok" ]]; then
    logger "[check-login] login data was empty." "info";
else    
    while IFS= read -u 9 -r line; do
        _count=`echo $line | awk '{print $1}'`;
        _host=`echo $line | awk '{print $2}'`;
        _user=`echo $line | awk '{print $3}'`;

        # check colume name
        case "$_user" in
        root)
            colume_name="root_count";
        ;;
        changer)
            colume_name="changer_count";
        ;;
        op11)
            colume_name="op11_count";
        ;;
        ap1)
            colume_name="ap1_count";
        ;;
        #user0)
        #    colume_name="user0_count"; # user0~5 template
        #;;
        *)
            logger "Login_Count: username($_user) not in colume case." "ERROR";
        ;;
        esac

        # update table
        is_record_exist=`exec_sqlcmd "SELECT date FROM Login_Count WHERE hostname='$_host'"`;
        if [[ -z "$is_record_exist" ]]; then
            query_cmd="INSERT Login_Count ( hostname, $colume_name ) VALUES ( '$_host', '$_count' )";
            logger "[check-login] insert: (host:$_host user:$_user count:$_count)" "info"; # login ok
        else
            query_cmd="UPDATE Login_Count SET $colume_name='$_count', date=CURRENT_TIMESTAMP WHERE hostname='$_host'";
            logger "[check-login] update: (host:$_host user:$_user count:$_count)" "info"; # login ok
        fi
        exec_sqlcmd "$query_cmd";

        unset _host _user _count;
    done 9<<< "$_login_ok"
fi

if [[ -z "$_login_fail" ]]; then 
    logger "[check-login] login fail data was empty." "info";    
else
    while IFS= read -u 9 -r line; do
        _count=`echo $line | awk '{print $1}'`;
        _host=`echo $line | awk '{print $2}'`;
        _user=`echo $line | awk '{print $3}'`;

        # insert table
        query_cmd="INSERT Login_Fail ( hostname, id, fail_count ) VALUES ( '$_host', '$_user', '$_count' )";
        logger "[check-login][login-fail] host:$_host user:$_user count:$_count." "warn";
        exec_sqlcmd "$query_cmd";

        unset _host _user _count;
    done 9<<< "$_login_fail"
fi

# update history table
query_cmd="INSERT INTO Login_Count_History SELECT * FROM Login_Count"; #
exec_sqlcmd "$query_cmd";

query_cmd="INSERT INTO Login_Fail_History SELECT * FROM Login_Fail"; #
exec_sqlcmd "$query_cmd";

exit 0;
