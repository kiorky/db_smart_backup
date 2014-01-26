#!/usr/bin/env sh
# LICENSE: BSD 3 clause
# Author: Mathieu Le Marec - Pasquet / kiorky@cryptelium.net

__NAME__="db_smart_backup"

# even if it is not really tested, we are trying to get full posix compatibility
# and to run on another shell than bash
#if [ x"$SHELL" = "x/bin/bash" ];then
#    set -o posix &> /dev/null
#fi

generate_configuration_file() {
    cat > ${DB_SMART_BACKUP_CONFFILE} << EOF

# A script run is only for one database at a time type (mysql, postgresql)
# But you can run it with multiple configuration files
# You can obiously share the same base backup directory.

# set to 1 to deactivate colors (cron)
#NO_COLOR=""

# Choose Compression type. (gzip or bzip2 or xz)
#COMP=bzip2

#User to run dumps dump binaries as
#RUNAS=

######## Backup settings
# one of: postgresql mysql
#BACKUP_TYPE=${BACKUP_TYPE:-}

# Backup directory location e.g /backups
#TOP_BACKUPDIR="/var/pgbackups"

# do also global backup (use by postgresql to save roles/groups and only that
#DO_GLOBAL_BACKUP="1"

# HOW MANY BACKUPS TO KEEP & LEVEL
#KEEP_DAYS=14
#KEEP_WEEKS=8
#KEEP_MONTHES=12

######## Database connection settings
# host defaults to localhost
# and without port we use a connexion via socket
#HOST=""
#PORT=""

# defaults to postgres on postgresql backup
# as ident is used by default on many installs, we certainly
# do not need either a password
#USER=""
#PASSWORD=""

# List of DBNAMES for Daily/Weekly Backup e.g. "DB1 DB2 DB3"
#DBNAMES="all"

# Include CREATE DATABASE in backup?
#CREATE_DATABASE=yes

# List of DBNAMES to EXLUCDE if DBNAMES are set to all (must be in " quotes)
#DBEXCLUDE=""

######## Mail setup
# What would you like to be mailed to you?
# - log   : send only log file
# - files : send log file and sql files as attachments (see docs)
# - stdout : will simply output the log to the screen if run manually.
#MAILCONTENT="stdout"

# Set the maximum allowed email size in k. (4000 = approx 5MB email [see docs])
#MAXATTSIZE="4000"

# Email Address to send mail to? (user@domain.com)
#MAILADDR="root@localhost"

# this server nick name
#MAIL_THISSERVERNAME="`hostname -f`"

######### Postgresql
# binaries path
#PSQL=""
#PG_DUMP=""
#PG_DUMPALL=""

# OPT string for use with pg_dump ( see man pg_dump )
#OPT="--create -Fc"

# OPT string for use with pg_dumpall ( see man pg_dumpall )
#OPTALL="--globals-only"

######## Hooks (optionnal)
# functions names which point to functions defined in your
# configuration file
# Pay attention not to make function names colliding with functions in the script

#
# All those hooks can call externals programs (eg: python scripts)
# Look inside the shell script to know which variables you ll have
# set in the context, but you ll have useful information available at
# each stage like the dbname, etc.
#

# Function to run before backups (uncomment to use)
#pre_backup_hook() {
#}

# Function to run after global backup  (uncomment to use)
#post_global_backup_hook() {
#}

# Function to run after global backup  (uncomment to use)
#post_global_backup_failure_hook() {
#}

# Fuction run after each database backup if the backup failed
#post_db_backup_failure_hook() {
#}

# Function to run after each database backup (uncomment to use)
#post_db_backup_hook() {
#}

# Function to run after backup rotation
#post_rotate_hook() {
#}

# Function to run after backup orphan cleanup
#post_cleanup_hook() {
#}

# Function run after backups (uncomment to use)
#post_backup_hook="mycompany_postbackup"

# Function to run after the recap mail emission
#post_mail_hook() {
#}

# Function to run after the recap mail emission
#failure_hook() {
#}
EOF
}

fn_exists() {
    echo $(LC_ALL=C LANG=C type $1 2>&1 | head -n1 | grep -q "is a function";echo $?)
}


log() {
    echo -e "${RED}[${__NAME__}] ${@}${NORMAL}" 1>&2
}

cyan_log() {
    echo -e "${CYAN}${@}${NORMAL}" 1>&2
}

die_() {
    ret="$1"
    shift
    cyan_log "$@"
    do_hook "FAILURE command output." "failure_hook"
    exit ${ret}
}

die() {
    die_ 1 "$@"
}

die_in_error_() {
    ret="$1"
    shift
    msg="${@:-"${ERROR_MSG}"}"
    if [ x"${ret}" != "x0" ];then
        die_ "${ret}" "${msg}"
    fi
}

die_in_error() {
    die_in_error_ "$?" "$@"
}

yellow_log(){
    echo -e "${YELLOW}[${__NAME__}] ${@}${NORMAL}" 1>&2
}

cyan_log(){
    echo -e "${CYAN}[${__NAME__}] ${@}${NORMAL}" 1>&2
}

usage() {
    cyan_log "- Backup your databases with ease"
    yellow_log "  $0"
    yellow_log "     /path/toconfig"
    yellow_log "        alias to --backup"
    yellow_log "     -b|--backup /path/toconfig:"
    yellow_log "        backup databases"
    yellow_log "     --gen-config [/path/toconfig (default: ${DB_SMART_BACKUP_CONFFILE}_DEFAULT)]"
    yellow_log "        generate a new config file]"
}

quote_all() {
    cmd=""
    for i in "$@";do
        cmd="${cmd} \"$(echo "$i"|sed "s/\"/\"\'\"/g")\""
    done
    echo "${cmd}"
}

runas() {
    bin="$1"
    shift
    args=$(quote_all "$@")
    if [ x"$RUNAS" != "x" ];then
        su $RUNAS -c "$bin $args"
    else
        "$bin" "$@"
    fi
}

pg_dumpall_() {
    runas ${PG_DUMPALL} "$@"
}

pg_dump_() {
    runas ${PG_DUMP} "$@"
}

psql_() {
    runas ${PSQL} "$@"
}

postgresql_get_all_databases() {
    psql_ --username=${PGUSER:-postgres} ${HOST} -l -A -F: | sed -ne "/:/ { /Name:Owner/d; /template0/d; s/:.*$//; p }"
}

postgresql_dumpall() {
    pg_dumpall_ $OPTALL "$1" > "$2"
}

postgresql_dump() {
    pg_dump_ $OPT "$1" > "$2"
}

get_compressed_name() {
    if [ x"${COMP}" = "xxz" ];then
        echo "$1.xz";
    elif [ x"${COMP}" = "xgz" ] || [ x"${COMP}" = "xgzip" ];then
        echo "$1.gz";
    elif [ x"${COMP}" = "xbzip2" ] || [ x"${COMP}" = "xbz2" ];then
        echo "$1.bz2";
    else
        echo "$1";
    fi
}

set_compressor() {
    for comp in ${COMP} ${COMP}S;do
        c=""
        if [ x"${COMP}" = "xxz" ];then
            XZ="${XZ:-xz}"
            c="${XZ}"
        elif [ x"${COMP}" = "xgz" ] || [ x"${COMP}" = "xgzip" ];then
            GZIP="${GZIP:-gzip}"
            c="$GZIP"
        elif [ x"${COMP}" = "xbzip2" ] || [ x"${COMP}" = "xbz2" ];then
            BZIP2="${BZIP2:-bzip2}"
            c="$BZIP2"
        else
            c="nocomp"
        fi
        # test that the binary is present
        if [ x"$c" != "xnocomp" ] && [ -e "$(which "$c")" ];then
            log "Using compressor: ${COMP}"
            break
        else
            COMP="nocomp"
        fi
    done
    if [ x"$c" = "xnocomp" ];then
        log "No compressor found"
    fi
}

comp_msg() {
    log "Compressing ${name} using ${COMP}"
}

do_compression() {
    COMPRESSED_NAME=""
    name="$1"
    zname="${2:-$(get_compressed_name $1)}"
    if [ x"${COMP}" = "xxz" ];then
        comp_msg
        "$XZ" --stdout -f -k -v "${name}" > "${zname}"
    elif [ x"${COMP}" = "xgz" ] || [ x"${COMP}" = "xgzip" ];then

        comp_msg
        "$GZIP" -f -c "${name}" > "${zname}"
        log "Backup information for ${name}"
        "$GZIP" -l "${zname}"
    elif [ x"${COMP}" = "xbzip2" ] || [ x"${COMP}" = "xbz2" ];then
        comp_msg
        log "Backup information for ${name}"
        "$BZIP2" -f -k -c -v "${name}" > "${zname}"
    else
        /bin/true # noop
    fi
    if [ -e "${zname}" ] && [ x"${zname}" != "x${name}" ];then
        COMPRESSED_NAME="${zname}"
    else
        if [ -e "${name}" ];then
            log "No compressor found, no compression done"
            COMPRESSED_NAME="${name}"
        else
            log "Compression error"
        fi
    fi
}

get_backupdir() {
    dir="${TOP_BACKUPDIR}/${BACKUP_TYPE:-}"
    if [  x"${BACKUP_TYPE}" = "xpostgresql" ];then
        host="${HOST}"
        if [ x"${HOST}" = "x" ] || [ x"${PGHOST}" = "x" ];then
            host="localhost"
        fi
        dir="$dir/$host"
    fi
    echo "$dir"
}

create_db_directories() {
    db="$1"
    dbdir="$(get_backupdir)/${db}"
    dirs="$dirs $(get_backupdir)/${db}/daily"
    dirs="$dirs $(get_backupdir)/${db}/monthly"
    dirs="$dirs $(get_backupdir)/${db}/weekly"
    dirs="$dirs $(get_backupdir)/${db}/dumps"
    for d in\
        "$dbdir"\
        "$dbdir/weekly"\
        "$dbdir/monthly"\
        "$dbdir/dumps"\
        "$dbdir/daily"\
        ;do
        if [ ! -e "$d" ];then
            mkdir -p "$d"
        fi
    done

}

link_into_dirs() {
    db="$1"
    real_filename="$2"
    real_zfilename="$(get_compressed_name "${real_filename}")"
    daily_filename="$(get_backupdir)/${db}/daily/${db}_${YEAR}_${DOY}_${DATE}.sql"
    weekly_filename="$(get_backupdir)/${db}/weekly/${db}_${YEAR}_${W}.sql"
    monthly_filename="$(get_backupdir)/${db}/monthly/${db}_${YEAR}_${MNUM}.sql"
    daily_zfilename="$(get_compressed_name "${daily_filename}")"
    weekly_zfilename="$(get_compressed_name "$weekly_filename")"
    monthly_zfilename="$(get_compressed_name "${monthly_filename}")"
    if [ ! -e "${daily_zfilename}" ];then
        ln "${real_zfilename}" "${daily_zfilename}"
    fi
    if [ ! -e "${weekly_zfilename}" ];then
        ln "${real_zfilename}" "${weekly_zfilename}"
    fi
    if [ ! -e "${monthly_zfilename}" ];then
        ln "${real_zfilename}" "${monthly_zfilename}"
    fi
}

dummy_callee_for_tests() {
    echo "here"
}

dummy_for_tests() {
    dummy_callee_for_tests
}

do_db_backup_() {
    db="$1"
    fun_="$2"
    create_db_directories "${db}"
    real_filename="$(get_backupdir)/${db}/dumps/${db}_${DATE}.sql"
    zreal_filename="$(get_compressed_name "${real_filename}")"
    $fun_ "${db}" "${real_filename}"
    do_compression "${real_filename}" "${zreal_filename}"
    link_into_dirs "${db}" "${real_filename}"
}

do_db_backup() {
    db="`echo $1 | sed 's/%/ /g'`"
    fun_="${BACKUP_TYPE}_dump"
    do_db_backup_ "${db}" "$fun_"
}

do_global_backup() {
    db="$GLOBAL_SUBDIR"
    fun_="${BACKUP_TYPE}_dumpall"
    do_db_backup_ "${db}" "$fun_"
}

do_sendmail() {
    if [ x"${MAILCONTENT}" = "xfiles" ]; then
        #Get backup size
        ATTSIZE=`du -c ${BACKUPFILES} | grep "[[:digit:][:space:]]total$" |sed s/\s*total//`
        if [ ${MAXATTSIZE} -ge ${ATTSIZE} ];then
            BACKUPFILES=`log "${BACKUPFILES}" | sed -e "s# # -a #g"`    #enable multiple attachments
            mutt -s "PostgreSQL Backup Log and SQL Files for ${PGHOST} - ${DATE}" ${BACKUPFILES} ${MAILADDR} < ${LOGFILE}        #send via mutt
        else
            cat "${LOGFILE}" | mail -s "WARNING! - PostgreSQL Backup exceeds set maximum attachment size on ${PGHOST} - ${DATE}" ${MAILADDR}
        fi
    elif [ x"${MAILCONTENT}" = "xlog" ];then
        cat "${LOGFILE}" | mail -s "PostgreSQL Backup Log for ${MAIL_THISSERVERNAME} - ${DATE}" ${MAILADDR}
    else
        cat "${LOGFILE}"
    fi
}

do_pre_backup() {
    # IO redirection for logging.
    touch ${LOGFILE}
    exec 6>&1           # Link file descriptor #6 with stdout.
    exec > ${LOGFILE}     # stdout replaced with file ${LOGFILE}.
    # If backing up all DBs on the server
    log "======================================================================"
    log "DB_SMART_BACKUP by kiorky@cryptelium.net"
    log "http://www.makina-corpus.com"
    log ""
    log "Backup of Database Server - ${PGHOST}"
    log "======================================================================"
    # Run command before we begin
    # Test is seperate DB backups are required
    log "Backup Start Time `date`"
    log "======================================================================"
}

do_post_backup() {
    # Run command when we're done
    log "======================================================================"
    log "Backup End Time `date`"
    log "======================================================================"
    log "Total disk space used for backup storage.."
    log "Size - Location"
    log "`du -hs "$(get_backupdir)"`"
    log ""
    #Clean up IO redirection
    exec 1>&6 6>&-      # Restore stdout and close file descriptor #6.
    # Clean up Logfile
}

get_sorted_files() {
    files="$(ls -1 "${1}" 2>/dev/null)"
    sep="____----____----____"
    echo -e "$files"|while read fic;do
        key=""
        oldkey="$fic"
        while true;do
            key="$(echo "${oldkey}"|sed -e "s/_\([0-9][^0-9]\)/_0\1/g")"
            if [ x"${key}" != x"${oldkey}" ];then
                oldkey="${key}"
            else
                break
            fi
        done
        echo "${key}${sep}${fic}"
    done | sort -n -r | awk -F"$sep" '{print $2}'
}

do_rotate() {
    log "Execute backup rotation policy"
    log "   - keep ${KEEP_DAYS} days"
    log "   - keep ${KEEP_WEEKS} weeks"
    log "   - keep ${KEEP_MONTHES} monthes"
    log ""
    # ./TOPDIR/POSTGRESQL/HOSTNAME
    ls -1d "$(get_backupdir)"/*|while read nsubdir;do
        log "   Operating in: '$nsubdir'"
        # ./TOPDIR/HOSTNAME/DBNAME/${monthly,weekly,daily,dumps}
        for chronodir in monthly weekly daily;do
            subdir="${nsubdir}/${chronodir}"
            if [ -d "${subdir}" ];then
                if [ x"${chronodir}" = "xweekly" ];then
                    to_keep=${KEEP_WEEKS}
                elif [ x"${chronodir}" = "xmonthly" ];then
                    to_keep=${KEEP_MONTHES}
                elif [ x"${chronodir}" = "xdaily" ];then
                    to_keep=${KEEP_DAYS}
                else
                    to_keep="65635" # int limit
                fi
                i=0
                get_sorted_files "${subdir}" | while read nfic;do
                    fic="${subdir}/${nfic}"
                    i="$(($i+1))"
                    if [ "$i" -gt "${to_keep}" ] && [ -e "${fic}" ];then
                        log "       * Pruning ${fic}"
                        rm "${fic}"
                    fi
                done
            fi
        done
    done
}

do_cleanup_orphans() {
    # prune all files in dumps dirs which have no more any
    # hardlinks in chronoted directories (weekly, monthly, daily)
    for dumpsdirs in "$(find "${TOP_BACKUPDIR}" -name dumps)";do
        for fic in "$(find "$dumpsdirs" -type f -links 1)";do
            rm -f "${fic}"
        done
    done
}

do_hook() {
    header="$1"
    cmd="$2"
    if [ x"$(fn_exists ${cmd})" = "x0" ];then
        log "======================================================================"
        log "${header}"
        log ""
        ${cmd}
        log ""
        log "======================================================================"
        log ""
    fi
}

do_backup() {
    # source conf file if any
    if [ -e "${DB_SMART_BACKUP_CONFFILE}" ];then
        . "${DB_SMART_BACKUP_CONFFILE}"
    else
        cyan_log "Missing configuration file: ${DB_SMART_BACKUP_CONFFILE}"
        usage
        exit 1
    fi
    # if either the source failed or we do not have a configuration file, bail out
    die_in_error "Invalid configuration file: ${DB_SMART_BACKUP_CONFFILE}"
    do_pre_backup
    do_hook "Prebackup command output." "pre_backup_hook"
    if [ x"$DO_GLOBAL_BACKUP" != "x"];then
        do_global_backup
        if [ x"$?" = "x0" ];then
            do_hook "Postglobalbackup command output." "post_global_backup_hook"
        else
            do_hook "Postglobalbackup(failure) command output." "post_global_backup_failure_hook"
        fi
    fi
    for DB in ${DBNAMES};do
        do_db_backup $DB
        if [ x"$?" = "x0" ];then
            do_hook "Postdbbackup: ${DBNAME}  command output." "post_db_backup_hook"
        else
            do_hook "Postdbbackup: ${DBNAME}(failure)  command output." "post_db_backup_failure_hook"
        fi
    done
    do_rotate
    do_hook "Postrotate command output." "post_rotate_hook"
    cleanup_orphans
    do_hook "Postcleanup command output." "post_cleanup_hook"
    do_hook "Postbackup command output." "post_backup_hook"
    do_post_backup
    do_sendmail
    do_hook "Postmail command output." "post_mail_hook"
    eval rm -f "${LOGFILE}"
}

mark_run_backup() {
    DB_SMART_BACKUP_CONFFILE="$1"
    DO_BACKUP="1"
}

set_postgresql_vars() {
    if [ x"${USER}" = "x" ];then
        USER="postgres"
    fi
    export RUNAS="${RUNAS:-postgres}"
    export PGHOST="${HOST}"
    export PGPORT="${PORT}"
    export PGUSER="${USER}"
    export PGPASSWORD="${PASSWORD}"
    if [ x"${PGHOST}" = "xlocalhost" ]; then
        PGHOST=
    fi
    if [ x"${DBNAMES}" = "xall" ]; then
        if [[ " ${DBEXCLUDE} " != *" template0 "* ]];then
            DBEXCLUDE="${DBEXCLUDE} template0"
        fi
        for exclude in ${DBEXCLUDE};do
            DBNAMES=`echo ${ALL_DBNAMES} | sed "s/\b${exclude}\b//g"`
        done
    fi
    for i in "psql::${PSQL}" "pg_dumpall::${PG_DUMPALL}" "pg_dump::${PG_DUMP}";do
        var="$(echo $i|awk -F:: '{print $1}')"
        bin="$(echo $i|awk -F:: '{print $2}')"
        if  [ ! -e "$bin" ];then
            die "missing $var"
        fi
    done
}

verify_backup_type() {
    for typ_ in _dump _dumpall;do
        if [ x"$(fn_exists ${BACKUP_TYPE}${typ_})" = "x0" ];then
            die "Please provide a ${BACKUP_TYPE}${typ_} export function"
        fi
    done
}

set_vars() {
    args=$@
    YELLOW="\e[1;33m"
    RED="\\033[31m"
    CYAN="\\033[36m"
    NORMAL="\\033[0m"
    if [ x"$NO_COLORS" != "x" ];then
        YELLOW=""
        RED=""
        CYAN=""
        NORMAL=""
    fi
    PARAM=""
    DB_SMART_BACKUP_CONFFILE_DEFAULT="/etc/db_smartbackup.conf.sh"
    if [ x"$@" == "x" ];then
        USAGE="1"
    fi
    if [ -e "$@" ];then
        mark_run_backup $1
    else
        while true
        do
            sh="1"
            if [ x"$1" = "x$PARAM" ];then
                break
            fi
            if [ x"$1" = "x--gen-config" ];then
                GENERATE_CONFIG="1"
                DB_SMART_BACKUP_CONFFILE="${2:-${DB_SMART_BACKUP_CONFFILE}_DEFAULT}"
                sh="2"
            elif [ x"$1" = "x-b" ] || [ x"$1" = "x--backup" ];then
                mark_run_backup $2;sh="2"
            else
                USAGE="1"
            fi
            PARAM="$1"
            OLD_ARG="$1"
            for i in $(seq $sh);do
                shift
                if [ x"$1" = "x${OLD_ARG}" ];then
                    break
                fi
            done
            if [ x"$1" = "x" ];then
                break
            fi
        done
    fi
    if [ x"${USAGE}" != "x" ];then
        usage
        exit 0
    fi

    ######## Backup settings
    NO_COLOR="${NO_COLOR:-}"
    COMP=${COMP:-bzip2}
    BACKUP_TYPE=${BACKUP_TYPE:-}
    if [ x"${BACKUP_TYPE}" = "x" ];then
        die "No backup type, choose between mysql & postgresql"
    fi
    TOP_BACKUPDIR="${TOP_BACKUPDIR:-/var/pgbackups}"
    DO_GLOBAL_BACKUP="1"
    KEEP_DAYS="${NB_DAILY:-14}"
    KEEP_WEEKS="${NB_WEEKLY:-8}"
    KEEP_MONTHES="${NB_MONTHLY:-12}"

    ######## Database connection settings
    HOST="${HOST:-localhost}"
    PORT="${PORT:-}"
    USER="${USER:-}"
    PASSWORD="${PASSWORD:-}"
    DBNAMES="${DBNAMES:-all}"
    CREATE_DATABASE=${CREATE_DATABASE:-yes}
    DBEXCLUDE="${DBEXCLUDE:-}"

    ######## Mail setup
    MAILCONTENT="${MAILCONTENT:-stdout}"
    MAXATTSIZE="${MAXATTSIZE:-4000}"
    MAILADDR="${MAILADDR:-root@localhost}"
    MAIL_SERVERNAME="${MAIL_SERVERNAME:-`hostname -f`}"

    ######### Postgresql
    PSQL="${PSQL:-"$(which psql 2>/dev/null)"}"
    PG_DUMP="${PG_DUMP:-"$(which pg_dump 2>/dev/null)"}"
    PG_DUMPALL="${PG_DUMPALL:-"$(which pg_dumpall 2>/dev/null)"}"
    OPT="${OPT:-"--create -Fc"}"
    OPTALL="${OPTALL:-"--globals-only"}"

    ######## Hooks
    pre_backup_hook="${pre_backup_hook:-}"
    post_global_backup_hook="${post_global_backup_hook-}"
    post_db_backup_hook="${post_db_backup_hook-}"
    post_backup_hook="${post_backup_hook-}"

    ######## Advanced options
    COMPS="xz bz2 gzip nocomp"
    GLOBAL_SUBDIR="__GLOBAL__"
    PATH=$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
    DATE=`date +%Y-%m-%d` # Datestamp e.g 2002-09-21
    DOY=`date +%j`  # Day of the YEAR 0..366
    DOW=`date +%A`  # Day of the week e.g. Monday
    DNOW=`date +%u` # Day number of the week 1 to 7 where 1 represents Monday
    DOM=`date +%d`  # Date of the Month e.g. 27
    M=`date +%B`    # Month e.g January
    YEAR=`date +%Y` # Datestamp e.g 2002-09-21
    MNUM=`date +%m` # Month e.g 1
    W=`date +%V`    # Week Number e.g 37
    LOGFILE=${TOP_BACKUPDIR}/${PGHOST}-`date +%N`.log    # Logfile Name
    BACKUPFILES=""                    # thh: added for later mailing

    set_compressor

    if [ x"${BACKUP_TYPE}" != "x" ];then
        ALL_DBNAMES="$(${BACKUP_TYPE}_get_all_databases)"
        verify_backup_type
    fi

    if [ x"${BACKUP_TYPE}" = "xpostgresql" ] && [ x"${BACKUP_TYPE}" = "xmysql" ];then
        "set_${BACKUP_TYPE}_vars"
    fi
}

do_main() {
    set_vars "$@"
    if [ x"${GENERATE_CONFIG}" != "x" ];then
        generate_configuration_file
        die_in_error "end_of_scripts"
    elif [ x"${DO_BACKUP}" != "x" ];then
        do_backup
        die_in_error "end_of_scripts"
    fi
}

if [ x"${DB_SMART_BACKUP_AS_FUNCS}" = "x" ];then
    do_main "$@"
fi
