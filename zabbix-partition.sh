#!/bin/bash

echo_usage() {
    echo -e "zabbix-partition.sh [-i] [-d #] [-e #] [-f #] [-m #] [-n #] [-o #] [-p] [-U #] [-P #] [-D #]"
    echo -e "-b\t- binary to use (default mysql)"
    echo -e "-c\t- zabbix config file with DB credentials"
    echo -e "-d\t- number of days to keep (default is 90)"
    echo -e "-e\t- number of daily partitions to create ahead (default is 1)"
    echo -e "-f\t- number of daily partitions to drop (default is 1)"
    echo -e "-h\t- prints this help"
    echo -e "-i\t- generate initial configuration instead of daily one"
    echo -e "-m\t- number of months to keep (default is 12)"
    echo -e "-n\t- number of monthly partitions to create ahead (default is 1)"
    echo -e "-o\t- number of monthly partitions to drop (default is 1)"
    echo -e "-p\t- force generation of monthly commands (normally these are generated only on 1st)"
    echo -e "-U\t- DB username (default zabbix)"
    echo -e "-P\t- DB password (default zabbix)"
    echo -e "-D\t- DB name (default zabbix)"    
}

# Defaults
DATABASE='zabbix'
DB_USER='zabbix'
DB_PASS='zabbix'
BIN='/usr/bin/mysql'
DB_CRED=''

DAYS_AHEAD=1
DAYS_BEHIND=1
DAYS_KEEP=90

MONTHS_AHEAD=1
MONTHS_BEHIND=1
MONTHS_KEEP=12

INIT=0
FORCE_MONTHLY=0

while getopts "b:c:d:e:f:him:n:o:pU:P:D:" opt; do
    case $opt in
        b)
            BIN=$OPTARG
            ;;
        c)
            DB_CRED=$OPTARG
            ;;
        d)
            DAYS_KEEP=$OPTARG
            ;;
        e)
            DAYS_AHEAD=$OPTARG
            ;;
        f)
            DAYS_BEHIND=$OPTARG
            ;;
        h)
            echo_usage
            exit 1
            ;;
        i)
            INIT=1
            ;;
        m)
            MONTHS_KEEP=$OPTARG
            ;;
        n)
            MONTHS_AHEAD=$OPTARG
            ;;
        o)
            MONTHS_BEHIND=$OPTARG
            ;;
        p)
            FORCE_MONTHLY=1
            ;;
        D)
            DATABASE=$OPTARG
            ;;
        U)
            DB_USER=$OPTARG   
            ;;
        P)
            DB_PASS=$OPTARG
            ;;
        *)
            echo_usage
            exit 1
            ;;
    esac
done

# Defaults for days partitioned tables
DAILY_PARTITIONED='history history_log history_str history_text history_uint'
DAILY_IDS='itemid id itemid id itemid'

# Defaults for monthly partitioned tables
MONTHLY_PARTITIONED='acknowledges alerts auditlog events service_alarms trends trends_uint'
MONTHLY_IDS='acknowledgeid alertid auditid eventid servicealarmid '

TODAY=$(date '+%Y-%m-%d')
DAY=$(date '+%-d')
MONTH=$(date '+%m')
YEAR=$(date '+%Y')
TIMESTAMP=$(date --date=${TODAY} +%s)

CONSTRAINT_TABLES="acknowledges alerts auditlog service_alarms auditlog_details"
CONSTRAINTS="c_acknowledges_1/c_acknowledges_2 c_alerts_1/c_alerts_2/c_alerts_3/c_alerts_4 c_auditlog_1 c_service_alarms_1 c_auditlog_details_1"

if [[ -n "$DB_CRED" && -a $DB_CRED && -r $DB_CRED ]]; then
    DB_USER=$(grep 'DBUser' $DB_CRED 2>/dev/null | cut -f2 -d'=')
    DB_PASS=$(grep 'DBPassword' $DB_CRED 2>/dev/null | cut -f2 -d'=')
fi

BIN="${BIN} -u ${DB_USER} -p${DB_PASS} -D ${DATABASE} -e"


if [[ $INIT -eq 1 ]]; then

    for table in $CONSTRAINT_TABLES; do
    
        constraints_table=$(echo $CONSTRAINTS | cut -f1 -d' ' )
        CONSTRAINTS=$(echo $CONSTRAINTS | cut -f2- -d' ' )

        for constraint in $( echo $constraints_table | tr '/' ' '); do
            ${BIN} "ALTER TABLE ${table} DROP FOREIGN KEY ${constraint};"
        done
    done

    IDS="${DAILY_IDS} ${MONTHLY_IDS}"

    for table in ${DAILY_PARTITIONED} ${MONTHLY_PARTITIONED}; do
        id=$(echo $IDS | cut -f1 -d' ')
        IDS=$(echo $IDS | cut -f2- -d' ')
        case $table in
            history_log|history_text)
                    ${BIN} "ALTER TABLE ${table} DROP PRIMARY KEY, ADD PRIMARY KEY (id, clock);"
                    ${BIN} "ALTER TABLE ${table} DROP KEY ${table}_2, ADD KEY ${table}_2(itemid, id);"
                ;;
            acknowledges|alerts|auditlog|events|service_alarms)
                    ${BIN} "ALTER TABLE ${table} DROP PRIMARY KEY, ADD KEY ${table}id (${id});"
                ;;
        esac
    done

    for table in $DAILY_PARTITIONED; do
        ${BIN} "ALTER TABLE ${table} PARTITION BY RANGE (clock) ( PARTITION pmax VALUES LESS THAN ( MAXVALUE ));"
    done

    month=$(( ( $MONTH % 12 ) + 1 ))    
    year=$(( $YEAR + ( $MONTH / 12 ) ))
    name=$(date --date="${year}-${month}-01" '+%Y%m%d')
    timestamp=$(date --date=$name '+%s')
    for table in $MONTHLY_PARTITIONED; do
        ${BIN} "ALTER TABLE ${table} PARTITION BY RANGE (clock) ( PARTITION pmax VALUES LESS THAN ( MAXVALUE ));"
    done

else 

    for table in $DAILY_PARTITIONED; do
        for ((i=1; i<=$DAYS_AHEAD; i++)); do
            timestamp=$(( $TIMESTAMP + (86400 * ($i + 1)) ))
            name=$(date --date="@${timestamp}" '+%Y%m%d')
            ${BIN} "ALTER TABLE ${table} REORGANIZE PARTITION pmax INTO ( PARTITION p${name} VALUES LESS THAN ( ${timestamp} ), PARTITION pmax VALUES LESS THAN (MAXVALUE) );"
        done

        for ((i=1; i<=$DAYS_BEHIND; i++)); do
            timestamp=$(( $TIMESTAMP - (86400 * ($i + $DAYS_KEEP )) ))
            name=$(date --date="@${timestamp}" '+%Y%m%d')
            ${BIN} "ALTER TABLE ${table} DROP PARTITION p${name};"
        done
    done

    if [[ $DAY -eq 1 || $FORCE_MONTHLY -eq 1 ]]; then

        for table in $MONTHLY_PARTITIONED; do
            for ((i=0; i<$MONTHS_AHEAD; i++)); do
                month=$(( (( $MONTH + $i ) % 12 ) + 1 ))    
                year=$(( $YEAR + ( $MONTH + $i ) / 12 ))
                name=$(date --date="${year}-${month}-01" '+%Y%m%d')
                timestamp=$(date --date=$name '+%s')
                ${BIN} "ALTER TABLE ${table} REORGANIZE PARTITION pmax INTO ( PARTITION p${name} VALUES LESS THAN ( ${timestamp} ), PARTITION pmax VALUES LESS THAN (MAXVALUE) );"
            done

            for ((i=0; i<$MONTHS_BEHIND; i++)); do
                month=$(( ( $MONTH - ( $i + $MONTHS_KEEP )) % 12 ))
                year=$(( $YEAR + (( $MONTH - ( $i + $MONTHS_KEEP ))  / 12 )))
                [[ $month -lt 1 ]] && month=$(( 12 + $month )) && year=$(( $year-1 ))
                name=$(date --date="${year}-${month}-01" '+%Y%m%d')
                timestamp=$(date --date=$name '+%s')
                ${BIN} "ALTER TABLE ${table} DROP PARTITION p${name};"
            done
        done

    fi
fi
