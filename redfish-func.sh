#!/bin/bash
#
# define var
SH_VER="Version:20240131"
TOKEN="" # read only account
REDFISH_PATH="" # temp var
RAW_JSON="" # temp var

# define function 
function get_model {
    #DEBUG="true";
    [[ -z "$1" ]] && { echo "update_template need 1 parameter"; return 1; } # $1 as server hostname or ip
    EXE_CMD="curl --connect-timeout 5 -s https://$1/redfish/v1/Systems/ --insecure -u $TOKEN -L";
    [[ -n "$DEBUG" ]] && echo "[debug] get_model: exec $EXE_CMD | jq '.Members|.[0].\"@odata.id\"'";
    local path=`$EXE_CMD | jq '.Members|.[0]."@odata.id"' | cut -d '"' -f2`;
    [[ -n "$DEBUG" ]] && echo "[debug] get_model: var $path";
    [[ -z "$path" ]] && { logger "get_model: host($1) var(path) null. (Maybe timeout)" "ERROR"; return 4; }; 
    EXE_CMD="curl --connect-timeout 5 -s https://$1$path --insecure -u $TOKEN -L";
    [[ -n "$DEBUG" ]] && echo "[debug] get_model: exec $EXE_CMD | jq '.Model'";
    local res=`$EXE_CMD | jq '.Model' | cut -d '"' -f2`;

    [[ -z "$res" ]] && { echo "[ERROR] get_model: @$1 return value can't be null"; return 4; } # func logic fail
    echo $res;
}
function get_redfish { # replace `echo $raw_json | jq ${RF_Key[$I]}` for multi rfpath with same rfkey
    [[ -z "$1" ]] && { logger "get_redfish need 3 parameters" "debug"; return 1; } # $1 as hostname
    [[ -z "$2" ]] && { logger "get_redfish need 3 parameters" "debug"; return 1; } # $2 as rf_path
    [[ -z "$3" ]] && { logger "get_redfish need 3 parameters" "debug"; return 1; } # $3 as rf_key

    [[ "$REDFISH_PATH" = "$2" ]] || { REDFISH_PATH="$2"; local HOST_IP=`get_srv_ip "$1"`; RAW_JSON=`curl --connect-timeout 5 -s https://$HOST_IP$REDFISH_PATH --insecure -u $TOKEN -L`; };
    [[ -z "$RAW_JSON" ]] && { logger "get_redfish: $1 var(RAW_JSON) empty! Maybe timeout, maybe check redfish path. (REDFISH_PATH: $REDFISH_PATH)" "ERROR"; exit 1; };
    #logger "--before jq-- $RAW_JSON" "debug";
    if [[ -z `echo $RAW_JSON | grep -n "</html>"` ]]; then echo $RAW_JSON | jq "$3"; else echo $RAW_JSON | sed -E -e 's/.*<\/html>//g' | jq "$3"; fi; # logger "VAR:RAW_JSON(`echo $RAW_JSON | sed -E -e 's/.*<\/html>//g'`)" "debug";
}
function set_power_type { # ResetType "On", "ForceOff", "GracefulShutdown", "ForceRestart", "Nmi", "PushPowerButton", "GracefulRestart"
    [[ -z "$1" ]] && { logger "set_power_type need $1 as hostname parameters" "debug"; return 1; } # $1 as hostname
    _model=`get_model $(get_srv_ip "$1")`; # echo "[DEBUG] var:srv_model $srv_model";
    
    case $2 in # check ResetType
    "On"|"ForceOff"|"GracefulShutdown"|"ForceRestart"|"PushPowerButton"|"GracefulRestart")
        _type="\'{\"ResetType\": \"$2\"}\'";
    ;;
    "")
        _type="\'{\"ResetType\": \"On\"}\'"; # Gen10 ResetType
    ;;
    *) # |"Nmi"
        logger "function(set_power_type) not support $2 type!" "error";
        return 1;
    esac
    
    case $_model in
    "ProLiant DL380 Gen10"|"Gen10")
        path="/redfish/v1/Systems/1/Actions/ComputerSystem.Reset";
        curl --connect-timeout 5 --header "Content-Type: application/json" --request POST --data $_type https://$1$path --insecure -u $TOKEN; # action method
        return $?;
    ;;
    "ProLiant DL380 Gen9"|"Gen9")
        #ilorest reboot On 
        [[ -z "$admin_usr" ]] && { logger "Please specify the user name." "warn"; return 1; };
        [[ -z "$admin_pw" ]] && { logger "Please check the password." "warn"; return 1; };
        ilorest reboot "$2" --url="$1" --user "$admin_usr" --password "$admin_pw"; # action method
        return $?;
    ;;
    "PowerEdge R740xd"|"PowerEdge R740"|"PowerEdge R640")
    ;;
    "PowerEdge R730"|"R730")
    ;;
    *)
        logger "function(set_power_type) not define $1 module($_model) type!" "warn";
        return 1;
    esac    

    return 0;
}
function set_rsyslog { # 
    [[ -z "$1" ]] && { logger "get_rsyslog: need \$1 as hostname parameters" "debug"; return 1; } # $1 as hostname
    [[ -z "$2" ]] && { logger "get_rsyslog: $1 need \$2 as logsrv ip ?" "debug"; } # $2 null as check mode
    [[ -z "$_result_path" ]] && { _result_path="/tmp/chk-rsyslog"; };
    _model=`get_model $(get_srv_ip "$1")`; # echo "[DEBUG] var:srv_model $srv_model"; 
    
    # setting RemoteSyslogServer # $2 null as check mode
    if [[ ! -z "$2" ]]; then
        case $_model in
        "ProLiant DL380 Gen10"|"Gen10")
            path="/redfish/v1/Managers/1/NetworkProtocol/";
            TOKEN="";
            
            # enable RemoteSyslog # {"Oem": {"Hpe": <--- !!!
            _enabled=`get_redfish "$I" "$path" ".Oem.Hpe.RemoteSyslogEnabled"`; # check RemoteSyslogEnabled
            [[ $_enabled != true ]] && { curl --connect-timeout 5 --header "Content-Type: application/json" --request PATCH --data-raw '{"Oem": {"Hpe": {"RemoteSyslogEnabled": true}}}' https://$1$path --insecure -u $TOKEN; };
            # get RemoteSyslogServer config before changed
            _rsyslogsrv=`get_redfish "$1" "$path" ".Oem.Hpe.RemoteSyslogServer"`;
            if [[ -z `echo $_rsyslogsrv | grep -w "$2"` ]]; then
                if [[ "$_rsyslogsrv" = "\"\"" ]]; then _resource_msg="{\"Oem\": {\"Hpe\": {\"RemoteSyslogServer\": \"$2\"}}}"; else _resource_msg="{\"Oem\": {\"Hpe\": {\"RemoteSyslogServer\": \"$_rsyslogsrv;$2\"}}}"; fi;
                curl --connect-timeout 5 --header "Content-Type: application/json" --request PATCH --data-raw "$_resource_msg" https://$1$path --insecure -u $TOKEN; # action method
            fi
        ;;
        "ProLiant DL380 Gen9"|"Gen9")
            path="/redfish/v1/Managers/1/NetworkService/";
            TOKEN="";
            
            # enable RemoteSyslog # {"Oem": {"Hp": <--- ...
            _enabled=`get_redfish "$I" "$path" ".Oem.Hp.RemoteSyslogEnabled"`; # check RemoteSyslogEnabled
            [[ $_enabled != true ]] && { curl --connect-timeout 5 --header "Content-Type: application/json" --request PATCH --data-raw '{"Oem": {"Hp": {"RemoteSyslogEnabled": true}}}' https://$1$path --insecure -u $TOKEN; };
            # get RemoteSyslogServer config before changed
            _rsyslogsrv=`get_redfish "$1" "$path" ".Oem.Hp.RemoteSyslogServer"`;
            if [[ -z `echo $_rsyslogsrv | grep -w "$2"` ]]; then
                if [[ "$_rsyslogsrv" = "\"\"" ]]; then _resource_msg="{\"Oem\": {\"Hp\": {\"RemoteSyslogServer\": \"$2\"}}}"; else _resource_msg="{\"Oem\": {\"Hp\": {\"RemoteSyslogServer\": \"$_rsyslogsrv;$2\"}}}"; fi;
                curl --connect-timeout 5 --header "Content-Type: application/json" --request PATCH --data-raw "$_resource_msg" https://$1$path --insecure -u $TOKEN; # action method
            fi
        ;;
        "PowerEdge R740xd"|"PowerEdge R740"|"PowerEdge R640")
            path="/redfish/v1/Managers/iDRAC.Embedded.1/Attributes";
            HOST_IP=`get_srv_ip "$1"`;
            TOKEN="";
            
            # enable RemoteSyslog
            _enabled=`get_redfish "$1" "$path" '.Attributes["SysLog.1.SysLogEnable"]'`;
            [[ $_enabled !=  "\"Enabled\"" ]] && { curl --connect-timeout 5 --header "Content-Type: application/json" --request PATCH --data-raw '{"Attributes": {"SysLog.1.SysLogEnable": "Enabled"}}' https://$HOST_IP$path --insecure -u $TOKEN; };
            # set RemoteSyslogServer # R640 api only eat server ip
            curl --connect-timeout 5 --header "Content-Type: application/json" --request PATCH --data-raw "{\"Attributes\": {\"SysLog.1.Server1\": \"$2\"}}" https://$HOST_IP$path --insecure -u $TOKEN;
        ;;
        "PowerEdge R730"|"R730")
        ;;
        *)
            logger "function(set_rsyslog) not define $1 module($_model) type!" "warn";
            return 1;
        esac 
    fi

    # check RemoteSyslogServer setting, output csv format
    case $_model in
    "ProLiant DL380 Gen9"|"Gen9")
        path="/redfish/v1/Managers/1/NetworkService/";
        _enabled=`get_redfish "$I" "$path" ".Oem.Hp.RemoteSyslogEnabled"`; # check RemoteSyslogEnabled
        _rsyslogsrv=`get_redfish "$1" "$path" ".Oem.Hp.RemoteSyslogServer"`;
        echo "$1, $_model, $_enabled, $_rsyslogsrv" | tee -a $_result_path;
    ;;
    "ProLiant DL380 Gen10"|"Gen10")
        path="/redfish/v1/Managers/1/NetworkProtocol/";
        _enabled=`get_redfish "$I" "$path" ".Oem.Hpe.RemoteSyslogEnabled"`; # check RemoteSyslogEnabled
        _rsyslogsrv=`get_redfish "$1" "$path" ".Oem.Hpe.RemoteSyslogServer"`;
        echo "$1, $_model, $_enabled, $_rsyslogsrv" | tee -a $_result_path;
    ;;
    "PowerEdge R740xd"|"PowerEdge R740"|"PowerEdge R640")
        path="/redfish/v1/Managers/iDRAC.Embedded.1/Attributes";
        HOST_IP=`get_srv_ip "$1"`;
        _enabled=`get_redfish "$1" "$path" '.Attributes["SysLog.1.SysLogEnable"]'`;
        _rsyslogsrv=`get_redfish "$1" "$path" '.Attributes["SysLog.1.Server1"], .Attributes["SysLog.1.Server2"], .Attributes["SysLog.1.Server3"]'`;
        _rsyslogsrv=`echo $_rsyslogsrv | tr '\n' ';'`;
        echo "$1, $_model, $_enabled, $_rsyslogsrv" | tee -a $_result_path;
    ;;
    "PowerEdge R730"|"R730")
    ;;
    *)
        logger "function(set_rsyslog - check RemoteSyslogServer setting) not define $1 module($_model) type!" "warn";
        return 1;
    esac
    
    return 0;
}
function set_var {
	[[ -z "$1" ]] && { echo "set_var need 1 parameter"; return 1; } # $1 as model

    case $1 in
    "ProLiant DL380 Gen10"|"ProLiant_DL380_Gen10"|"Gen10")
        RF_Path=("/redfish/v1/Systems/1/"
        "/redfish/v1/Systems/1/"
        "/redfish/v1/Systems/1/"
        "/redfish/v1/Systems/1/"
        "/redfish/v1/Systems/1/"
        "/redfish/v1/Systems/1/"
        "/redfish/v1/Systems/1/"
        "/redfish/v1/Systems/1/"
        "/redfish/v1/Systems/1/"
        "/redfish/v1/Systems/1/"
        "/redfish/v1/Systems/1/"
        "/redfish/v1/Systems/1/"
        "/redfish/v1/Systems/1/");
        RF_Key=(".Status.State"
        ".Oem.Hpe.AggregateHealthStatus.AgentlessManagementService"
        ".Oem.Hpe.AggregateHealthStatus.BiosOrHardwareHealth.Status.Health"
        ".Oem.Hpe.AggregateHealthStatus.FanRedundancy"
        ".Oem.Hpe.AggregateHealthStatus.Fans.Status.Health"
        ".Oem.Hpe.AggregateHealthStatus.Memory.Status.Health"
        ".Oem.Hpe.AggregateHealthStatus.Network.Status.Health"
        ".Oem.Hpe.AggregateHealthStatus.PowerSupplyRedundancy"
        ".Oem.Hpe.AggregateHealthStatus.PowerSupplies.Status.Health"
        ".Oem.Hpe.AggregateHealthStatus.Processors.Status.Health"
        ".Oem.Hpe.AggregateHealthStatus.SmartStorageBattery.Status.Health"
        ".Oem.Hpe.AggregateHealthStatus.Storage.Status.Health"
        ".Oem.Hpe.AggregateHealthStatus.Temperatures.Status.Health");
        # define column_name mapping with RF_Key
        column_name=("Stat"
        "AMS"
        "BiosHW"
        "FanRedundancy"
        "Fans"
        "Mem"
        "Network"
        "PowerRedundancy"
        "Power"
        "CPU"
        "RaidBattery"
        "Storage"
        "Temp");

        table_postfix="Gen10";
        let index=${#RF_Key[@]}-1; # echo "[DEBUG] index:$index"; 
    ;;
    "PowerEdge R740xd"|"PowerEdge R740"|"R740"|"PowerEdge R640")
        RF_Path=("/redfish/v1/Systems/System.Embedded.1"
        "/redfish/v1/Systems/System.Embedded.1/Oem/Dell/DellSystem/System.Embedded.1"
        "/redfish/v1/Systems/System.Embedded.1/Oem/Dell/DellSystem/System.Embedded.1"
        "/redfish/v1/Systems/System.Embedded.1/Oem/Dell/DellSystem/System.Embedded.1"
        "/redfish/v1/Systems/System.Embedded.1/Oem/Dell/DellSystem/System.Embedded.1"
        "/redfish/v1/Systems/System.Embedded.1/Oem/Dell/DellSystem/System.Embedded.1"
        "/redfish/v1/Systems/System.Embedded.1/Oem/Dell/DellSystem/System.Embedded.1"
        "/redfish/v1/Systems/System.Embedded.1/Oem/Dell/DellSystem/System.Embedded.1"
        "/redfish/v1/Systems/System.Embedded.1/Oem/Dell/DellSystem/System.Embedded.1"
        "/redfish/v1/Systems/System.Embedded.1/Oem/Dell/DellSystem/System.Embedded.1"
        "/redfish/v1/Chassis/System.Embedded.1/NetworkAdapters/NIC.Integrated.1"
        "/redfish/v1/Chassis/System.Embedded.1/NetworkAdapters/NIC.Slot.2"
        "/redfish/v1/Chassis/System.Embedded.1/NetworkAdapters/NIC.Slot.3"
        "/redfish/v1/Chassis/System.Embedded.1/NetworkAdapters/NIC.Slot.4"
        "/redfish/v1/Chassis/System.Embedded.1/NetworkAdapters/NIC.Slot.5"
        "/redfish/v1/Chassis/System.Embedded.1/NetworkAdapters/FC.Slot.1"
        "/redfish/v1/Chassis/System.Embedded.1/NetworkAdapters/FC.Slot.7"
        "/redfish/v1/Chassis/System.Embedded.1/NetworkAdapters/NIC.Integrated.1/NetworkPorts/NIC.Integrated.1-1"
        "/redfish/v1/Chassis/System.Embedded.1/NetworkAdapters/NIC.Integrated.1/NetworkPorts/NIC.Integrated.1-2"
        "/redfish/v1/Chassis/System.Embedded.1/NetworkAdapters/NIC.Integrated.1/NetworkPorts/NIC.Integrated.1-3"
        "/redfish/v1/Chassis/System.Embedded.1/NetworkAdapters/NIC.Integrated.1/NetworkPorts/NIC.Integrated.1-4"
        "/redfish/v1/Chassis/System.Embedded.1/NetworkAdapters/NIC.Slot.2/NetworkPorts/NIC.Slot.2-1"
        "/redfish/v1/Chassis/System.Embedded.1/NetworkAdapters/NIC.Slot.2/NetworkPorts/NIC.Slot.2-2"
        "/redfish/v1/Chassis/System.Embedded.1/NetworkAdapters/NIC.Slot.3/NetworkPorts/NIC.Slot.3-1"
        "/redfish/v1/Chassis/System.Embedded.1/NetworkAdapters/NIC.Slot.3/NetworkPorts/NIC.Slot.3-2"
        "/redfish/v1/Chassis/System.Embedded.1/NetworkAdapters/NIC.Slot.4/NetworkPorts/NIC.Slot.4-1"
        "/redfish/v1/Chassis/System.Embedded.1/NetworkAdapters/NIC.Slot.4/NetworkPorts/NIC.Slot.4-2"
        "/redfish/v1/Chassis/System.Embedded.1/NetworkAdapters/NIC.Slot.4/NetworkPorts/NIC.Slot.4-3"
        "/redfish/v1/Chassis/System.Embedded.1/NetworkAdapters/NIC.Slot.4/NetworkPorts/NIC.Slot.4-4"
        "/redfish/v1/Chassis/System.Embedded.1/NetworkAdapters/NIC.Slot.5/NetworkPorts/NIC.Slot.5-1"
        "/redfish/v1/Chassis/System.Embedded.1/NetworkAdapters/NIC.Slot.5/NetworkPorts/NIC.Slot.5-2"
        "/redfish/v1/Chassis/System.Embedded.1/NetworkAdapters/NIC.Slot.5/NetworkPorts/NIC.Slot.5-3"
        "/redfish/v1/Chassis/System.Embedded.1/NetworkAdapters/NIC.Slot.5/NetworkPorts/NIC.Slot.5-4"
        "/redfish/v1/Chassis/System.Embedded.1/NetworkAdapters/FC.Slot.1/NetworkPorts/FC.Slot.1-1"
        "/redfish/v1/Chassis/System.Embedded.1/NetworkAdapters/FC.Slot.1/NetworkPorts/FC.Slot.1-2"
        "/redfish/v1/Chassis/System.Embedded.1/NetworkAdapters/FC.Slot.7/NetworkPorts/FC.Slot.7-1"
        "/redfish/v1/Chassis/System.Embedded.1/NetworkAdapters/FC.Slot.7/NetworkPorts/FC.Slot.7-2"
        "/redfish/v1/Systems/System.Embedded.1/Bios"
        "/redfish/v1/Systems/System.Embedded.1/Bios"
        "/redfish/v1/Systems/System.Embedded.1/Bios"
        "/redfish/v1/Systems/System.Embedded.1/Bios"
        "/redfish/v1/Systems/System.Embedded.1/Bios"
        "/redfish/v1/Systems/System.Embedded.1/Bios"
        "/redfish/v1/Systems/System.Embedded.1/Bios"
        "/redfish/v1/Systems/System.Embedded.1/Bios"
        "/redfish/v1/Systems/System.Embedded.1/Bios"
        "/redfish/v1/Systems/System.Embedded.1/Bios");
        RF_Key=(".Status.State"
        ".BatteryRollupStatus"
        ".CPURollupStatus"
        ".CurrentRollupStatus"
        ".FanRollupStatus"
        ".PSRollupStatus"
        ".StorageRollupStatus"
        ".SysMemPrimaryStatus"
        ".TempRollupStatus"
        ".VoltRollupStatus"
        ".Status.HealthRollup"
        ".Status.HealthRollup"
        ".Status.HealthRollup"
        ".Status.HealthRollup"
        ".Status.HealthRollup"
        ".Status.HealthRollup"
        ".Status.HealthRollup"
        ".LinkStatus"
        ".LinkStatus"
        ".LinkStatus"
        ".LinkStatus"
        ".LinkStatus"
        ".LinkStatus"
        ".LinkStatus"
        ".LinkStatus"
        ".LinkStatus"
        ".LinkStatus"
        ".LinkStatus"
        ".LinkStatus"
        ".LinkStatus"
        ".LinkStatus"
        ".LinkStatus"
        ".LinkStatus"
        ".LinkStatus"
        ".LinkStatus"
        ".LinkStatus"
        ".LinkStatus"
        ".Attributes.BootMode"
        ".Attributes.ControlledTurbo"
        ".Attributes.EnergyPerformanceBias"
        ".Attributes.LogicalProc"
        ".Attributes.ProcHwPrefetcher"
        ".Attributes.ProcPwrPerf"
        ".Attributes.ProcTurboMode"
        ".Attributes.ProcVirtualization"
        ".Attributes.SysProfile"
        ".Attributes.SystemBiosVersion");
        # define column_name mapping with RF_Key
        column_name=("Stat"
        "Battery"
        "CPU"
        "CurrentRollupStatus"
        "Fan"
        "PowerSupply"
        "Storage"
        "SysMem"
        "Temp"
        "Volt"
        "NIC1"
        "NIC2"
        "NIC3"
        "NIC4"
        "NIC5"
        "FC1"
        "FC7"
        "NIC1_P1"
        "NIC1_P2"
        "NIC1_P3"
        "NIC1_P4"
        "NIC2_P1"
        "NIC2_P2"
        "NIC3_P1"
        "NIC3_P2"
        "NIC4_P1"
        "NIC4_P2"
        "NIC4_P3"
        "NIC4_P4"
        "NIC5_P1"
        "NIC5_P2"
        "NIC5_P3"
        "NIC5_P4"
        "FC1_P1"
        "FC1_P2"
        "FC7_P1"
        "FC7_P2"
        "BIOS_BootMode"
        "BIOS_ControlledTurbo"
        "BIOS_EnergyPerformanceBias"
        "BIOS_LogicalProc"
        "BIOS_ProcHwPrefetcher"
        "BIOS_ProcPwrPerf"
        "BIOS_ProcTurboMode"
        "BIOS_ProcVirtualization"
        "BIOS_SysProfile"
        "BIOS_SystemBiosVersion");

        table_postfix="R740";
        let index=${#RF_Key[@]}-1; # echo "[DEBUG] index:$index"; 
    ;;
    "ProLiant DL380 Gen9"|"ProLiant_DL380_Gen9"|"Gen9")
        RF_Path=("/redfish/v1/Systems/1/"
        "/redfish/v1/Systems/1/"
        "/redfish/v1/Systems/1/"
        "/redfish/v1/Systems/1/"
        "/redfish/v1/Systems/1/"
        "/redfish/v1/Systems/1/SmartStorage/ArrayControllers/0/DiskDrives/0/"
        "/redfish/v1/Systems/1/SmartStorage/ArrayControllers/0/DiskDrives/1/"
        "/redfish/v1/Systems/1/SmartStorage/ArrayControllers/0/DiskDrives/2/"
        "/redfish/v1/Systems/1/SmartStorage/ArrayControllers/0/DiskDrives/3/"
        "/redfish/v1/Systems/1/SmartStorage/ArrayControllers/0/DiskDrives/4/"
        "/redfish/v1/Systems/1/SmartStorage/ArrayControllers/0/DiskDrives/5/"
        "/redfish/v1/Systems/1/SmartStorage/ArrayControllers/0/DiskDrives/6/"
        "/redfish/v1/Systems/1/SmartStorage/ArrayControllers/0/DiskDrives/7/"
        "/redfish/v1/Systems/1/SmartStorage/ArrayControllers/0/DiskDrives/8/"
        "/redfish/v1/Systems/1/SmartStorage/ArrayControllers/0/DiskDrives/9/"
        "/redfish/v1/Systems/1/SmartStorage/ArrayControllers/0/DiskDrives/10/"
        "/redfish/v1/Systems/1/SmartStorage/ArrayControllers/0/DiskDrives/11/"
        "/redfish/v1/Systems/1/SmartStorage/ArrayControllers/0/DiskDrives/12/"
        "/redfish/v1/Systems/1/SmartStorage/ArrayControllers/0/DiskDrives/13/"
        "/redfish/v1/Systems/1/SmartStorage/ArrayControllers/0/DiskDrives/14/"
        "/redfish/v1/Systems/1/SmartStorage/ArrayControllers/0/DiskDrives/15/"
        "/redfish/v1/Systems/1/SmartStorage/ArrayControllers/0/DiskDrives/16/"
        "/redfish/v1/Systems/1/SmartStorage/ArrayControllers/0/DiskDrives/17/"
        "/redfish/v1/Systems/1/SmartStorage/ArrayControllers/0/DiskDrives/18/"
        "/redfish/v1/Systems/1/SmartStorage/ArrayControllers/0/DiskDrives/19/"
        "/redfish/v1/Systems/1/SmartStorage/ArrayControllers/0/DiskDrives/20/"
        "/redfish/v1/Systems/1/SmartStorage/ArrayControllers/0/DiskDrives/21/"
        "/redfish/v1/Systems/1/SmartStorage/ArrayControllers/0/DiskDrives/22/"
        "/redfish/v1/Systems/1/SmartStorage/ArrayControllers/0/DiskDrives/23/"
        "/redfish/v1/Systems/1/SmartStorage/ArrayControllers/0/DiskDrives/24/"
        "/redfish/v1/Systems/1/SmartStorage/ArrayControllers/0/DiskDrives/25/"
        "/redfish/v1/Systems/1/SmartStorage/ArrayControllers/0/DiskDrives/26/"
        "/redfish/v1/Systems/1/SmartStorage/ArrayControllers/0/DiskDrives/27/"
        "/redfish/v1/Systems/1/SmartStorage/ArrayControllers/0/DiskDrives/28/"
        "/redfish/v1/Systems/1/SmartStorage/ArrayControllers/0/DiskDrives/29/"
        "/redfish/v1/Systems/1/SmartStorage/ArrayControllers/0/DiskDrives/30/"
        "/redfish/v1/Systems/1/SmartStorage/ArrayControllers/0/DiskDrives/31/"
        "/redfish/v1/Systems/1/SmartStorage/ArrayControllers/0/DiskDrives/32/"
        "/redfish/v1/Systems/1/SmartStorage/ArrayControllers/0/DiskDrives/33/"
        "/redfish/v1/Systems/1/SmartStorage/ArrayControllers/0/DiskDrives/34/"
        "/redfish/v1/Systems/1/EthernetInterfaces/1/"
        "/redfish/v1/Systems/1/EthernetInterfaces/2/"
        "/redfish/v1/Systems/1/EthernetInterfaces/3/"
        "/redfish/v1/Systems/1/EthernetInterfaces/4/"
        "/redfish/v1/Systems/1/EthernetInterfaces/5/"
        "/redfish/v1/Systems/1/bios/settings/"
        "/redfish/v1/Systems/1/bios/settings/"
        "/redfish/v1/Systems/1/bios/settings/"
        "/redfish/v1/Systems/1/bios/settings/"
        "/redfish/v1/Systems/1/bios/settings/"
        "/redfish/v1/Systems/1/bios/settings/"
        "/redfish/v1/Systems/1/bios/settings/"
        "/redfish/v1/Systems/1/bios/settings/"
        "/redfish/v1/Systems/1/bios/settings/"
        "/redfish/v1/Systems/1/bios/settings/"
        "/redfish/v1/Systems/1/bios/settings/"
        "/redfish/v1/Systems/1/bios/settings/"
        "/redfish/v1/Systems/1/bios/settings/"
        "/redfish/v1/Systems/1/bios/settings/"
        "/redfish/v1/Systems/1/");
        RF_Key=(".Status.State"
        ".MemorySummary.Status.HealthRollUp"
        ".PowerState"
        ".ProcessorSummary.Status.HealthRollUp"
        ".Oem.Hp.Battery[0].Condition"
        ".Status.Health" 
        ".Status.Health"
        ".Status.Health"
        ".Status.Health"
        ".Status.Health"
        ".Status.Health"
        ".Status.Health"
        ".Status.Health"
        ".Status.Health"
        ".Status.Health"
        ".Status.Health"
        ".Status.Health"
        ".Status.Health"
        ".Status.Health"
        ".Status.Health"
        ".Status.Health"
        ".Status.Health"
        ".Status.Health"
        ".Status.Health"
        ".Status.Health"
        ".Status.Health"
        ".Status.Health"
        ".Status.Health"
        ".Status.Health"
        ".Status.Health"
        ".Status.Health"
        ".Status.Health"
        ".Status.Health"
        ".Status.Health"
        ".Status.Health"
        ".Status.Health"
        ".Status.Health"
        ".Status.Health"
        ".Status.Health"
        ".Status.Health"
        ".Status.Health" 
        ".Status.Health"
        ".Status.Health"
        ".Status.Health"
        ".Status.Health"
        ".BootMode" 
        ".CollabPowerControl"
        ".DynamicPowerCapping"
        ".EnergyPerfBias"
        ".IntelQpiFreq"
        ".PowerProfile"
        ".MinProcIdlePower"
        ".PowerRegulator"
        ".ProcHyperthreading"
        ".ProcVirtualization"
        ".QpiSnoopConfig"
        ".ThermalConfig"
        ".TimeFormat"
        ".TimeZone"
        ".Oem.Hp.Bios.Current.VersionString");

        # define column_name mapping with RF_Key
        column_name=("Stat"
        "Mem"
        "Power"
        "CPU"
        "RaidBattery"
        "Disk0"
        "Disk1"
        "Disk2"
        "Disk3"
        "Disk4"
        "Disk5"
        "Disk6"
        "Disk7"
        "Disk8"
        "Disk9"
        "Disk10"
        "Disk11"
        "Disk12"
        "Disk13"
        "Disk14"
        "Disk15"
        "Disk16"
        "Disk17"
        "Disk18"
        "Disk19"
        "Disk20"
        "Disk21"
        "Disk22"
        "Disk23"
        "Disk24"
        "Disk25"
        "Disk26"
        "Disk27"
        "Disk28"
        "Disk29"
        "Disk30"
        "Disk31"
        "Disk32"
        "Disk33"
        "Disk34"
        "NIC1"
        "NIC2"
        "NIC3"
        "NIC4"
        "NIC5"
        "BIOS_BootMode"
        "BIOS_CollabPowerControl"
        "BIOS_DynamicPowerCapping"
        "BIOS_EnergyPerfBias"
        "BIOS_IntelQpiFreq"
        "BIOS_PowerProfile"
        "BIOS_MinProcIdlePower"
        "BIOS_PowerRegulator"
        "BIOS_ProcHyperthreading"
        "BIOS_ProcVirtualization"
        "BIOS_QpiSnoopConfig"
        "BIOS_ThermalConfig"
        "BIOS_TimeFormat"
        "BIOS_TimeZone"
        "BIOS_VersionString");

	# Not found yet. 
        #"AMS" # Maybe not needed 
        #"Network" # not everyone has PhysicalPorts .Status.Health
        #"Temp"

        table_postfix="Gen9";
        let index=${#RF_Key[@]}-1; # echo "[DEBUG] index:$index";
    ;;
    "PowerEdge R730"|"R730"|"r730")
        RF_Path=("/redfish/v1/Systems/System.Embedded.1"
        "/redfish/v1/Systems/System.Embedded.1"
        "/redfish/v1/Systems/System.Embedded.1"
        "/redfish/v1/Systems/System.Embedded.1"
        "/redfish/v1/Systems/System.Embedded.1/Bios"
        "/redfish/v1/Systems/System.Embedded.1/Bios"
        "/redfish/v1/Systems/System.Embedded.1/Bios"
        "/redfish/v1/Systems/System.Embedded.1/Bios"
        "/redfish/v1/Systems/System.Embedded.1/Bios"
        "/redfish/v1/Systems/System.Embedded.1/Bios"
        "/redfish/v1/Systems/System.Embedded.1/Bios"
        "/redfish/v1/Systems/System.Embedded.1/Bios"
        "/redfish/v1/Systems/System.Embedded.1/Bios"
        "/redfish/v1/Systems/System.Embedded.1/Bios"
        "/redfish/v1/Systems/System.Embedded.1/Bios"
        "/redfish/v1/Systems/System.Embedded.1/Bios"
        "/redfish/v1/Systems/System.Embedded.1/Bios"
        "/redfish/v1/Systems/System.Embedded.1/NetworkAdapters/FC.Slot.1"
        "/redfish/v1/Systems/System.Embedded.1/NetworkAdapters/FC.Slot.5"
        "/redfish/v1/Systems/System.Embedded.1/NetworkAdapters/FC.Slot.7"
        "/redfish/v1/Systems/System.Embedded.1/NetworkAdapters/NIC.Integrated.1"
        "/redfish/v1/Systems/System.Embedded.1/NetworkAdapters/NIC.Slot.2"
        "/redfish/v1/Systems/System.Embedded.1/NetworkAdapters/NIC.Slot.3"
        "/redfish/v1/Systems/System.Embedded.1/NetworkAdapters/NIC.Slot.4"
        "/redfish/v1/Systems/System.Embedded.1/NetworkAdapters/NIC.Slot.5"
        "/redfish/v1/Systems/System.Embedded.1/NetworkAdapters/NIC.Slot.6"
        "/redfish/v1/Systems/System.Embedded.1/NetworkAdapters/NIC.Slot.7"
        "/redfish/v1/Systems/System.Embedded.1/NetworkAdapters/FC.Slot.1/NetworkPorts/FC.Slot.1-1"
        "/redfish/v1/Systems/System.Embedded.1/NetworkAdapters/FC.Slot.7/NetworkPorts/FC.Slot.7-1"
        "/redfish/v1/Systems/System.Embedded.1/NetworkAdapters/NIC.Integrated.1/NetworkPorts/NIC.Integrated.1-1"
        "/redfish/v1/Systems/System.Embedded.1/NetworkAdapters/NIC.Integrated.1/NetworkPorts/NIC.Integrated.1-2"
        "/redfish/v1/Systems/System.Embedded.1/NetworkAdapters/NIC.Integrated.1/NetworkPorts/NIC.Integrated.1-3"
        "/redfish/v1/Systems/System.Embedded.1/NetworkAdapters/NIC.Integrated.1/NetworkPorts/NIC.Integrated.1-4"
        "/redfish/v1/Systems/System.Embedded.1/NetworkAdapters/NIC.Slot.2/NetworkPorts/NIC.Slot.2-1"
        "/redfish/v1/Systems/System.Embedded.1/NetworkAdapters/NIC.Slot.2/NetworkPorts/NIC.Slot.2-2"
        "/redfish/v1/Systems/System.Embedded.1/NetworkAdapters/NIC.Slot.3/NetworkPorts/NIC.Slot.3-1"
        "/redfish/v1/Systems/System.Embedded.1/NetworkAdapters/NIC.Slot.3/NetworkPorts/NIC.Slot.3-2"
        "/redfish/v1/Systems/System.Embedded.1/NetworkAdapters/NIC.Slot.4/NetworkPorts/NIC.Slot.4-1"
        "/redfish/v1/Systems/System.Embedded.1/NetworkAdapters/NIC.Slot.4/NetworkPorts/NIC.Slot.4-2"
        "/redfish/v1/Systems/System.Embedded.1/NetworkAdapters/NIC.Slot.4/NetworkPorts/NIC.Slot.4-3"
        "/redfish/v1/Systems/System.Embedded.1/NetworkAdapters/NIC.Slot.4/NetworkPorts/NIC.Slot.4-4"
        "/redfish/v1/Systems/System.Embedded.1/NetworkAdapters/NIC.Slot.5/NetworkPorts/NIC.Slot.5-1"
        "/redfish/v1/Systems/System.Embedded.1/NetworkAdapters/NIC.Slot.5/NetworkPorts/NIC.Slot.5-2"
        "/redfish/v1/Systems/System.Embedded.1/NetworkAdapters/NIC.Slot.6/NetworkPorts/NIC.Slot.6-1"
        "/redfish/v1/Systems/System.Embedded.1/NetworkAdapters/NIC.Slot.6/NetworkPorts/NIC.Slot.6-2"
        "/redfish/v1/Systems/System.Embedded.1/NetworkAdapters/NIC.Slot.6/NetworkPorts/NIC.Slot.6-3"
        "/redfish/v1/Systems/System.Embedded.1/NetworkAdapters/NIC.Slot.6/NetworkPorts/NIC.Slot.6-4"
        "/redfish/v1/Systems/System.Embedded.1/NetworkAdapters/NIC.Slot.7/NetworkPorts/NIC.Slot.7-1"
        "/redfish/v1/Systems/System.Embedded.1/NetworkAdapters/NIC.Slot.7/NetworkPorts/NIC.Slot.7-2"
        "/redfish/v1/Systems/System.Embedded.1/SimpleStorage/Controllers/RAID.Integrated.1-1"
        "/redfish/v1/Systems/System.Embedded.1/SimpleStorage/Controllers/RAID.Integrated.1-1"
        "/redfish/v1/Systems/System.Embedded.1/SimpleStorage/Controllers/RAID.Integrated.1-1"
        "/redfish/v1/Systems/System.Embedded.1/SimpleStorage/Controllers/RAID.Integrated.1-1"
        "/redfish/v1/Systems/System.Embedded.1/SimpleStorage/Controllers/RAID.Integrated.1-1"
        "/redfish/v1/Systems/System.Embedded.1/SimpleStorage/Controllers/RAID.Integrated.1-1"
        "/redfish/v1/Systems/System.Embedded.1/SimpleStorage/Controllers/RAID.Integrated.1-1"
        "/redfish/v1/Systems/System.Embedded.1/SimpleStorage/Controllers/RAID.Integrated.1-1"
        "/redfish/v1/Systems/System.Embedded.1/SimpleStorage/Controllers/RAID.Integrated.1-1"
        "/redfish/v1/Systems/System.Embedded.1/SimpleStorage/Controllers/RAID.Integrated.1-1"
        "/redfish/v1/Systems/System.Embedded.1/SimpleStorage/Controllers/RAID.Integrated.1-1"
        "/redfish/v1/Systems/System.Embedded.1/SimpleStorage/Controllers/RAID.Integrated.1-1"
        "/redfish/v1/Systems/System.Embedded.1/SimpleStorage/Controllers/RAID.Integrated.1-1"
        "/redfish/v1/Systems/System.Embedded.1/SimpleStorage/Controllers/RAID.Integrated.1-1"
        "/redfish/v1/Systems/System.Embedded.1/SimpleStorage/Controllers/RAID.Integrated.1-1"
        "/redfish/v1/Systems/System.Embedded.1/SimpleStorage/Controllers/RAID.Integrated.1-1");

        RF_Key=(".Status.State"
        ".ProcessorSummary.Status.Health"
        ".MemorySummary.Status.Health"
        ".PowerState"
        ".Attributes.BootMode"
        ".Attributes.ControlledTurbo"
        ".Attributes.EnergyEfficientTurbo"
        ".Attributes.EnergyPerformanceBias"
        ".Attributes.LogicalProc"
        ".Attributes.PowerSaver"
        ".Attributes.ProcHwPrefetcher"
        ".Attributes.ProcPwrPerf"
        ".Attributes.ProcTurboMode"
        ".Attributes.ProcVirtualization"
        ".Attributes.QpiSpeed"
        ".Attributes.SysProfile"
        ".Attributes.SystemBiosVersion"
        ".Status.State"
        ".Status.State"
        ".Status.State"
        ".Status.State"
        ".Status.State"
        ".Status.State"
        ".Status.State"
        ".Status.State"
        ".Status.State"
        ".Status.State"
        ".LinkStatus"
        ".LinkStatus"
        ".LinkStatus"
        ".LinkStatus"
        ".LinkStatus"
        ".LinkStatus"
        ".LinkStatus"
        ".LinkStatus"
        ".LinkStatus"
        ".LinkStatus"
        ".LinkStatus"
        ".LinkStatus"
        ".LinkStatus"
        ".LinkStatus"
        ".LinkStatus"
        ".LinkStatus"
        ".LinkStatus"
        ".LinkStatus"
        ".LinkStatus"
        ".LinkStatus"
        ".LinkStatus"
        ".LinkStatus"
        ".Devices[0]|.Status.Health"
        ".Devices[1]|.Status.Health"
        ".Devices[2]|.Status.Health"
        ".Devices[3]|.Status.Health"
        ".Devices[4]|.Status.Health"
        ".Devices[5]|.Status.Health"
        ".Devices[6]|.Status.Health"
        ".Devices[7]|.Status.Health"
        ".Devices[8]|.Status.Health"
        ".Devices[9]|.Status.Health"
        ".Devices[10]|.Status.Health"
        ".Devices[11]|.Status.Health"
        ".Devices[12]|.Status.Health"
        ".Devices[13]|.Status.Health"
        ".Devices[14]|.Status.Health"
        ".Devices[15]|.Status.Health");

        # define column_name mapping with RF_Key
        column_name=("Stat"
        "CPU"
        "Mem"
        "Power"
        "BIOS_BootMode"
        "BIOS_ControlledTurbo"
        "BIOS_EnergyEfficientTurbo"
        "BIOS_EnergyPerformanceBias"
        "BIOS_LogicalProc"
        "BIOS_PowerSaver"
        "BIOS_ProcHwPrefetcher"
        "BIOS_ProcPwrPerf"
        "BIOS_ProcTurboMode"
        "BIOS_ProcVirtualization"
        "BIOS_QpiSpeed"
        "BIOS_SysProfile"
        "BIOS_SystemBiosVersion"
        "FC1"
        "FC5"
        "FC7"
        "NIC1"
        "NIC2"
        "NIC3"
        "NIC4"
        "NIC5"
        "NIC6"
        "NIC7"
        "FC1_P1"
        "FC7_P1"
        "NIC1_P1"
        "NIC1_P2"
        "NIC1_P3"
        "NIC1_P4"
        "NIC2_P1"
        "NIC2_P2"
        "NIC3_P1"
        "NIC3_P2"
        "NIC4_P1"
        "NIC4_P2"
        "NIC4_P3"
        "NIC4_P4"
        "NIC5_P1"
        "NIC5_P2"
        "NIC6_P1"
        "NIC6_P2"
        "NIC6_P3"
        "NIC6_P4"
        "NIC7_P1"
        "NIC7_P2"
        "Disk0"
        "Disk1"
        "Disk2"
        "Disk3"
        "Disk4"
        "Disk5"
        "Disk6"
        "Disk7"
        "Disk8"
        "Disk9"
        "Disk10"
        "Disk11"
        "Disk12"
        "Disk13"
        "Disk14"
        "Disk15");

        table_postfix="R730";
        let index=${#RF_Key[@]}-1; # echo "[DEBUG] index:$index"; 
    ;;
    *)
        logger "Not define $1 module type!" "warn";
        return 1;
    esac

    return 0
}
