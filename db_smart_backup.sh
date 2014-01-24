#!/usr/bin/env bash
# LICENSE: BSD 3 clause
# Author: Mathieu Le Marec - Pasquet / kiorky@cryptelium.net
BACKUP_SERVERS="postgresql mysql"
# Backup directory location e.g /backups
BACKUPDIR="/var/pgbackups"
# do also global backup (use by postgresql to save roles/groups and only that
DO_GLOBAL_BACKUP="1"
# HOW MANY BACKUPS TO KEEP & LEVEL
KEEP_DAILY="${NB_DAILY:-14}"
KEEP_WEEKLY="${NB_WEEKLY-8}"
KEEP_MONTHLY="${NB_MONTHLY-12}"
KEEP_FULL_DAILY="${NB_DAILY:-14}"
KEEP_FULL_WEEKLY="${NB_WEEKLY-8}"
KEEP_FULL_MONTHLY="${NB_MONTHLY-12}"
# Choose Compression type. (gzip or bzip2)
COMP=bzip2

######## Mail setup
# What would you like to be mailed to you?
# - log   : send only log file
# - files : send log file and sql files as attachments (see docs)
# - stdout : will simply output the log to the screen if run manually.
MAILCONTENT="stdout"

# Set the maximum allowed email size in k. (4000 = approx 5MB email [see docs])
MAXATTSIZE="4000"

# Email Address to send mail to? (user@domain.com)
MAILADDR="root@localhost"

# this server nick name
MAIL_SERVERNAME="`hostname -f`"

# Include CREATE DATABASE in backup?
CREATE_DATABASE=yes

######### Postgresql
# Postgresql password
# create a file $HOME/.pgpass containing a line like this
#   hostname:*:*:dbuser:dbpass
# replace hostname with the value of PGHOST and postgres with
# Host name (or IP address) of PostgreSQL server e.g localhost
# Username to access the PostgreSQL server e.g. dbuser
PG_USERNAME="postgres"
PGHOST="localhost"
# Hostname for LOG information
PGPORT="${PGPORT:-5432}"
PSQL="${PSQL:-psql}"
PG_DUMP="${PG_DUMP-pg_dump}"
# OPT string for use with pg_dump ( see man pg_dump )
OPT="--create -Fc"
PG_DUMPALL="${PG_DUMPALL-pg_dumpall}"
# OPT string for use with pg_dumpall ( see man pg_dumpall )
OPTALL="--globals-only"
# List of PG_DBNAMES for Daily/Weekly Backup e.g. "DB1 DB2 DB3"
PG_DBNAMES="all"
# List of PG_DBNAMES to EXLUCDE if PG_DBNAMES are set to all (must be in " quotes)
PG_DBEXCLUDE="template0"

# Command to run before backups (uncomment to use)
# PREBACKUP="/etc/pgsql-backup-pre"

# Command run after backups (uncomment to use)
# POSTBACKUP="bash /home/backups/scripts/ftp_pgsql"

######## Advanced options
GLOBAL_SUBDIR="__GLOBAL__"
PATH=/usr/local/bin:/usr/bin:/bin:/usr/local/postgres/bin:/usr/local/pgsql/bin
DATE=`date +%Y-%m-%d` # Datestamp e.g 2002-09-21
DOY=`date +%j`        # Day of the YEAR 0..366
DOW=`date +%A`        # Day of the week e.g. Monday
DNOW=`date +%u`       # Day number of the week 1 to 7 where 1 represents Monday
DOM=`date +%d`        # Date of the Month e.g. 27
M=`date +%B`          # Month e.g January
MNUM=`date +%m`      # Month e.g 1
W=`date +%V`          # Week Number e.g 37
LOGFILE=$BACKUPDIR/$PGHOST-`date +%N`.log    # Logfile Name
BACKUPFILES=""                    # thh: added for later mailing

# Database dump function
get_all_databases() {
    $PSQL --username=$PG_USERNAME $HOST -l -A -F: | sed -ne "/:/ { /Name:Owner/d; /template0/d; s/:.*$//; p }"
}

db_dumpall() {
    $PG_DUMPALL --username=$PG_USERNAME $HOST $OPTALL $1 > $2
    return 0
}

db_dump() {
    $PG_DUMP --username=$PG_USERNAME $HOST $OPT $1 > $2
    return 0
}

# Compression function
get_compressed_name() {
    case $COMP in
        gz|gzip)
            echo "$1.gz";;
        bz2|bzip2)
            echo "$1.bz2";;
        *)
            echo "$1";;
    esac
}

compression() {
    local name="$(get_compressed_name $1)"
    case $COMP in
        gz|gzip)
            gzip -f "$1"
            echo "Backup information for $name"
            gzip -l "$name"
            ;;
        bz2|bzip2)
            echo "Backup information for $name"
            bzip2 -f -v $1 2>&1
            ;;
        *)
            echo "No compression option set, check advanced settings";;
    esac
}

# source conf file if any
CONFFILE="/etc/autopostgresqlbackup.conf.sh"
if [[ -e "$CONFFILE" ]];then
    . "$CONFFILE"
fi

create_directories() {
    # Create required directories
    local db="$GLOBAL_SUBDIR"
    local sdirs="$BACKUPDIR/$db"
    local sdirs="$dirs $BACKUPDIR/$db/daily"
    local sdirs="$dirs $BACKUPDIR/$db/monthly"
    local sdirs="$dirs $BACKUPDIR/$db/weekly"
    local sdirs="$dirs $BACKUPDIR/$db/dumps"
    for d in $sdirs;do
        if [ ! -e "$d" ];then
            mkdir -p "$d"
        fi
    done
}

create_db_directories() {
    local db=$1
    local dirs="$BACKUPDIR/$db"
    local dirs="$dirs $BACKUPDIR/$db/daily"
    local dirs="$dirs $BACKUPDIR/$db/monthly"
    local dirs="$dirs $BACKUPDIR/$db/weekly"
    local dirs="$dirs $BACKUPDIR/$db/dumps"
    for d in $dirs;do
        if [ ! -e "$d" ];then
            mkdir -p "$d"
        fi
    done
}

link_into_dirs() {
    local db="$1"
    local real_filename="$2"
    local real_zfilename="$(get_compressed_name $real_filename)"
    local daily_filename="$BACKUPDIR/${db}/daily/${W}_${DOY}_${db}_${DATE}.sql"
    local weekly_filename="$BACKUPDIR/${db}/weekly/${W}_${db}_${DATE}.sql"
    local monthly_filename="$BACKUPDIR/${db}/monthly/${MNUM}_${db}_${DATE}.sql"
    local daily_zfilename="$(get_compressed_name $daily_filename)"
    local weekly_zfilename="$(get_compressed_name $weekly_filename)"
    local monthly_zfilename="$(get_compressed_name $monthly_filename)"
    if [[ ! -e "$daily_zfilename" ]];then
        ln "$real_zfilename" "$daily_zfilename"
    fi
    if [[ ! -e "$weekly_zfilename" ]];then
        ln "$real_zfilename" "$weekly_zfilename"
    fi
    if [[ ! -e "$monthly_zfilename" ]];then
        ln "$real_zfilename" "$monthly_zfilename"
    fi
}

do_db_backup_() {
    create_db_directories "$DB"
    local real_filename="$BACKUPDIR/${DB}/dumps/${DB}_${DOY}_${DATE}.sql"
    # db_dump "$db" "$real_filename"
    # compression "$real_filename"
    echo > "$real_zfilename"
    link_into_dirs "$db" "$real_filename"
}

do_db_backup() {
    local db="`echo $1 | sed 's/%/ /g'`"
    local fun_="db_dump"
    do_db_backup_ "$db" "$fun_"
}

do_global_backup() {
    local db="$GLOBAL_SUBDIR"
    local fun_="db_dumpall"
    do_db_backup_ "$db" "$fun_"
}

do_sendmail() {
    if [ "$MAILCONTENT" = "files" ]; then
        #Get backup size
        ATTSIZE=`du -c $BACKUPFILES | grep "[[:digit:][:space:]]total$" |sed s/\s*total//`
        if [ $MAXATTSIZE -ge $ATTSIZE ]
        then
            BACKUPFILES=`echo "$BACKUPFILES" | sed -e "s# # -a #g"`    #enable multiple attachments
            mutt -s "PostgreSQL Backup Log and SQL Files for $PGHOST - $DATE" $BACKUPFILES $MAILADDR < $LOGFILE        #send via mutt
        else
            cat "$LOGFILE" | mail -s "WARNING! - PostgreSQL Backup exceeds set maximum attachment size on $PGHOST - $DATE" $MAILADDR
        fi
    elif [ "$MAILCONTENT" = "log" ];then
        cat "$LOGFILE" | mail -s "PostgreSQL Backup Log for $PGHOST - $DATE" $MAILADDR
    else
        cat "$LOGFILE"
    fi
}

do_post_backup() {
    # Run command when we're done
    if [ "$POSTBACKUP" ]; then
        echo ======================================================================
        echo "Postbackup command output."
        echo
        eval $POSTBACKUP
        echo
        echo ======================================================================
    fi
    echo Backup End Time `date`
    echo ======================================================================
    echo Total disk space used for backup storage..
    echo Size - Location
    echo `du -hs "$BACKUPDIR"`
    echo
    #Clean up IO redirection
    exec 1>&6 6>&-      # Restore stdout and close file descriptor #6.
    # Clean up Logfile
}

do_rotate() {
    echo ""

}

do_cleanup_orphans() {
    echo ""
}


set_vars() {
    if [ "$PGHOST" = "localhost" ]; then
        PGHOST=
    fi
}
do_main() {
    set_vars
    # IO redirection for logging.
    touch $LOGFILE
    exec 6>&1           # Link file descriptor #6 with stdout.
    exec > $LOGFILE     # stdout replaced with file $LOGFILE.

    # If backing up all DBs on the server
    echo ======================================================================
    echo AutoPostgreSQLBackup
    echo http://www.makina-corpus.com
    echo
    echo Backup of Database Server - $PGHOST
    echo ======================================================================
    # Run command before we begin
    if [ "$PREBACKUP" ]
    then
        echo ======================================================================
        echo "Prebackup command output."
        echo
        eval $PREBACKUP
        echo
        echo ======================================================================
        echo
    fi
    # Test is seperate DB backups are required
    echo Backup Start Time `date`
    echo ======================================================================
    if [ "$PG_DBNAMES" = "all" ]; then
        PG_DBNAMES="$(get_all_databases)"
        # If DBs are excluded
        for exclude in $PG_DBEXCLUDE;do
            PG_DBNAMES=`echo $PG_DBNAMES | sed "s/\b$exclude\b//g"`
        done
    fi
    if [[ -n $DO_GLOBAL_BACKUP ]];then
        do_global_backup
    fi
    create_directories
    for DB in $PG_DBNAMES;do
        do_db_backup $DB
    done
    do_rotate
    cleanup_orphans
    do_post_backup
    do_sendmail
    eval rm -f "$LOGFILE"
}

if [[ -z $DB_SMART_BACKUP_AS_FUNCS ]];then
    do_main
fi
exit 0
