#!/bin/bash
#
# define var
SH_VER="Version:20221214"
PROGRAM_DIR="/var/tfx-daily"
CHK_DIR="$PROGRAM_DIR/check"
declare -ga ERR_HOSTS; # my_array+=(baz)
declare -ga ERR_COL;
# source file
if [[ -f "$PROGRAM_DIR/common.sh" ]]; then source "$PROGRAM_DIR/common.sh"; else echo "[ERROR] please check missing file: $PROGRAM_DIR/common.sh"; exit 1; fi # logger, exec_sqlcmd
# define function
function gen_chk_script { # $1 as colume name(?)
    [[ -z "$ORI_TN" ]] && { logger "update_summary var(ORI_TN) empty! Maybe check set_tablename." "ERROR"; return 4; }
    [[ -z "$TEPL_TN" ]] && { logger "update_summary var(TEPL_TN) empty! Maybe check set_tablename." "ERROR"; return 4; }
    [[ -d "$CHK_DIR" ]] || { mkdir -p "$CHK_DIR"; logger "gen_chk_script: mkdir $CHK_DIR." "debug"; }
    local script_path="$CHK_DIR/`date '+%Y%m%d'`_chk.sh";
    local sqlcmd_option="/opt/mssql-tools/bin/sqlcmd -D -S $DB_SRV -U $DB_USR -P $DB_PW -W -Q ";

    local query_col=""; # query colume
    let index=${#ERR_COL[@]}-1;
    for I in `seq 0 $index`; do 
        query_col="$query_col ${ERR_COL[$I]},"
    done
    query_col="hostname, $query_col date"
    local query_cond=""; # query condition
    let index=${#ERR_HOSTS[@]}-1;
    for I in `seq 0 $index`; do 
        let b4i=$I-1;
        if [[ "$I" -eq "0" ]]; then query_cond="hostname='${ERR_HOSTS[$I]}'"; # first item
        elif [[ "${ERR_HOSTS[$b4i]}" -eq "${ERR_HOSTS[$I]}" ]]; then continue;
        else query_cond="$query_cond OR hostname='${ERR_HOSTS[$I]}'"; fi
    done

    # init script
    [[ -f "$script_path" ]] || { echo -e "#!/bin/bash \n#\necho \"--- Date: `date '+%Y%m%d'` ---\"" > "$script_path"; }
    
    echo -e "echo \"== Check $1 from $ORI_TN and $TEPL_TN ==\"" >> "$script_path";
    echo -e "$sqlcmd_option \"SELECT $query_col FROM $ORI_TN WHERE $query_cond\";" >> "$script_path"; # select from ORI_TN
    echo -e "$sqlcmd_option \"SELECT $query_col FROM $TEPL_TN WHERE $query_cond\";" >> "$script_path"; # select from TEPL_TN
    echo -e "echo \"\"" >> "$script_path"; # new line

    # pop out array
    for I in `seq ${#ERR_HOSTS[@]} -1 0`; do [[ "$I" -eq "${#ERR_HOSTS[@]}" ]] && continue; ERR_HOSTS[$I]=""; done
    for I in `seq ${#ERR_COL[@]} -1 0`; do [[ "$I" -eq "${#ERR_COL[@]}" ]] && continue; ERR_COL[$I]=""; done
    return 0;
}
function check_summary_value { # parameter: hostname, colume name # check current and snapshot to define summary value
    [[ -z "$1" ]] && { logger "check_summary_value need 2 parameter" "ERROR"; return 1; } # $1 as hostname
    [[ -z "$2" ]] && { logger "check_summary_value need 2 parameter" "ERROR"; return 1; } # $2 as colume name
    # check TN var not empty
    [[ -z "$ORI_TN" ]] && { logger "check_summary_value var(ORI_TN) empty!" "ERROR"; return 4; }
    [[ -z "$TEPL_TN" ]] && { logger "check_summary_value var(TEPL_TN) empty!" "ERROR"; return 4; }
    [[ -z "$SUMMARY_TN" ]] && { logger "check_summary_value var(SUMMARY_TN) empty!" "ERROR"; return 4; }
    [[ -z "$HISTORY_TN" ]] && { logger "check_summary_value var(HISTORY_TN) empty!" "ERROR"; return 4; }
    local current_value=`exec_sqlcmd "SELECT $2 FROM $ORI_TN WHERE hostname='$1'"`; # get current record
    local snapshot_value=`exec_sqlcmd "SELECT $2 FROM $TEPL_TN WHERE hostname='$1'"`; # get snapshot record
    local res=""; # [[ -n "$res" ]] && res=""; 

    case "$SUMMARY_TN" in
    HW_Summary_Gen10)
        case "$2" in # colume name
        AMS)
            # check current value
            if [[ "`echo $current_value | cut -d '"' -f2`" = "Ready" ]]; then res="OK";
            elif [[ "`echo $current_value | cut -d '"' -f2`" = "Unavailable" ]]; then res="warn"; 
            else res="unknown"; fi
        ;;
        Stat|BiosHW|Mem|Network|CPU|RaidBattery|Storage|Temp)
            if [[ "$snapshot_value" = "$current_value" ]]; then [[ -n "$current_value" ]] && res="OK"; 
            elif [[ -z "$current_value" ]]; then res="unknown"; else res="ERR"; ERR_HOSTS+=("$1"); ERR_COL+=("$2"); fi
        ;;
        Fans) # Fans FanRedundancy
            current_value=`exec_sqlcmd "SELECT FanRedundancy, Fans FROM $ORI_TN WHERE hostname='$1'"`;
            snapshot_value=`exec_sqlcmd "SELECT FanRedundancy, Fans FROM $TEPL_TN WHERE hostname='$1'"`;
            
            if [[ "$snapshot_value" = "$current_value" ]]; then [[ -n "$current_value" ]] && res="OK"; 
            elif [[ -z "$current_value" ]]; then res="unknown"; else res="ERR"; ERR_HOSTS+=("$1"); ERR_COL+=("FanRedundancy" "Fans"); fi
        ;;
        Power) # Power PowerRedundancy
            current_value=`exec_sqlcmd "SELECT PowerRedundancy, Power FROM $ORI_TN WHERE hostname='$1'"`;
            snapshot_value=`exec_sqlcmd "SELECT PowerRedundancy, Power FROM $TEPL_TN WHERE hostname='$1'"`;
            
            if [[ "$snapshot_value" = "$current_value" ]]; then [[ -n "$current_value" ]] && res="OK"; 
            elif [[ -z "$current_value" ]]; then res="unknown"; else res="ERR"; ERR_HOSTS+=("$1"); ERR_COL+=("PowerRedundancy" "Power"); fi
        ;;
        date)
            [[ "`echo $current_value | tr -d '-' | cut -d ' ' -f1`" -eq "`date +%Y%m%d`" ]] && res="OK";
            [[ "`echo $current_value | tr -d '-' | cut -d ' ' -f1`" -lt "`date +%Y%m%d`" ]] && res="warn"; # : Not yet checked today!
            [[ -z "$current_value" ]] && res="unknown";
        ;;
        *)
            logger "check_summary_value: colume name:$2 wrong!" "warn";
        esac
    ;;
    HW_Summary_R740)
        case "$2" in # colume name
        Stat|Battery|CPU|CurrentRollupStatus|Fan|PowerSupply|Storage|SysMem|Temp|Volt)
            if [[ "$snapshot_value" = "$current_value" ]]; then [[ -n "$current_value" ]] && res="OK"; 
            elif [[ -z "$current_value" ]]; then res="unknown"; else res="ERR"; ERR_HOSTS+=("$1"); ERR_COL+=("$2"); fi
        ;;
        LinkStatus|NIC|BIOS) # "NIC1_P1, NIC1_P2, NIC1_P3, NIC1_P4, NIC2_P1, NIC2_P2, NIC3_P1, NIC3_P2, .. FC7_P2"
            # set column name
            case "$2" in
            NIC)
                local column_name=("NIC1" "NIC2" "NIC3" "NIC4" "NIC5" "FC1" "FC7");
            ;;
            LinkStatus)
                local column_name=("NIC1_P1" "NIC1_P2" "NIC1_P3" "NIC1_P4" "NIC2_P1" "NIC2_P2" "NIC3_P1" "NIC3_P2" "NIC4_P1" 
                "NIC4_P2" "NIC4_P3" "NIC4_P4" "NIC5_P1" "NIC5_P2" "NIC5_P3" "NIC5_P4" "FC1_P1" "FC1_P2" "FC7_P1" "FC7_P2");
            ;;
            BIOS)
                local column_name=("BIOS_BootMode" "BIOS_ControlledTurbo" "BIOS_EnergyPerformanceBias" "BIOS_LogicalProc" 
                "BIOS_ProcHwPrefetcher" "BIOS_ProcPwrPerf" "BIOS_ProcTurboMode" "BIOS_ProcVirtualization" "BIOS_SysProfile" "BIOS_SystemBiosVersion");
            ;;
            esac

            let index=${#column_name[@]}-1;
            query_cmd="SELECT";
            for I in `seq 0 $index`; do 
                if [[ "$I" -lt "$index" ]]; then query_cmd="$query_cmd ${column_name[$I]},"; 
                else query_cmd="$query_cmd ${column_name[$I]}"; fi
            done
            current_value=`exec_sqlcmd "$query_cmd FROM $ORI_TN WHERE hostname='$1'"`;
            snapshot_value=`exec_sqlcmd "$query_cmd FROM $TEPL_TN WHERE hostname='$1'"`;

            if [[ "$snapshot_value" = "$current_value" ]]; then [[ -n "$current_value" ]] && res="OK"; 
            elif [[ -z "$current_value" ]]; then res="unknown"; 
            else 
                res="ERR"; ERR_HOSTS+=("$1"); 
                local err_msg="check_summary_value: $1 $2:$res(";
                for I in `seq 0 $index`; do 
                    let N=$I+1;
                    local current_stat=`echo $current_value | cut -d ',' -f$N`;
                    local snapshot_stat=`echo $snapshot_value | cut -d ',' -f$N`;
                    # if linkstat diff, append column_name to res
                    [[ "$current_stat" = "$snapshot_stat" ]] || { err_msg="$err_msg ${column_name[$I]}"; ERR_COL+=("${column_name[$I]}"); }; 
                done
                logger "$err_msg )" "ERROR";
            fi
        ;;
        date)
            [[ "`echo $current_value | tr -d '-' | cut -d ' ' -f1`" -eq "`date +%Y%m%d`" ]] && res="OK";
            [[ "`echo $current_value | tr -d '-' | cut -d ' ' -f1`" -lt "`date +%Y%m%d`" ]] && res="warn"; # : Not yet checked today!
            [[ -z "$current_value" ]] && res="unknown";
        ;;
        *)
            logger "check_summary_value: colume name:$2 wrong!" "warn";
        esac
    ;;
    HW_Summary_SanSwitch)
        case "$2" in # colume name
        Overall|PowerSupply|Fan|Temp)
            if [[ "$snapshot_value" = "$current_value" ]]; then [[ -n "$current_value" ]] && res="OK"; 
            elif [[ -z "$current_value" ]]; then res="unknown"; else res="ERR"; ERR_HOSTS+=("$1"); ERR_COL+=("$2"); fi
        ;;
        FC_Stat) # physical-state
            local column_name=("FC0" "FC1" "FC2" "FC3" "FC4" "FC5" "FC6" "FC7" "FC8" "FC9" "FC10" "FC11" "FC12" "FC13" "FC14" "FC15" 
            "FC16" "FC17" "FC18" "FC19" "FC20" "FC21" "FC22" "FC23" "FC24" "FC25" "FC26" "FC27" "FC28" "FC29" "FC30" "FC31" 
            "FC32" "FC33" "FC34" "FC35" "FC36" "FC37" "FC38" "FC39" "FC40" "FC41" "FC42" "FC43" "FC44" "FC45" "FC46" "FC47" 
            "FC48" "FC49" "FC50" "FC51" "FC52" "FC53" "FC54" "FC55" "FC56" "FC57" "FC58" "FC59" "FC60" "FC61" "FC62" "FC63");
            let index=${#column_name[@]}-1;
            query_cmd="SELECT";
            for I in `seq 0 $index`; do 
                if [[ "$I" -lt "$index" ]]; then query_cmd="$query_cmd ${column_name[$I]},"; 
                else query_cmd="$query_cmd ${column_name[$I]}"; fi
            done
            current_value=`exec_sqlcmd "$query_cmd FROM $ORI_TN WHERE hostname='$1'"`;
            snapshot_value=`exec_sqlcmd "$query_cmd FROM $TEPL_TN WHERE hostname='$1'"`;

            if [[ "$snapshot_value" = "$current_value" ]]; then [[ -n "$current_value" ]] && res="OK"; 
            elif [[ -z "$current_value" ]]; then res="unknown"; 
            else 
                res="ERR"; ERR_HOSTS+=("$1"); 
                local err_msg="check_summary_value: $1 $2:$res(";
                for I in `seq 0 $index`; do 
                    let N=$I+1;
                    local current_stat=`echo $current_value | cut -d ',' -f$N`;
                    local snapshot_stat=`echo $snapshot_value | cut -d ',' -f$N`;
                    # if linkstat diff, append column_name to res
                    [[ "$current_stat" = "$snapshot_stat" ]] || { err_msg="$err_msg ${column_name[$I]}"; ERR_COL+=("${column_name[$I]}"); }; 
                done
                logger "$err_msg )" "ERROR";
            fi
        ;;
        date)
            [[ "`echo $current_value | tr -d '-' | cut -d ' ' -f1`" -eq "`date +%Y%m%d`" ]] && res="OK";
            [[ "`echo $current_value | tr -d '-' | cut -d ' ' -f1`" -lt "`date +%Y%m%d`" ]] && res="warn"; # : Not yet checked today!
            [[ -z "$current_value" ]] && res="unknown";
        ;;
        *)
            logger "check_summary_value: colume name:$2 wrong!" "warn";
        esac
    ;;
    HW_Summary_NetApp) 
        case "$2" in # colume name
        Chassis)
            if [[ "$snapshot_value" = "$current_value" ]]; then [[ -n "$current_value" ]] && res="OK"; 
            elif [[ -z "$current_value" ]]; then res="unknown"; else res="ERR"; ERR_HOSTS+=("$1"); ERR_COL+=("$2"); fi
        ;;
        Power|Fan|Disk|Node|Ethernet|FC|HA|ServiceIP|SAN_Path|NFS|CIFS)
            # set column name
            case "$2" in
            Power)
                local column_name=("Power0" "Power1" "Power2" "Power3");
            ;;
            Fan)
                local column_name=("Fan0" "Fan1" "Fan2" "Fan3" "Fan4" "Fan5" "Fan6" "Fan7");
            ;;
            Disk)
                local column_name=("Disk_State" "Disk_Count");
            ;;
            Node)
                local column_name=("Node0_Name" "Node0_State" "Node1_Name" "Node1_State");
            ;;
            Ethernet)
                local column_name=("Eth0" "Eth1" "Eth2" "Eth3" "Eth4" "Eth5" "Eth6" "Eth7" "Eth8" "Eth9" "Eth10" "Eth11" "Eth12" 
                "Eth13" "Eth14" "Eth15" "Eth16" "Eth17" "Eth18" "Eth19" "Eth20" "Eth21" "Eth22" "Eth23" "Eth24" "Eth25");
            ;;
            FC)
                local column_name=("FC0" "FC1" "FC2" "FC3" "FC4" "FC5" "FC6" "FC7");
            ;;
            HA)
                local column_name=("HA0_Name" "HA0_giveback" "HA0_takeover" "HA0_Port0_state" "HA0_Port1_state" 
                "HA1_Name" "HA1_giveback" "HA1_takeover" "HA1_Port0_state" "HA1_Port1_state");
            ;;
            ServiceIP)
                local column_name=("SIP0" "SIP1" "SIP2" "SIP3" "SIP4" "SIP5" "SIP6" "SIP7" "SIP8" "SIP9" "SIP10" "SIP11" "SIP12" 
                "SIP13" "SIP14" "SIP15" "SIP16" "SIP17" "SIP18" "SIP19" "SIP20" "SIP21" "SIP22" "SIP23" "SIP24" "SIP25" "SIP26" 
                "SIP27" "SIP28" "SIP29" );
            ;;
            SAN_Path)
                local column_name=("SAN_Path0" "SAN_Path1" "SAN_Path2" "SAN_Path3" "SAN_Path4" "SAN_Path5" "SAN_Path6" "SAN_Path7" 
                "SAN_Path8" "SAN_Path9" "SAN_Path10" "SAN_Path11" "SAN_Path12" "SAN_Path13" "SAN_Path14" "SAN_Path15");
            ;;
            NFS)
                local column_name=("NFS0" "NFS1" "NFS2" "NFS3" "NFS4" "NFS5" "NFS6" "NFS7" "NFS8" "NFS9");
            ;;
            CIFS)
                local column_name=("CIFS0" "CIFS1" "CIFS2" "CIFS3" "CIFS4" "CIFS5" "CIFS6" "CIFS7" "CIFS8" "CIFS9");
            ;;
            esac

            let index=${#column_name[@]}-1;
            query_cmd="SELECT";
            for I in `seq 0 $index`; do 
                if [[ "$I" -lt "$index" ]]; then query_cmd="$query_cmd ${column_name[$I]},"; 
                else query_cmd="$query_cmd ${column_name[$I]}"; fi
            done
            current_value=`exec_sqlcmd "$query_cmd FROM $ORI_TN WHERE hostname='$1'"`;
            snapshot_value=`exec_sqlcmd "$query_cmd FROM $TEPL_TN WHERE hostname='$1'"`;

            if [[ "$snapshot_value" = "$current_value" ]]; then [[ -n "$current_value" ]] && res="OK"; 
            elif [[ -z "$current_value" ]]; then res="unknown"; 
            else 
                res="ERR"; ERR_HOSTS+=("$1"); 
                local err_msg="check_summary_value: $1 $2:$res(";
                for I in `seq 0 $index`; do 
                    let N=$I+1;
                    local current_stat=`echo $current_value | cut -d ',' -f$N`;
                    local snapshot_stat=`echo $snapshot_value | cut -d ',' -f$N`;
                    # if stat diff, append column_name to res
                    [[ "$current_stat" = "$snapshot_stat" ]] || { err_msg="$err_msg ${column_name[$I]}"; ERR_COL+=("${column_name[$I]}"); };   
                done
                logger "$err_msg )" "ERROR";
            fi
        ;;
        VolumeUsage)
            local column_name=("Volume0" "Volume1" "Volume2" "Volume3" "Volume4" "Volume5" "Volume6" "Volume7" "Volume8" "Volume9" "Volume10" 
            "Volume11" "Volume12" "Volume13" "Volume14" "Volume15" "Volume16" "Volume17" "Volume18" "Volume19" "Volume20" "Volume21" "Volume22" 
            "Volume23" "Volume24" "Volume25" "Volume26" "Volume27" "Volume28" "Volume29" "Volume30" "Volume31" "Volume32" "Volume33" "Volume34" 
            "Volume35" "Volume36" "Volume37" "Volume38" "Volume39" "Volume40" "Volume41" "Volume42" "Volume43" "Volume44" "Volume45" "Volume46" 
            "Volume47" "Volume48" "Volume49");
            let index=${#column_name[@]}-1;
            query_cmd="SELECT";
            for I in `seq 0 $index`; do 
                if [[ "$I" -lt "$index" ]]; then query_cmd="$query_cmd ${column_name[$I]},"; 
                else query_cmd="$query_cmd ${column_name[$I]}"; fi
            done
            current_value=`exec_sqlcmd "$query_cmd FROM $ORI_TN WHERE hostname='$1'"`;

            local err_threshold=90; # if usage > 90 then ERR
            local warn_threshold=70; # if usage > 70 then warn
            for I in `seq 0 $index`; do 
                let N=$I+1;
                local current_stat=`echo $current_value | cut -d ',' -f$N`;
				[[ "$current_stat" = "Exception" ]] && continue; # Exception volume skip usage check

                if [[ "$current_stat" -ge "$err_threshold" ]]; then
                    res="ERR"; # whatever, set res ERR
                    logger "check_summary_value: $1 ${column_name[$I]} usage($current_stat) over $err_threshold%." "ERROR";
                elif [[ "$current_stat" -ge "$warn_threshold" ]]; then
                    [[ "$res" = "ERR" ]] || res="warn"; # if res not ERR, set res="warn"
                    logger "check_summary_value: $1 ${column_name[$I]} usage($current_stat) over $warn_threshold%." "ERROR";
                else [[ -z "$res" ]] && res="OK"; fi
            done
        ;;
        date)
            [[ "`echo $current_value | tr -d '-' | cut -d ' ' -f1`" -eq "`date +%Y%m%d`" ]] && res="OK";
            [[ "`echo $current_value | tr -d '-' | cut -d ' ' -f1`" -lt "`date +%Y%m%d`" ]] && res="warn"; # : Not yet checked today!
            [[ -z "$current_value" ]] && res="unknown";
        ;;
        *)
            logger "check_summary_value: colume name:$2 wrong!" "warn";
        esac
    ;; 
    OS_Summary_icinga) # summary tablename
        case "$2" in # colume name
        DiskUsage|MountPoint|NTP|Bonding|Routing)
            if [[ "$snapshot_value" = "$current_value" ]]; then [[ -n "$current_value" ]] && res="OK"; 
            elif [[ -z "$current_value" ]]; then res="unknown"; else res="ERR"; ERR_HOSTS+=("$1"); ERR_COL+=("$2"); fi
        ;;
        date)
            [[ "`echo $current_value | tr -d '-' | cut -d ' ' -f1`" -eq "`date +%Y%m%d`" ]] && res="OK";
            [[ "`echo $current_value | tr -d '-' | cut -d ' ' -f1`" -lt "`date +%Y%m%d`" ]] && res="warn"; # : Not yet checked today!
            [[ -z "$current_value" ]] && res="unknown";
        ;;
        *)
            logger "check_summary_value: colume name:$2 wrong!" "warn";
        esac
    ;; 
    HW_Summary_Gen9)
        case "$2" in # colume name
        Stat|Mem|CPU|Power|RaidBattery)
            if [[ "$snapshot_value" = "$current_value" ]]; then [[ -n "$current_value" ]] && res="OK"; 
            elif [[ -z "$current_value" ]]; then res="unknown"; else res="ERR"; ERR_HOSTS+=("$1"); ERR_COL+=("$2"); fi
        ;;
        Disk|NIC|BIOS) # 
            # set column name
            case "$2" in
            NIC)
                local column_name=("NIC1" "NIC2" "NIC3" "NIC4" "NIC5");
            ;;
            Disk)
                local column_name=("Disk0" "Disk1" "Disk2" "Disk3" "Disk4" "Disk5" "Disk6" "Disk7" "Disk8" "Disk9" "Disk10"
                "Disk11" "Disk12" "Disk13" "Disk14" "Disk15" "Disk16" "Disk17" "Disk18" "Disk19" "Disk20" "Disk21" "Disk22" 
                "Disk23" "Disk24" "Disk25" "Disk26" "Disk27" "Disk28" "Disk29" "Disk30" "Disk31" "Disk32" "Disk33" "Disk34" );
            ;;
            BIOS)
                local column_name=("BIOS_BootMode" "BIOS_CollabPowerControl" "BIOS_DynamicPowerCapping" "BIOS_EnergyPerfBias" 
                "BIOS_IntelQpiFreq" "BIOS_PowerProfile" "BIOS_MinProcIdlePower" "BIOS_PowerRegulator" "BIOS_ProcHyperthreading" 
                "BIOS_ProcVirtualization" "BIOS_QpiSnoopConfig" "BIOS_ThermalConfig" "BIOS_TimeFormat" "BIOS_TimeZone" "BIOS_VersionString");
            ;;
            esac

            let index=${#column_name[@]}-1;
            query_cmd="SELECT";
            for I in `seq 0 $index`; do 
                if [[ "$I" -lt "$index" ]]; then query_cmd="$query_cmd ${column_name[$I]},"; 
                else query_cmd="$query_cmd ${column_name[$I]}"; fi
            done
            current_value=`exec_sqlcmd "$query_cmd FROM $ORI_TN WHERE hostname='$1'"`;
            snapshot_value=`exec_sqlcmd "$query_cmd FROM $TEPL_TN WHERE hostname='$1'"`;

            if [[ "$snapshot_value" = "$current_value" ]]; then [[ -n "$current_value" ]] && res="OK"; 
            elif [[ -z "$current_value" ]]; then res="unknown"; 
            else 
                res="ERR"; ERR_HOSTS+=("$1"); 
                local err_msg="check_summary_value: $1 $2:$res(";
                for I in `seq 0 $index`; do 
                    let N=$I+1;
                    local current_stat=`echo $current_value | cut -d ',' -f$N`;
                    local snapshot_stat=`echo $snapshot_value | cut -d ',' -f$N`;
                    # if linkstat diff, append column_name to res
                    [[ "$current_stat" = "$snapshot_stat" ]] || { err_msg="$err_msg ${column_name[$I]}"; ERR_COL+=("${column_name[$I]}"); }; 
                done
                logger "$err_msg )" "ERROR";
            fi
        ;;
        date)
            [[ "`echo $current_value | tr -d '-' | cut -d ' ' -f1`" -eq "`date +%Y%m%d`" ]] && res="OK";
            [[ "`echo $current_value | tr -d '-' | cut -d ' ' -f1`" -lt "`date +%Y%m%d`" ]] && res="warn"; # : Not yet checked today!
            [[ -z "$current_value" ]] && res="unknown";
        ;;
        *)
            logger "check_summary_value: colume name:$2 wrong!" "warn";
        esac
    ;;
    HW_Summary_R730)
        case "$2" in # colume name
        Stat|Mem|CPU|Power)
            if [[ "$snapshot_value" = "$current_value" ]]; then [[ -n "$current_value" ]] && res="OK"; 
            elif [[ -z "$current_value" ]]; then res="unknown"; else res="ERR"; ERR_HOSTS+=("$1"); ERR_COL+=("$2"); fi
        ;;
        BIOS|NIC|Disk|LinkStat) 
            # set column name
            case "$2" in
            NIC)
                local column_name=("FC1" "FC5" "FC7" "NIC1" "NIC2" "NIC3" "NIC4" "NIC5" "NIC6" "NIC7");
            ;;
            LinkStat)
                local column_name=("FC1_P1" "FC7_P1" "NIC1_P1" "NIC1_P2" "NIC1_P3" "NIC1_P4" "NIC2_P1" "NIC2_P2" "NIC3_P1" "NIC3_P2" 
                "NIC4_P1" "NIC4_P2" "NIC4_P3" "NIC4_P4" "NIC5_P1" "NIC5_P2" "NIC6_P1" "NIC6_P2" "NIC6_P3" "NIC6_P4" "NIC7_P1" "NIC7_P2");
            ;;
            Disk)
                local column_name=("Disk0" "Disk1" "Disk2" "Disk3" "Disk4" "Disk5" "Disk6" "Disk7" "Disk8" "Disk9" "Disk10"
                "Disk11" "Disk12" "Disk13" "Disk14" "Disk15");
            ;;
            BIOS)
                local column_name=("BIOS_BootMode" "BIOS_ControlledTurbo" "BIOS_EnergyEfficientTurbo" "BIOS_EnergyPerformanceBias" "BIOS_LogicalProc" 
                "BIOS_PowerSaver" "BIOS_ProcHwPrefetcher" "BIOS_ProcPwrPerf" "BIOS_ProcTurboMode" "BIOS_ProcVirtualization" "BIOS_QpiSpeed" "BIOS_SysProfile" 
                "BIOS_SystemBiosVersion");
            ;;
            esac

            let index=${#column_name[@]}-1;
            query_cmd="SELECT";
            for I in `seq 0 $index`; do 
                if [[ "$I" -lt "$index" ]]; then query_cmd="$query_cmd ${column_name[$I]},"; 
                else query_cmd="$query_cmd ${column_name[$I]}"; fi
            done
            current_value=`exec_sqlcmd "$query_cmd FROM $ORI_TN WHERE hostname='$1'"`;
            snapshot_value=`exec_sqlcmd "$query_cmd FROM $TEPL_TN WHERE hostname='$1'"`;

            if [[ "$snapshot_value" = "$current_value" ]]; then [[ -n "$current_value" ]] && res="OK"; 
            elif [[ -z "$current_value" ]]; then res="unknown"; 
            else 
                res="ERR"; ERR_HOSTS+=("$1"); 
                local err_msg="check_summary_value: $1 $2:$res(";
                for I in `seq 0 $index`; do 
                    let N=$I+1;
                    local current_stat=`echo $current_value | cut -d ',' -f$N`;
                    local snapshot_stat=`echo $snapshot_value | cut -d ',' -f$N`;
                    # if linkstat diff, append column_name to res
                    [[ "$current_stat" = "$snapshot_stat" ]] || { err_msg="$err_msg ${column_name[$I]}"; ERR_COL+=("${column_name[$I]}"); }; 
                done
                logger "$err_msg )" "ERROR";
            fi
        ;;
        date)
            [[ "`echo $current_value | tr -d '-' | cut -d ' ' -f1`" -eq "`date +%Y%m%d`" ]] && res="OK";
            [[ "`echo $current_value | tr -d '-' | cut -d ' ' -f1`" -lt "`date +%Y%m%d`" ]] && res="warn"; # : Not yet checked today!
            [[ -z "$current_value" ]] && res="unknown";
        ;;
        *)
            logger "check_summary_value: colume name:$2 wrong!" "warn";
        esac
    ;;
    # template-case) # summary tablename
    #     case "$2" in # colume name
    #     date)
    #         [[ "`echo $current_value | tr -d '-' | cut -d ' ' -f1`" -eq "`date +%Y%m%d`" ]] && res="OK";
    #         [[ "`echo $current_value | tr -d '-' | cut -d ' ' -f1`" -lt "`date +%Y%m%d`" ]] && res="warn"; # : Not yet checked today!
    #         [[ -z "$current_value" ]] && res="unknown";
    #     ;;
    #     *)
    #         logger "check_summary_value: colume name:$2 wrong!" "warn";
    #     esac
    # ;; 
    *)
        logger "check_summary_value: Not define SUMMARY_TN($SUMMARY_TN)!" "warn";
        return 4;
    esac

    [[ "${#ERR_HOSTS[@]}" -gt "0" ]] && { 
        gen_chk_script "$2"; # 
        [[ -n "$DEBUG" ]] && { logger "check_summary_value: ERR_HOSTS NUM:${#ERR_HOSTS[@]} ($1, $2)" "debug"; };
    }
    [[ -z "$res" ]] && { 
        res="unknown"; 
        [[ -n "$DEBUG" ]] && { logger "check_summary_value: Host($1) Colume($2:$current_value) unknown." "debug"; };
    }
    echo "$res";
}
function update_summary { # parameter: TEPL tablename # update summary table
    [[ -z "$1" ]] && { logger "update_summary need 2 parameter" "ERROR"; return 1; } # $1 as TEPL tablename
    # set tablename var
    set_tablename "$1"; # get var ORI_TN, TEPL_TN, SUMMARY_TN, HISTORY_TN
    [[ -z "$ORI_TN" ]] && { logger "update_summary var(ORI_TN) empty! Maybe check set_tablename." "ERROR"; return 4; }
    [[ -z "$TEPL_TN" ]] && { logger "update_summary var(TEPL_TN) empty! Maybe check set_tablename." "ERROR"; return 4; }
    [[ -z "$SUMMARY_TN" ]] && { logger "update_summary var(SUMMARY_TN) empty! Maybe check set_tablename." "ERROR"; return 4; }
    [[ -z "$HISTORY_TN" ]] && { logger "update_summary var(HISTORY_TN) empty! Maybe check set_tablename." "ERROR"; return 4; }
    
    # check table exist # ORI_TN usually check exist in get script
    is_table_exist=`exec_sqlcmd "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME='$TEPL_TN'"`;
    [[ -z "$is_table_exist" ]] && { logger "check_hw table:$TEPL_TN not exist!" "ERROR"; return 4; };
    is_table_exist=`exec_sqlcmd "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME='$SUMMARY_TN'"`;
    [[ -z "$is_table_exist" ]] && { logger "check_hw table:$SUMMARY_TN not exist!" "ERROR"; return 4; };
    is_table_exist=`exec_sqlcmd "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME='$HISTORY_TN'"`;
    [[ -z "$is_table_exist" ]] && { logger "check_hw table:$HISTORY_TN not exist!" "ERROR"; return 4; };

    # list all host from TEPL table
    HOSTS=`exec_sqlcmd "SELECT hostname FROM $TEPL_TN"`;
    [[ -z "$HOSTS" ]] && { logger "update_summary: TEPL($TEPL_TN) empty, not update Summary table($SUMMARY_TN)."; return 0; }

    # truncate summary table
    exec_sqlcmd "TRUNCATE TABLE $SUMMARY_TN";

    for H in $HOSTS; do
    # check all summary colume
        query_cmd="INSERT $SUMMARY_TN ( ";
        for COL in `exec_sqlcmd "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME='$SUMMARY_TN'"`; do
            [[ "$COL" = "hostname" ]] && continue; 
            [[ "$COL" = "timestamp" ]] && continue;
            query_cmd="$query_cmd $COL,";
        done
        query_cmd="$query_cmd hostname ) VALUES ( ";
        for COL in `exec_sqlcmd "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME='$SUMMARY_TN'"`; do
            [[ "$COL" = "hostname" ]] && continue; 
            [[ "$COL" = "timestamp" ]] && continue;
    # summary value define by: check_summary_value ( hostname, colume name )
            local summary_value=`check_summary_value "$H" "$COL"`; 
            query_cmd="$query_cmd '$summary_value',";

            [[ -n "$DEBUG" ]] && { logger "update_summary: host($H), $COL:$summary_value" "debug"; }
        done
        query_cmd="$query_cmd '$H' )";

    # insert to summary table
        [[ -n "$DEBUG" ]] && { logger "update_summary: insert query_cmd:$query_cmd" "debug"; }
        exec_sqlcmd "$query_cmd";
        logger "update_summary: insert $H into ($SUMMARY_TN)"
    done

    # insert into history table
    query_cmd="INSERT INTO $HISTORY_TN SELECT";
    for COL in `exec_sqlcmd "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME='$SUMMARY_TN'"`; do
        [[ "$COL" = "timestamp" ]] && continue;
        query_cmd="$query_cmd $COL,";
    done
    exec_sqlcmd "$query_cmd getdate() FROM $SUMMARY_TN;"; #
    logger "update_summary: insert into ($HISTORY_TN)"
}
# check var # error msg
rpm -q mssql-tools &> /dev/null; [[ $? -eq 1 ]] && { echo "[Error] Cannot find mssql-tools rpm."; exit 2; };
[[ -z "`rpm -qa | grep msodbcsql`" ]] && { echo "[Error] Cannot find msodbcsql rpm."; exit 2; };
[[ -f "/opt/mssql-tools/bin/sqlcmd" ]] || { echo "[Error] Cannot find sqlcmd command."; exit 2; };
[[ -z "$DB_SRV" ]] && { echo "[Error] DB Server can't empty!"; exit 1; } # syntax error (?)
[[ -z "$DB_USR" ]] && { echo "[Error] DB Username can't empty!"; exit 1; }
[[ -z "$DB_PW" ]] && { echo "[Error] DB Password can't empty!"; exit 1; }
# main
grep -iE "iLO|iDrac|iRMC|IMM" /etc/hosts | grep -E '^[0-9]{1,3}\.[0-9]{1,3}\."125||195"\.[0-9]{1,3}' | awk '{print $2}' | xargs -d '\n' -n1 -P4 -I {} "$PROGRAM_DIR/get-hw.sh" {} ; 
"$PROGRAM_DIR/get-hw-san.sh";
"$PROGRAM_DIR/get-hw-netapp.sh";
"$PROGRAM_DIR/get-os.sh";
# grep -iE "iLO|iDrac|iRMC|IMM" /etc/hosts | grep -E '^[0-9]{1,3}\.[0-9]{1,3}\."125||195"\.[0-9]{1,3}' | awk '{print $2}' | xargs -d '\n' -n1 -P4 -I {} "/var/tfx-daily/get-ipmi-protocol.sh" {} ; # ipmi
# grep -iE "iLO|iDrac|iRMC|IMM" /etc/hosts | grep -E '^[0-9]{1,3}\.[0-9]{1,3}\."125||195"\.[0-9]{1,3}' | awk '{print $2}' | xargs -d '\n' -n1 -P4 -I {} "/var/tfx-daily/get-ssd-percent.sh" {} ; # chkssd

# update summary table
for TABLE in `exec_sqlcmd "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME LIKE 'TEPL_%'"`; do
    update_summary "$TABLE"; 
done

# clear chk script 
ls -alt --time-style=+%Y%m%d "$CHK_DIR/"* 2> /dev/null | awk '{if(NR>10) print $7}' | xargs rm -f ; # keep 10

exit 0;
