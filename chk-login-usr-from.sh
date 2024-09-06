#!/bin/sh
_exception_host="192.168.xxx.xxx|192.168.ooo.ooo";
#_chk_user="root";
_chk_date="Jan 19";
_chk_hosts="wk-srv1|wk-srv2"; # log $9

grep "$_chk_date" /var/log/secure | egrep -i sshd | grep -v COMMAND | egrep -i "Accepted password|Accepted publickey" | awk '{if($9=="root")print $4,$11}' | egrep "_chk_hosts" | sort | uniq -c; # check root login log count

exit 0;
