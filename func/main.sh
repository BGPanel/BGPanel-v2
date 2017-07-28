#!/usr/bin/env bash
# Internal variables
BIN=$BGPANEL/bin/env
USER_DATA=$BGPANEL/data/users/$user

# Return codes
OK=0
E_ARGS=1
E_INVALID=2
E_NOTEXIST=3
E_EXISTS=4
E_SUSPENDED=5
E_UNSUSPENDED=6
E_INUSE=7
E_LIMIT=8
E_PASSWORD=9
E_FORBIDEN=10
E_DISABLED=11
E_PARSING=12
E_DISK=13
E_LA=14
E_CONNECT=15
E_FTP=16
E_DB=17
E_RRD=18
E_UPDATE=19
E_RESTART=20

# Event string for logger
for ((I=1; I <= $# ; I++)); do
    if [[ "$HIDE" != $I ]]; then
        ARGUMENTS="$ARGUMENTS '$(eval echo \$${I})'"
    else
        ARGUMENTS="$ARGUMENTS '******'"
    fi
done

# Log event function
log_event() {
    if [ -z "$time" ]; then
        LOG_TIME="$(date +'%F %T') $(basename $0)"
    else
        LOG_TIME="$date $time $(basename $0)"
    fi
    if [ "$1" -eq 0 ]; then
        echo "$LOG_TIME $2" >> $BGPANEL/log/system.log
    else
        echo "$LOG_TIME $2 [Error $1]" >> $BGPANEL/log/error.log
    fi
}

# Log user history
log_history() {
    cmd=$1
    undo=${2-no}
    log_user=${3-$user}
    log=$BGPANEL/data/users/$log_user/history.log
    touch $log
    if [ '99' -lt "$(wc -l $log |cut -f 1 -d ' ')" ]; then
        tail -n 49 $log > $log.moved
        mv -f $log.moved $log
        chmod 660 $log
    fi
    if [ -z "$date" ]; then
        time_n_date=$(date +'%T %F')
        time=$(echo "$time_n_date" |cut -f 1 -d \ )
        date=$(echo "$time_n_date" |cut -f 2 -d \ )
    fi
    curr_str=$(grep "ID=" $log | cut -f 2 -d \' | sort -n | tail -n1)
    id="$((curr_str +1))"
    echo "ID='$id' DATE='$date' TIME='$time' CMD='$cmd' UNDO='$undo'" >> $log
}

# Result checker
check_result() {
    if [ $1 -ne 0 ]; then
        echo "Error: $2"
        if [ ! -z "$3" ]; then
            log_event "$3" "$ARGUMENTS"
            exit $3
        else
            log_event "$1" "$ARGUMENTS"
            exit $1
        fi
    fi
}

# Argument list checker
check_args() {
    if [ "$1" -gt "$2" ]; then
        echo "Usage: $(basename $0) $3"
        check_result $E_ARGS "not enought arguments" >/dev/null
    fi
}

# Subsystem checker
is_system_enabled() {
    if [ -z "$1" ] || [ "$1" = no ]; then
        check_result $E_DISABLED "$2 is not enabled"
    fi
}

# Random password generator
generate_password() {
    matrix=$1
    lenght=$2
    if [ -z "$matrix" ]; then
        matrix=0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz
    fi
    if [ -z "$lenght" ]; then
        lenght=10
    fi
    i=1
    while [ $i -le $lenght ]; do
        pass="$pass${matrix:$(($RANDOM%${#matrix})):1}"
       ((i++))
    done
    echo "$pass"
}

# Check if object is new
is_object_new() {
    if [ $2 = 'USER' ]; then
        if [ -d "$USER_DATA" ]; then
            object="OK"
        fi
    else
        object=$(grep "$2='$3'" $USER_DATA/$1.conf)
    fi
    if [ ! -z "$object" ]; then
        check_result $E_EXISTS "$2=$3 is already exists"
    fi
}

# Check if object is valid
is_object_valid() {
    if [ $2 = 'USER' ]; then
        if [ ! -d "$BGPANEL/data/users/$3" ]; then
            check_result $E_NOTEXIST "$1 $3 doesn't exist"
        fi
    else
        object=$(grep "$2='$3'" $BGPANEL/data/users/$user/$1.conf)
        if [ -z "$object" ]; then
            arg1=$(basename $1)
            arg2=$(echo $2 |tr '[:upper:]' '[:lower:]')
            check_result $E_NOTEXIST "$arg1 $arg2 $3 doesn't exist"
        fi
    fi
}

# Check if object is supended
is_object_suspended() {
    if [ $2 = 'USER' ]; then
        spnd=$(cat $USER_DATA/$1.conf|grep "SUSPENDED='yes'")
    else
        spnd=$(grep "$2='$3'" $USER_DATA/$1.conf|grep "SUSPENDED='yes'")
    fi
    if [ -z "$spnd" ]; then
        check_result $E_UNSUSPENDED "$(basename $1) $3 is not suspended"
    fi
}

# Check if object is unsupended
is_object_unsuspended() {
    if [ $2 = 'USER' ]; then
        spnd=$(cat $USER_DATA/$1.conf |grep "SUSPENDED='yes'")
    else
        spnd=$(grep "$2='$3'" $USER_DATA/$1.conf |grep "SUSPENDED='yes'")
    fi
    if [ ! -z "$spnd" ]; then
        check_result $E_SUSPENDED "$(basename $1) $3 is suspended"
    fi
}

# Check if object value is empty
is_object_value_empty() {
    str=$(grep "$2='$3'" $USER_DATA/$1.conf)
    eval $str
    eval value=$4
    if [ ! -z "$value" ] && [ "$value" != 'no' ]; then
        check_result $E_EXISTS "${4//$}=$value is already exists"
    fi
}

# Check if object value is empty
is_object_value_exist() {
    str=$(grep "$2='$3'" $USER_DATA/$1.conf)
    eval $str
    eval value=$4
    if [ -z "$value" ] || [ "$value" = 'no' ]; then
        check_result $E_NOTEXIST "${4//$}=$value doesn't exist"
    fi
}

# Get next cron job id
get_next_cronjob() {
    if [ -z "$job" ]; then
        curr_str=$(grep "JOB=" $USER_DATA/cron.conf|cut -f 2 -d \'|\
                 sort -n|tail -n1)
        job="$((curr_str +1))"
    fi
}

# Sort cron jobs by id
sort_cron_jobs() {
    cat $USER_DATA/cron.conf |sort -n -k 2 -t \' > $USER_DATA/cron.tmp
    mv -f $USER_DATA/cron.tmp $USER_DATA/cron.conf
}

# Sync cronjobs with system cron
sync_cron_jobs() {
    source $USER_DATA/user.conf
    if [ -e "/var/spool/cron/crontabs" ]; then
        crontab="/var/spool/cron/crontabs/$user"
    else
        crontab="/var/spool/cron/$user"
    fi
    rm -f $crontab
    if [ "$CRON_REPORTS" = 'yes' ]; then
        echo "MAILTO=$CONTACT" > $crontab
        echo 'CONTENT_TYPE="text/plain; charset=utf-8"' >> $crontab
    fi
    while read line; do
        eval $line
        if [ "$SUSPENDED" = 'no' ]; then
            echo "$MIN $HOUR $DAY $MONTH $WDAY $CMD" |\
                sed -e "s/%quote%/'/g" -e "s/%dots%/:/g" \
                >> $crontab
        fi
    done < $USER_DATA/cron.conf
    chown $user:$user $crontab
    chmod 600 $crontab
}


# Check if password is transmitted via file
is_password_valid() {
    if [[ "$password" =~ ^/tmp/ ]]; then
        if [ -f "$password" ]; then
            password=$(head -n1 $password)
        fi
    fi
}

# Get object value
get_object_value() {
    object=$(grep "$2='$3'" $USER_DATA/$1.conf)
    eval "$object"
    eval echo $4
}

# Update object value
update_object_value() {
    row=$(grep -nF "$2='$3'" $USER_DATA/$1.conf)
    lnr=$(echo $row | cut -f 1 -d ':')
    object=$(echo $row | sed "s/^$lnr://")
    eval "$object"
    eval old="$4"
    old=$(echo "$old" | sed -e 's/\\/\\\\/g' -e 's/&/\\&/g' -e 's/\//\\\//g')
    new=$(echo "$5" | sed -e 's/\\/\\\\/g' -e 's/&/\\&/g' -e 's/\//\\\//g')
    sed -i "$lnr s/${4//$/}='${old//\*/\\*}'/${4//$/}='${new//\*/\\*}'/g" \
        $USER_DATA/$1.conf
}

# Add object key
add_object_key() {
    row=$(grep -n "$2='$3'" $USER_DATA/$1.conf)
    lnr=$(echo $row | cut -f 1 -d ':')
    object=$(echo $row | sed "s/^$lnr://")
    if [ -z "$(echo $object |grep $4=)" ]; then
        eval old="$4"
        sed -i "$lnr s/$5='/$4='' $5='/" $USER_DATA/$1.conf
    fi
}

# Search objects
search_objects() {
    OLD_IFS="$IFS"
    IFS=$'\n'
    for line in $(grep $2=\'$3\' $USER_DATA/$1.conf); do
        eval $line
        eval echo \$$4
    done
    IFS="$OLD_IFS"
}

# Get user value
get_user_value() {
    grep "^${1//$/}=" $USER_DATA/user.conf |awk -F "'" '{print $2}'
}

# Update user value in user.conf
update_user_value() {
    key="${2//$}"
    lnr=$(grep -n "^$key='" $VESTA/data/users/$1/user.conf |cut -f 1 -d ':')
    if [ ! -z "$lnr" ]; then
        sed -i "$lnr d" $VESTA/data/users/$1/user.conf
        sed -i "$lnr i\\$key='${3}'" $VESTA/data/users/$1/user.conf
    fi
}

# Increase user counter
increase_user_value() {
    key="${2//$}"
    factor="${3-1}"
    conf="$VESTA/data/users/$1/user.conf"
    old=$(grep "$key=" $conf | cut -f 2 -d \')
    if [ -z "$old" ]; then
        old=0
    fi
    new=$((old + factor))
    sed -i "s/$key='$old'/$key='$new'/g" $conf
}

# Decrease user counter
decrease_user_value() {
    key="${2//$}"
    factor="${3-1}"
    conf="$VESTA/data/users/$1/user.conf"
    old=$(grep "$key=" $conf | cut -f 2 -d \')
    if [ -z "$old" ]; then
        old=0
    fi
    if [ "$old" -le 1 ]; then
        new=0
    else
        new=$((old - factor))
    fi
    if [ "$new" -lt 0 ]; then
        new=0
    fi
    sed -i "s/$key='$old'/$key='$new'/g" $conf
}


# User format validator
is_user_format_valid() {
    if [ ${#1} -eq 1 ]; then
        if ! [[ "$1" =~ ^^[[:alnum:]]$ ]]; then
            check_result $E_INVALID "invalid $2 format :: $1"
        fi
    else
        if ! [[ "$1" =~ ^[[:alnum:]][-|\.|_[:alnum:]]{0,28}[[:alnum:]]$ ]]
            then
            check_result $E_INVALID "invalid $2 format :: $1"
        fi
    fi
}

# Domain format validator
is_domain_format_valid() {
    object_name=${2-domain}
    exclude="[!|@|#|$|^|&|*|(|)|+|=|{|}|:|,|<|>|?|_|/|\|\"|'|;|%|\`| ]"
    if [[ $1 =~ $exclude ]] || [[ $1 =~ ^[0-9]+$ ]] || [[ $1 =~ "\.\." ]]; then
        check_result $E_INVALID "invalid $object_name format :: $1"
    fi
}

# Alias forman validator
is_alias_format_valid() {
    for object in ${1//,/ }; do
        exclude="[!|@|#|$|^|&|(|)|+|=|{|}|:|<|>|?|_|/|\|\"|'|;|%|\`| ]"
        if [[ "$object" =~ $exclude ]]; then
            check_result $E_INVALID "invalid alias format :: $object"
        fi
        if [[ "$object" =~ [*] ]] && ! [[ "$object" =~ ^[*]\..* ]]; then
            check_result $E_INVALID "invalid alias format :: $object"
        fi
    done
}

# IP format validator
is_ip_format_valid() {
    object_name=${2-ip}
    ip_regex='([1-9]?[0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])'
    ip_clean=$(echo "${1%/*}")
    if ! [[ $ip_clean =~ ^$ip_regex\.$ip_regex\.$ip_regex\.$ip_regex$ ]]; then
        check_result $E_INVALID "invalid $object_name format :: $1"
    fi
    if [ $1 != "$ip_clean" ]; then
        ip_cidr="$ip_clean/"
        ip_cidr=$(echo "${1#$ip_cidr}")
        if [[ "$ip_cidr" -gt 32 ]] || [[ "$ip_cidr" =~ [:alnum:] ]]; then
            check_result $E_INVALID "invalid $object_name format :: $1"
        fi
    fi
}

# Proxy extention format validator
is_extention_format_valid() {
    exclude="[!|#|$|^|&|(|)|+|=|{|}|:|@|<|>|?|/|\|\"|'|;|%|\`| ]"
    if [[ "$1" =~ $exclude ]]; then
        check_result $E_INVALID "invalid proxy extention format :: $1"
    fi
}

# Number format validator
is_number_format_valid() {
    object_name=${2-number}
    if ! [[ "$1" =~ ^[0-9]+$ ]] ; then
        check_result $E_INVALID "invalid $object_name format :: $1"
    fi
}

# Autoreply format validator
is_autoreply_format_valid() {
    if [[ "$1" =~ [$|\`] ]] || [ 10240 -le ${#1} ]; then
        check_result $E_INVALID "invalid autoreply format :: $1"
    fi
}

# Boolean format validator
is_boolean_format_valid() {
    if [ "$1" != 'yes' ] && [ "$1" != 'no' ]; then
        check_result $E_INVALID "invalid $2 format :: $1"
    fi
}

# Common format validator
is_common_format_valid() {
    exclude="[!|#|$|^|&|(|)|+|=|{|}|:|<|>|?|/|\|\"|'|;|%|\`| ]"
    if [[ "$1" =~ $exclude ]]; then
        check_result $E_INVALID "invalid $2 format :: $1"
    fi
    if [ 400 -le ${#1} ]; then
        check_result $E_INVALID "invalid $2 format :: $1"
    fi
    if [[ "$1" =~ @ ]] && [ ${#1} -gt 1 ] ; then
        check_result $E_INVALID "invalid $2 format :: $1"
    fi
    if [[ $1 =~ \* ]]; then
        if [ "$(echo $1 | grep -o '*'|wc -l)" -gt 1 ]; then
            check_result $E_INVALID "invalid $2 format :: $1"
        fi
    fi
}

# Database format validator
is_database_format_valid() {
    exclude="[!|@|#|$|^|&|*|(|)|+|=|{|}|:|,|<|>|?|/|\|\"|'|;|%|\`| ]"
    if [[ "$1" =~ $exclude ]] || [ 65 -le ${#1} ]; then
        check_result $E_INVALID "invalid $2 format :: $1"
    fi
}

# Date format validator
is_date_format_valid() {
    if ! [[ "$1" =~ ^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$ ]]; then
        check_result $E_INVALID "invalid date format :: $1"
    fi
}

# Database user validator
is_dbuser_format_valid() {
    exclude="[!|@|#|$|^|&|*|(|)|+|=|{|}|:|,|<|>|?|/|\|\"|'|;|%|\`| ]"
    if [ 17 -le ${#1} ]; then
		check_result $E_INVALID "mysql username can be up to 16 characters long"
	fi
    if [[ "$1" =~ $exclude ]]; then
        check_result $E_INVALID "invalid $2 format :: $1"
    fi
}

# DNS record type validator
is_dns_type_format_valid() {
    known_dnstype='A,AAAA,NS,CNAME,MX,TXT,SRV,DNSKEY,KEY,IPSECKEY,PTR,SPF,TLSA'
    if [ -z "$(echo $known_dnstype |grep -w $1)" ]; then
        check_result $E_INVALID "invalid dns record type format :: $1"
    fi
}

# DNS record validator
is_dns_record_format_valid() {
    if [ "$rtype" = 'A' ]; then
        is_ip_format_valid "$1"
    fi
    if [ "$rtype" = 'NS' ]; then
        is_domain_format_valid "${1::-1}" 'ns_record'
    fi
    if [ "$rtype" = 'MX' ]; then
        is_domain_format_valid "${1::-1}" 'mx_record'
        is_int_format_valid "$priority" 'priority_record'
    fi

}

# Email format validator
is_email_format_valid() {
    if [[ ! "$1" =~ ^[A-Za-z0-9._%+-]+@[[:alnum:].-]+\.[A-Za-z]{2,63}$ ]] ; then
        check_result $E_INVALID "invalid email format :: $1"
    fi
}

# Firewall action validator
is_fw_action_format_valid() {
    if [ "$1" != "ACCEPT" ] && [ "$1" != 'DROP' ] ; then
        check_result $E_INVALID "invalid action format :: $1"
    fi
}

# Firewall protocol validator
is_fw_protocol_format_valid() {
    if [ "$1" != "ICMP" ] && [ "$1" != 'UDP' ] && [ "$1" != 'TCP' ] ; then
        check_result $E_INVALID "invalid protocol format :: $1"
    fi
}

# Firewall port validator
is_fw_port_format_valid() {
    if [ "${#1}" -eq 1 ]; then
        if ! [[ "$1" =~ [0-9] ]]; then
            check_result $E_INVALID "invalid port format :: $1"
        fi
    else
        if ! [[ "$1" =~ ^[0-9][-|,|:|0-9]{0,30}[0-9]$ ]]
        then
            check_result $E_INVALID "invalid port format :: $1"
        fi
    fi
}

# Integer validator
is_int_format_valid() {
    if ! [[ "$1" =~ ^[0-9]+$ ]] ; then 
        check_result $E_INVALID "invalid $2 format :: $1"
    fi
}

# Interface validator
is_interface_format_valid() {
    netdevices=$(cat /proc/net/dev |grep : |cut -f 1 -d : |tr -d ' ')
    if [ -z $(echo "$netdevices" |grep -x $1) ]; then
        check_result $E_INVALID "invalid interface format :: $1"
    fi
}

# IP status validator
is_ip_status_format_valid() {
    if [ -z "$(echo shared,dedicated | grep -w $1 )" ]; then
        check_result $E_INVALID "invalid status format :: $1"
    fi
}

# Cron validator
is_cron_format_valid() {
    limit=60
    check_format=''
    if [ "$2" = 'day' ]; then
        limit=31
    fi
    if [ "$2" = 'month' ]; then
        limit=12
    fi
    if [ "$2" = 'wday' ]; then
        limit=7
    fi
    if [ "$1" = '*' ]; then
        check_format='ok'
    fi
    if [[ "$1" =~ ^[\*]+[/]+[0-9] ]]; then
        if [ "$(echo $1 |cut -f 2 -d /)" -lt $limit ]; then
            check_format='ok'
        fi
    fi
    if [[ "$1" =~ ^[0-9][-|,|0-9]{0,70}[\/][0-9]$ ]]; then
        check_format='ok'
        crn_values=${1//,/ }
        crn_values=${crn_values//-/ }
        crn_values=${crn_values//\// }
        for crn_vl in $crn_values; do
            if [ "$crn_vl" -gt $limit ]; then
                check_format='invalid'
            fi
        done
    fi
    if [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -le $limit ]; then
        check_format='ok'
    fi
    if [ "$check_format" != 'ok' ]; then
        check_result $E_INVALID "invalid $2 format :: $1"
    fi
}

# Name validator
is_name_format_valid() {
    if ! [[ "$1" =~ ^[[:alnum:]][-|\ |\.|_[:alnum:]]{0,28}[[:alnum:]]$ ]]; then
        check_result $E_INVALID "invalid $2 format :: $1"
    fi
}

# Object validator
is_object_format_valid() {
    if ! [[ "$1" =~ ^[[:alnum:]][-|\.|_[:alnum:]]{0,28}[[:alnum:]]$ ]]; then
        check_result $E_INVALID "invalid $2 format :: $1"
    fi
}

# Password validator
is_password_format_valid() {
    if [ "${#1}" -lt '6' ]; then
        check_result $E_INVALID "invalid password format :: $1"
    fi
}

# Format validation controller
is_format_valid() {
    for arg_name in $*; do
        eval arg=\$$arg_name
        if [ !  -z "$arg" ]; then
            case $arg_name in
                account)        is_user_format_valid "$arg" "$arg_name";;
                action)         is_fw_action_format_valid "$arg";;
                aliases)        is_alias_format_valid "$arg" ;;
                antispam)       is_boolean_format_valid "$arg" 'antispam' ;;
                antivirus)      is_boolean_format_valid "$arg" 'antivirus' ;;
                autoreply)      is_autoreply_format_valid "$arg" ;;
                backup)         is_user_format_valid "$arg" 'backup' ;;
                charset)        is_object_format_valid "$arg" "$arg_name" ;;
                charsets)       is_common_format_valid "$arg" 'charsets' ;;
                comment)        is_object_format_valid "$arg" 'comment' ;;
                database)       is_database_format_valid "$arg" 'database';;
                day)            is_cron_format_valid "$arg" $arg_name ;;
                dbpass)         is_password_format_valid "$arg" ;;
                dbuser)         is_dbuser_format_valid "$arg" 'dbuser';;
                dkim)           is_boolean_format_valid "$arg" 'dkim' ;;
                dkim_size)      is_int_format_valid "$arg" ;;
                domain)         is_domain_format_valid "$arg" ;;
                dvalue)         is_dns_record_format_valid "$arg";;
                email)          is_email_format_valid "$arg" ;;
                exp)            is_date_format_valid "$arg" ;;
                extentions)     is_common_format_valid "$arg" 'extentions' ;;
                fname)          is_name_format_valid "$arg" "first name" ;;
                ftp_password)   is_password_format_valid "$arg" ;;
                ftp_user)       is_user_format_valid "$arg" "$arg_name" ;;
                host)           is_object_format_valid "$arg" "$arg_name" ;;
                hour)           is_cron_format_valid "$arg" $arg_name ;;
                id)             is_int_format_valid "$arg" 'id' ;;
                ip)             is_ip_format_valid "$arg" ;;
                ip_name)        is_domain_format_valid "$arg" 'IP name';;
                ip_status)      is_ip_status_format_valid "$arg" ;;
                job)            is_int_format_valid "$arg" 'job' ;;
                key)            is_user_format_valid "$arg" "$arg_name" ;;
                lname)          is_name_format_valid "$arg" "last name" ;;
                malias)         is_user_format_valid "$arg" "$arg_name" ;;
                max_db)         is_int_format_valid "$arg" 'max db';;
                min)            is_cron_format_valid "$arg" $arg_name ;;
                month)          is_cron_format_valid "$arg" $arg_name ;;
                nat_ip)         is_ip_format_valid "$arg" ;;
                netmask)        is_ip_format_valid "$arg" 'netmask' ;;
                newid)          is_int_format_valid "$arg" 'id' ;;
                ns1)            is_domain_format_valid "$arg" 'ns1' ;;
                ns2)            is_domain_format_valid "$arg" 'ns2' ;;
                ns3)            is_domain_format_valid "$arg" 'ns3' ;;
                ns4)            is_domain_format_valid "$arg" 'ns4' ;;
                ns5)            is_domain_format_valid "$arg" 'ns5' ;;
                ns6)            is_domain_format_valid "$arg" 'ns6' ;;
                ns7)            is_domain_format_valid "$arg" 'ns7' ;;
                ns8)            is_domain_format_valid "$arg" 'ns8' ;;
                object)         is_name_format_valid "$arg" 'object';;
                package)        is_object_format_valid "$arg" "$arg_name" ;;
                password)       is_password_format_valid "$arg" ;;
                port)           is_int_format_valid "$arg" 'port' ;;
                port_ext)       is_fw_port_format_valid "$arg";;
                protocol)       is_fw_protocol_format_valid "$arg" ;;
                proxy_ext)      is_extention_format_valid "$arg" ;;
                quota)          is_int_format_valid "$arg" 'quota' ;;
                record)         is_common_format_valid "$arg" 'record';;
                restart)        is_boolean_format_valid "$arg" 'restart' ;;
                rtype)          is_dns_type_format_valid "$arg" ;;
                rule)           is_int_format_valid "$arg" "rule id" ;;
                soa)            is_domain_format_valid "$arg" 'SOA' ;;
                stats_pass)     is_password_format_valid "$arg" ;;
                stats_user)     is_user_format_valid "$arg" "$arg_name" ;;
                template)       is_object_format_valid "$arg" "$arg_name" ;;
                ttl)            is_int_format_valid "$arg" 'ttl';;
                user)           is_user_format_valid "$arg" $arg_name;;
                wday)           is_cron_format_valid "$arg" $arg_name ;;
            esac
        fi
    done
}

# Domain argument formatting
format_domain() {
    if [[ "$domain" = *[![:ascii:]]* ]]; then
        if [[ "$domain" =~ [[:upper:]] ]]; then
            domain=$(echo "$domain" |sed 's/[[:upper:]].*/\L&/')
        fi
    else
        if [[ "$domain" =~ [[:upper:]] ]]; then
            domain=$(echo "$domain" |tr '[:upper:]' '[:lower:]')
        fi
    fi
    if [[ "$domain" =~ ^www\..* ]]; then
        domain=$(echo "$domain" |sed -e "s/^www.//")
    fi
    if [[ "$domain" =~ .*\.$ ]]; then
        domain=$(echo "$domain" |sed -e "s/\.$//")
    fi
}

format_domain_idn() {
    if [ -z "$domain_idn" ]; then
        domain_idn=$domain
    fi
    if [[ "$domain_idn" = *[![:ascii:]]* ]]; then
        domain_idn=$(idn -t --quiet -a $domain_idn)
    fi
}

format_aliases() {
    if [ ! -z "$aliases" ] && [ "$aliases" != 'none' ]; then
        aliases=$(echo $aliases |tr '[:upper:]' '[:lower:]' |tr ',' '\n')
        aliases=$(echo "$aliases" |sed -e "s/\.$//" |sort -u)
        aliases=$(echo "$aliases" |grep -v www.$domain |sed -e "/^$/d")
        aliases=$(echo "$aliases" |tr '\n' ',' |sed -e "s/,$//")
    fi
}