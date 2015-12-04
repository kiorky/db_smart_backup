#!/usr/bin/env bash
# LICENSE: BSD 3 clause
# Author: Mathieu Le Marec - Pasquet / kiorky@cryptelium.net

__NAME__="db_smart_backup"

# even if it is not really tested, we are trying to get full posix compatibility
# and to run on another shell than bash
#if [ x"$SHELL" = "x/bin/bash" ];then
#    set -o posix &> /dev/null
#fi

generate_configuration_file() {
    cat > ${DSB_CONF_FILE} << EOF

# A script can run only for one database type and a specific host
# at a time (mysql, postgresql)
# But you can run it with multiple configuration files
# You can obiously share the same base backup directory.

# set to 1 to deactivate colors (cron)
#NO_COLOR=""

# Choose Compression type. (gzip or bzip2 or xz)
#COMP=bzip2

#User to run dumps dump binaries as, defaults to logged in user
#RUNAS=postgres
#DB user to connect to the database with, defaults to $RUNAS
#DBUSER=postgres

######## Backup settings
# one of: postgresql mysql
#BACKUP_TYPE=postgresql
#BACKUP_TYPE=mysql
#BACKUP_TYPE=mongodb
#BACKUP_TYPE=slapd
#BACKUP_TYPE=redis
#BACKUP_TYPE=es

# Backup directory location e.g /backups
#TOP_BACKUPDIR="/var/db_smart_backup"

# do also global backup (use by postgresql to save roles/groups and only that
#DO_GLOBAL_BACKUP="1"

# HOW MANY BACKUPS TO KEEP & LEVEL
# How many snapshots to keep (lastlog for dump)
# How many per day
#KEEP_LASTS=24
#KEEP_DAYS=14
#KEEP_WEEKS=8
#KEEP_MONTHES=12
#KEEP_LOGS=60

# directories permission
#DPERM="750"

# directory permission
#FPERM="640"

# OWNER/GROUP
#OWNER=root
#GROUP=root

######## Database connection settings
# host defaults to localhost
# and without port we use a connection via socket
#HOST=""
#PORT=""

# defaults to postgres on postgresql backup
# as ident is used by default on many installs, we certainly
# do not need either a password
#PASSWORD=""

# List of DBNAMES for Daily/Weekly Backup e.g. "DB1 DB2 DB3"
#DBNAMES="all"

# List of DBNAMES to EXLUCDE if DBNAMES are set to all (must be in " quotes)
#DBEXCLUDE=""

######### Elasticsearch
# ES_URI="http://localhost:9200"
# ES_USER="user"
# ES_PASSWORD="secret"
# path to snapshots (have to be added to path.repo in elasticsearch.yml)
# ES_SNAPSHOTS_DIR="${ES_SNAPSHOTS_DIR:-${ES_TMP}/snapshots}"
# elasticsearch daemon user

######### Postgresql
# binaries path
#PSQL=""
#PG_DUMP=""
#PG_DUMPALL=""

######## slapd
# SLAPCAT_ARGS="${SLAPCAT_ARGS:-""}"
# SLAPD_DIR="${SLAPD_DIR:-/var/lib/ldap}"

# OPT string for use with pg_dump ( see man pg_dump )
#OPT="--create -Fc"

# OPT string for use with pg_dumpall ( see man pg_dumpall )
#OPTALL="--globals-only"

######## MYSQL
#MYSQL_SOCK_PATHS=""
#MYSQL=""
#MYSQLDUMP=""
# do we disable mysqldump --single-transaction0
#MYSQLDUMP_NO_SINGLE_TRANSACTION=""
# disable to enable autocommit
#MYSQLDUMP_AUTOCOMMIT="1"
# set to enable complete inserts (true by default, disabling enable extended inserts)
#MYSQLDUMP_COMPLETEINSERTS="1"
# do we disable mysqldump --lock-tables=false
#MYSQLDUMP_LOCKTABLES=""
# set to add extra dumps info
#MYSQLDUMP_DEBUG=""
# set to disable dump routines
#MYSQLDUMP_NOROUTINES=""
# do we use ssl to connect
#MYSQL_USE_SSL=""

######## mongodb
# MONGODB_PATH="${MONGODB_PATH:-"/var/lib/mongodb"}"
# MONGODB_USER="${MONGODB_USER:-""}"
# MONGODB_PASSWORD="${MONGODB_PASSWORD:-""}"
# MONGODB_ARGS="${MONGODB_ARGS:-""}"

######## Redis
# REDIS_PATH="${REDIS_PATH:-"/var/lib/redis"}"

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
#failure_hook() {
#}
# vim:set ft=sh:
EOF
}

fn_exists() {
    echo $(LC_ALL=C;LANG=C;type ${1} 2>&1 | head -n1 | grep -q "is a function";echo $?)
}


print_name() {
    echo -e "[${__NAME__}]"
}

log() {
    echo -e "${RED}$(print_name) ${@}${NORMAL}" 1>&2
}

cyan_log() {
    echo -e "${CYAN}${@}${NORMAL}" 1>&2
}

die_() {
    ret="${1}"
    shift
    cyan_log "ABRUPT PROGRAM TERMINATION: ${@}"
    do_hook "FAILURE command output" "failure_hook"
    exit ${ret}
}

die() {
    die_ 1 "${@}"
}

die_in_error_() {
    ret="${1}"
    shift
    msg="${@:-"${ERROR_MSG}"}"
    if [ x"${ret}" != "x0" ];then
        die_ "${ret}" "${msg}"
    fi
}

die_in_error() {
    die_in_error_ "$?" "${@}"
}

yellow_log(){
    echo -e "${YELLOW}$(print_name) ${@}${NORMAL}" 1>&2
}

readable_date() {
    date +"%Y-%m-%d %H:%M:%S.%N"
}

debug() {
    if [ x"${DSB_DEBUG}" != "x" ];then
        yellow_log "DEBUG $(readable_date): $@"
    fi
}

usage() {
    cyan_log "- Backup your databases with ease"
    yellow_log "  $0"
    yellow_log "     /path/toconfig"
    yellow_log "        alias to --backup"
    yellow_log "     -b|--backup /path/toconfig:"
    yellow_log "        backup databases"
    yellow_log "     --gen-config [/path/toconfig (default: ${DSB_CONF_FILE}_DEFAULT)]"
    yellow_log "        generate a new config file]"
}

runas() {
    echo "${RUNAS:-"$(whoami)"}"
}

quote_all() {
    cmd=""
    for i in "${@}";do
        cmd="${cmd} \"$(echo "${i}"|sed "s/\"/\"\'\"/g")\""
    done
    echo "${cmd}"
}

runcmd_as() {
    cd "${RUNAS_DIR:-/}"
    bin="${1}"
    shift
    args=$(quote_all "${@}")
    if [ x"$(runas)" = "x" ] || [ x"$(runas)" = "x$(whoami)" ];then
        ${bin} "${@}"
    else
        su ${RUNAS} -c "${bin} ${args}"
    fi
}

get_compressed_name() {
    if [ x"${COMP}" = "xxz" ];then
        echo "${1}.xz";
    elif [ x"${COMP}" = "xgz" ] || [ x"${COMP}" = "xgzip" ];then
        echo "${1}.gz";
    elif [ x"${COMP}" = "xbzip2" ] || [ x"${COMP}" = "xbz2" ];then
        echo "${1}.bz2";
    else
        echo "${1}";
    fi
}

set_compressor() {
    for comp in ${COMP} ${COMPS};do
        c=""
        if [ x"${COMP}" = "xxz" ];then
            XZ="${XZ:-xz}"
            c="${XZ}"
        elif [ x"${COMP}" = "xgz" ] || [ x"${COMP}" = "xgzip" ];then
            GZIP="${GZIP:-gzip}"
            c="${GZIP}"
        elif [ x"${COMP}" = "xbzip2" ] || [ x"${COMP}" = "xbz2" ];then
            BZIP2="${BZIP2:-bzip2}"
            c="${BZIP2}"
        else
            c="nocomp"
        fi
        # test that the binary is present
        if [ x"$c" != "xnocomp" ] && [ -e "$(which "$c")" ];then
            break
        else
            COMP="nocomp"
        fi
    done
}

comp_msg() {
    sz="$(du -sh "$zname"|awk '{print $1}') "
    s1="$(du -sb "$zname"|awk '{print $1}')"
    s2="$(du -sb "$name"|awk '{print $1}')"
    ratio=$(echo "$s1" "${s2}" | awk '{printf "%.2f \n", $1/$2}')
    log "${RED}${NORMAL}${YELLOW} ${COMP}${NORMAL}${RED} -> ${YELLOW}${zname}${NORMAL} ${RED}(${NORMAL}${YELLOW} ${sz} ${NORMAL}${RED}/${NORMAL} ${YELLOW}${ratio}${NORMAL}${RED})${NORMAL}"
}


cleanup_uncompressed_dump_if_ok() {
    comp_msg
    if [ x"$?" = x"0" ];then
        rm -f "$name"
    fi
}

do_compression() {
    COMPRESSED_NAME=""
    name="${1}"
    zname="${2:-$(get_compressed_name ${1})}"
    if [ x"${COMP}" = "xxz" ];then
        "${XZ}" --stdout -f -k "${name}" > "${zname}"
        cleanup_uncompressed_dump_if_ok
    elif [ x"${COMP}" = "xgz" ] || [ x"${COMP}" = "xgzip" ];then
        "${GZIP}" -f -c "${name}" > "${zname}"
        cleanup_uncompressed_dump_if_ok
    elif [ x"${COMP}" = "xbzip2" ] || [ x"${COMP}" = "xbz2" ];then
        "${BZIP2}" -f -k -c "${name}" > "${zname}"
        cleanup_uncompressed_dump_if_ok
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
    if [ x"${COMPRESSED_NAME}" != "x" ];then
        fix_perm "${fic}"
    fi
}

get_backupdir() {
    dir="${TOP_BACKUPDIR}/${BACKUP_TYPE:-}"
    if [  x"${BACKUP_TYPE}" = "xpostgresql" ];then
        host="${HOST}"
        if [ x"${HOST}" = "x" ] || [ x"${PGHOST}" = "x" ];then
            host="localhost"
        fi
        if [ -e $host ];then
            host="localhost"
        fi
        dir="$dir/$host"
    fi
    echo "$dir"
}

create_db_directories() {
    db="${1}"
    dbdir="$(get_backupdir)/${db}"
    created="0"
    for d in\
        "$dbdir"\
        "$dbdir/weekly"\
        "$dbdir/monthly"\
        "$dbdir/dumps"\
        "$dbdir/daily"\
        "$dbdir/lastsnapshots"\
        ;do
        if [ ! -e "$d" ];then
            mkdir -p "$d"
            created="1"
        fi
    done
    if [ x"${created}" = "x1" ];then
        fix_perms
    fi
}

link_into_dirs() {
    db="${1}"
    real_filename="${2}"
    real_zfilename="$(get_compressed_name "${real_filename}")"
    daily_filename="$(get_backupdir)/${db}/daily/${db}_${YEAR}_${DOY}_${DATE}.${BACKUP_EXT}"
    lastsnapshots_filename="$(get_backupdir)/${db}/lastsnapshots/${db}_${YEAR}_${DOY}_${FDATE}.${BACKUP_EXT}"
    weekly_filename="$(get_backupdir)/${db}/weekly/${db}_${YEAR}_${W}.${BACKUP_EXT}"
    monthly_filename="$(get_backupdir)/${db}/monthly/${db}_${YEAR}_${MNUM}.${BACKUP_EXT}"
    lastsnapshots_zfilename="$(get_compressed_name "${lastsnapshots_filename}")"
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
    if [ ! -e "${lastsnapshots_zfilename}" ];then
        ln "${real_zfilename}" "${lastsnapshots_zfilename}"
    fi
}

dummy_callee_for_tests() {
    echo "here"
}

dummy_for_tests() {
    dummy_callee_for_tests
}

do_db_backup_() {
    LAST_BACKUP_STATUS=""
    db="${1}"
    fun_="${2}"
    create_db_directories "${db}"
    real_filename="$(get_backupdir)/${db}/dumps/${db}_${FDATE}.${BACKUP_EXT}"
    zreal_filename="$(get_compressed_name "${real_filename}")"
    adb="${YELLOW}${db}${NORMAL} "
    if [ x"${db}" = x"${GLOBAL_SUBDIR}" ];then
        adb=""
    fi
    log "Dumping database ${adb}${RED}to maybe uncompressed dump: ${YELLOW}${real_filename}${NORMAL}"
    $fun_ "${db}" "${real_filename}"
    if [ x"$?" != "x0" ];then
        LAST_BACKUP_STATUS="failure"
        log "${CYAN}    Backup of ${db} failed !!!${NORMAL}"
    else
        do_compression "${real_filename}" "${zreal_filename}"
        link_into_dirs "${db}" "${real_filename}"
    fi
}

do_db_backup() {
    db="`echo ${1} | sed 's/%/ /g'`"
    fun_="${BACKUP_TYPE}_dump"
    do_db_backup_ "${db}" "$fun_"
}

do_global_backup() {
    db="$GLOBAL_SUBDIR"
    fun_="${BACKUP_TYPE}_dumpall"
    log_rule
    log "GLOBAL BACKUP"
    log_rule
    do_db_backup_ "${db}" "$fun_"
}

activate_IO_redirection() {
    if [ x"${DSB_ACTITED_RIO}" = x"" ];then
        DSB_ACTITED_RIO="1"
        if [ ! -e "${DSB_LOGDIR}" ];then
            mkdir -p "${DSB_LOGDIR}"
        fi
        touch "${DSB_LOGFILE}"
        exec 1> >(tee -a "${DSB_LOGFILE}") 2>&1
    fi
}


deactivate_IO_redirection() {
    if [ x"${DSB_ACTITED_RIO}" != x"" ];then
        DSB_ACTITED_RIO=""
        exec 1>&1  # Restore stdout and close file descriptor #6.
        exec 2>&2  # Restore stdout and close file descriptor #7.
    fi
}

do_pre_backup() {
    debug "do_pre_backup"
    # IO redirection for logging.
    if [ x"$COMP" = "xnocomp" ];then
        comp_msg="No compression"
    else
        comp_msg="${COMP}"
    fi
    # If backing up all DBs on the server
    log_rule
    log "DB_SMART_BACKUP by kiorky@cryptelium.net / http://www.makina-corpus.com"
    log "Conf: ${YELLOW}'${DSB_CONF_FILE}'"
    log "Log: ${YELLOW}'${DSB_LOGFILE}'"
    log "Backup Start Time: ${YELLOW}$(readable_date)${NORMAL}"
    log "Backup of database compression://type@server: ${YELLOW}${comp_msg}://${BACKUP_TYPE}@${HOST}${NORMAL}"
    log_rule
}


fix_perm() {
    fic="${1}"
    if [ -e "${fic}" ];then
        if [ -d "${fic}" ];then
            perm="${DPERM:-750}"
        elif [ -f "${fic}" ];then
            perm="${FPERM:-640}"
        fi
        chown ${OWNER:-"root"}:${GROUP:-"root"} "${fic}"
        chmod -f $perm "${fic}"
    fi
}

fix_perms() {
    debug "fix_perms"
    find  "${TOP_BACKUPDIR}" -type d -print|\
        while read fic
        do
            fix_perm "${fic}"
        done
    find  "${TOP_BACKUPDIR}" -type f -print|\
        while read fic
        do
            fix_perm "${fic}"
        done
}


wrap_log() {
    echo -e "$("$@"|sed "s/^/$(echo -e "${NORMAL}${RED}")$(print_name)     $(echo -e "${NORMAL}${YELLOW}")/g"|sed "s/\t/    /g"|sed "s/  +/   /g")${NORMAL}"
}

do_post_backup() {
    # Run command when we're done
    log_rule
    debug "do_post_backup"
    log "Total disk space used for backup storage.."
    log "  Size   - Location:"
    wrap_log du -shc "$(get_backupdir)"/*
    log_rule
    log "Backup end time: ${YELLOW}$(readable_date)${NORMAL}"
    log_rule
    deactivate_IO_redirection
    sanitize_log
}

sanitize_log() {
    sed -i -e "s/\x1B\[[0-9;]*[JKmsu]//g" "${DSB_LOGFILE}"
}

get_sorted_files() {
    files="$(ls -1 "${1}" 2>/dev/null)"
    sep="____----____----____"
    echo -e "${files}"|while read fic;do
        key=""
        oldkey="${fic}"
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
    log_rule
    debug "rotate"
    log "Execute backup rotation policy, keep"
    log "   -  logs           : ${YELLOW}${KEEP_LOGS}${NORMAL}"
    log "   -  last snapshots : ${YELLOW}${KEEP_LASTS}${NORMAL}"
    log "   -  daily dumps    : ${YELLOW}${KEEP_DAYS}${NORMAL}"
    log "   -  weekly dumpss  : ${YELLOW}${KEEP_WEEKS}${NORMAL}"
    log "   -  monthly dumps  : ${YELLOW}${KEEP_MONTHES}${NORMAL}"
    # ./TOPDIR/POSTGRESQL/HOSTNAME
    # or ./TOPDIR/logs for logs
    KEEP_LOGS=2
    ls -1d "${TOP_BACKUPDIR}" "$(get_backupdir)"/*|while read nsubdir;do
        # ./TOPDIR/HOSTNAME/DBNAME/${monthly,weekly,daily,dumps}
        suf=""
        if [ x"$nsubdir" = "x${TOP_BACKUPDIR}" ];then
            subdirs="logs"
            suf="/logs"
        else
            subdirs="monthly weekly daily lastsnapshots"
        fi
        log "   - Operating in: ${YELLOW}'${nsubdir}${suf}'${NORMAL}"
        for chronodir in ${subdirs};do
            subdir="${nsubdir}/${chronodir}"
            if [ -d "${subdir}" ];then
                if [ x"${chronodir}" = "xlogs" ];then
                    to_keep=${KEEP_LOGS:-2}
                elif [ x"${chronodir}" = "xweekly" ];then
                    to_keep=${KEEP_WEEKS:-2}
                elif [ x"${chronodir}" = "xmonthly" ];then
                    to_keep=${KEEP_MONTHES:-2}
                elif [ x"${chronodir}" = "xdaily" ];then
                    to_keep=${KEEP_DAYS:-2}
                elif [ x"${chronodir}" = "xlastsnapshots" ];then
                    to_keep=${KEEP_LASTS:-2}
                else
                    to_keep="65535" # int limit
                fi
                i=0
                get_sorted_files "${subdir}" | while read nfic;do
                    dfic="${subdir}/${nfic}"
                    i="$((${i}+1))"
                    if [ "${i}" -gt "${to_keep}" ] &&\
                        [ -e "${dfic}" ] &&\
                        [ ! -d ${dfic} ];then
                        log "       * Unlinking ${YELLOW}${dfic}${NORMAL}"
                        rm "${dfic}"
                    fi
                done
            fi
        done
    done
}

log_rule() {
    log "======================================================================"
}

handle_hook_error() {
    debug "handle_hook_error"
    log "Unexpected exit of ${HOOK_CMD} hook, you should never issue an exit in a hook"
    log_rule
    DSB_RETURN_CODE="1"
    handle_exit
}

do_prune() {
    do_rotate
    do_hook "Postrotate command output" "post_rotate_hook"
    do_cleanup_orphans
    do_hook "Postcleanup command output" "post_cleanup_hook"
    fix_perms
    do_post_backup
    do_hook "Postbackup command output" "post_backup_hook"
}

handle_exit() {
    DSB_RETURN_CODE="${DSB_RETURN_CODE:-$?}"
    if [ x"${DSB_BACKUP_STARTED}" != "x" ];then
        debug "handle_exit"
        DSB_HOOK_NO_TRAP="1"
        do_prune
        if [ x"$DSB_RETURN_CODE" != "x0" ];then
            log "WARNING, this script did not behaved correctly, check the log: ${DSB_LOGFILE}"
        fi
        if [ x"${DSB_GLOBAL_BACKUP_IN_FAILURE}" != x"" ];then
            cyan_log "Global backup failed, check the log: ${DSB_LOGFILE}"
            DSB_RETURN_CODE="${DSB_BACKUP_FAILED}"
        fi
        if [ x"${DSB_BACKUP_IN_FAILURE}" != x"" ];then
            cyan_log "One of the databases backup failed, check the log: ${DSB_LOGFILE}"
            DSB_RETURN_CODE="${DSB_BACKUP_FAILED}"
        fi
    fi
    exit "${DSB_RETURN_CODE}"
}

do_trap() {
    debug "do_trap"
	trap handle_exit      EXIT SIGHUP SIGINT SIGQUIT SIGTERM
}

do_cleanup_orphans() {
    log_rule
    debug "do_cleanup_orphans"
    log "Cleaning orphaned dumps:"
    # prune all files in dumps dirs which have no more any
    # hardlinks in chronoted directories (weekly, monthly, daily)
    find "$(get_backupdir)" -type f -links 1 -print 2>/dev/null|\
        while read fic
        do
            log "       * Pruning ${YELLOW}${fic}${NORMAL}"
            rm -f "${fic}"
        done
}

do_hook() {
    HOOK_HEADER="${1}"
    HOOK_CMD="${2}"
    if [ x"${DSB_HOOK_NO_TRAP}" = "x" ];then
        trap handle_hook_error EXIT SIGHUP SIGINT SIGQUIT SIGTERM
    fi
    if [ x"$(fn_exists ${HOOK_CMD})" = "x0" ];then
        debug "do_hook ${HOOK_CMD}"
        log_rule
        log "HOOK: ${YELLOW} ${HOOK_HEADER}"
        "${HOOK_CMD}"
        log_rule
        log ""
    fi
    if [ x"${DSB_HOOK_NO_TRAP}" = "x" ];then
        trap handle_exit EXIT SIGHUP SIGINT SIGQUIT SIGTERM
    fi
}

do_backup() {
    debug "do_backup"
    if [ x"${BACKUP_TYPE}" = "x" ];then
        die "No backup type, choose between mysql,postgresql,redis,mongodb,slapd,es"
    fi
    # if either the source failed or we do not have a configuration file, bail out
    die_in_error "Invalid configuration file: ${DSB_CONF_FILE}"
    DSB_BACKUP_STARTED="y"
    do_pre_backup
    do_hook "Prebackup command output" "pre_backup_hook"
    if [ x"${DO_GLOBAL_BACKUP}" != "x" ];then
        do_global_backup
        if [ x"${LAST_BACKUP_STATUS}" = "xfailure" ];then
            do_hook "Postglobalbackup command output" "post_global_backup_hook"
            DSB_GLOBAL_BACKUP_IN_FAILURE="y"
        else
            do_hook "Postglobalbackup(failure) command output" "post_global_backup_failure_hook"
        fi
    fi
    if [ "x${BACKUP_DB_NAMES}" != "x" ];then
        log_rule
        log "DATABASES BACKUP"
        log_rule
        for db in ${BACKUP_DB_NAMES};do
            do_db_backup $db
            if [ x"${LAST_BACKUP_STATUS}" = "xfailure" ];then
                do_hook "Postdbbackup: ${db}  command output" "post_db_backup_hook"
                DSB_BACKUP_IN_FAILURE="y"
            else
                do_hook "Postdbbackup: ${db}(failure)  command output" "post_db_backup_failure_hook"
            fi
        done
    fi
}

mark_run_rotate() {
    DSB_CONF_FILE="${1}"
    DO_PRUNE="1"
}

mark_run_backup() {
    DSB_CONF_FILE="${1}"
    DO_BACKUP="1"
}

verify_backup_type() {
    for typ_ in _dump _dumpall;do
        if [ x"$(fn_exists ${BACKUP_TYPE}${typ_})" != "x0" ];then
            die "Please provide a ${BACKUP_TYPE}${typ_} export function"
        fi
    done
}

db_user() {
    echo "${DBUSER:-${RUNAS:-$(whoami)}}"
}

set_colors() {
    YELLOW="\e[1;33m"
    RED="\\033[31m"
    CYAN="\\033[36m"
    NORMAL="\\033[0m"
    if [ x"$NO_COLOR" != "x" ] || [ x"$NOCOLOR" != "x" ] || [ x"$NO_COLORS" != "x" ] || [ x"$NOCOLORS" != "x" ];then
        YELLOW=""
        RED=""
        CYAN=""
        NORMAL=""
    fi
}

set_vars() {
    debug "set_vars"
    args=${@}
    set_colors
    PARAM=""
    DSB_CONF_FILE_DEFAULT="/etc/db_smartbackup.conf.sh"
    parsable_args="$(echo "${@}"|sed "s/^--//g")"
    if [ x"${parsable_args}" = "x" ];then
        USAGE="1"
    fi
    if [ -e "${parsable_args}" ];then
        mark_run_backup ${1}
    else
        while true
        do
            sh="1"
            if [ x"${1}" = "x$PARAM" ];then
                break
            fi
            if [ x"${1}" = "x--gen-config" ];then
                DSB_GENERATE_CONFIG="1"
                DSB_CONF_FILE="${2:-${DSB_CONF_FILE_DEFAULT}}"
                sh="2"
            elif [ x"${1}" = "x-p" ] || [ x"${1}" = "x--prune" ];then
                mark_run_rotate ${2};sh="2"
            elif [ x"${1}" = "x-b" ] || [ x"${1}" = "x--backup" ];then
                mark_run_backup ${2};sh="2"
            else
                if [ x"${DB_SMART_BACKUP_AS_FUNCS}" = "x" ];then
                    usage
                    die "Invalid invocation"
                fi
            fi
            PARAM="${1}"
            OLD_ARG="${1}"
            for i in $(seq $sh);do
                shift
                if [ x"${1}" = "x${OLD_ARG}" ];then
                    break
                fi
            done
            if [ x"${1}" = "x" ];then
                break
            fi
        done
    fi

    ######## Backup settings
    NO_COLOR="${NO_COLOR:-}"
    COMP=${COMP:-xz}
    BACKUP_TYPE=${BACKUP_TYPE:-}
    TOP_BACKUPDIR="${TOP_BACKUPDIR:-/var/db_smart_backup}"
    DEFAULT_DO_GLOBAL_BACKUP="1"
    if [ "x${BACKUP_TYPE}" = "xes" ];then
        DEFAULT_DO_GLOBAL_BACKUP=""
    fi
    DO_GLOBAL_BACKUP="${DO_GLOBAL_BACKUP-${DEFAULT_DO_GLOBAL_BACKUP}}"
    KEEP_LASTS="${KEEP_LASTS:-24}"
    KEEP_DAYS="${KEEP_DAYS:-14}"
    KEEP_WEEKS="${KEEP_WEEKS:-8}"
    KEEP_MONTHES="${KEEP_MONTHES:-12}"
    KEEP_LOGS="${KEEP_LOGS:-60}"
    DPERM="${DPERM:-"750"}"
    FPERM="${FPERM:-"640"}"
    OWNER="${OWNER:-"root"}"
    GROUP="${GROUP:-"root"}"

    ######## Database connection settings
    HOST="${HOST:-localhost}"
    PORT="${PORT:-}"
    RUNAS="" # see runas function
    DBUSER="" # see db_user function
    PASSWORD="${PASSWORD:-}"
    DBNAMES="${DBNAMES:-all}"
    DBEXCLUDE="${DBEXCLUDE:-}"

    ######## hostname
    GET_HOSTNAME=`hostname -f`
    if [ x"${GET_HOSTNAME}" = x"" ]; then
        GET_HOSTNAME=`hostname -s`
    fi

    ######## Mail setup
    MAILCONTENT="${MAILCONTENT:-stdout}"
    MAXATTSIZE="${MAXATTSIZE:-4000}"
    MAILADDR="${MAILADDR:-root@localhost}"

    MAIL_SERVERNAME="${MAIL_SERVERNAME:-${GET_HOSTNAME}}"

    ######### Postgresql
    PSQL="${PSQL:-"$(which psql 2>/dev/null)"}"
    PG_DUMP="${PG_DUMP:-"$(which pg_dump 2>/dev/null)"}"
    PG_DUMPALL="${PG_DUMPALL:-"$(which pg_dumpall 2>/dev/null)"}"
    OPT="${OPT:-"--create -Fc"}"
    OPTALL="${OPTALL:-"--globals-only"}"

    ######### MYSQL
    MYSQL_USE_SSL="${MYSQL_USE_SSL:-}"
    MYSQL_SOCK_PATHS="${MYSQL_SOCK_PATHS:-"/var/run/mysqld/mysqld.sock"}"
    MYSQL="${MYSQL:-$(which mysql 2>/dev/null)}"
    MYSQLDUMP="${MYSQLDUMP:-$(which mysqldump 2>/dev/null)}"
    MYSQLDUMP_NO_SINGLE_TRANSACTION="${MYSQLDUMP_NO_SINGLE_TRANSACTION:-}"
    MYSQLDUMP_AUTOCOMMIT="${MYSQLDUMP_AUTOCOMMIT:-1}"
    MYSQLDUMP_COMPLETEINSERTS="${MYSQLDUMP_COMPLETEINSERTS:-1}"
    MYSQLDUMP_LOCKTABLES="${MYSQLDUMP_LOCKTABLES:-}"
    MYSQLDUMP_DEBUG="${MYSQLDUMP_DEBUG:-}"
    MYSQLDUMP_NOROUTINES="${MYSQLDUMP_NOROUTINES:-}"
    # mongodb
    MONGODB_PATH="${MONGODB_PATH:-"/var/lib/mongodb"}"
    MONGODB_USER="${MONGODB_USER:-""}"
    MONGODB_PASSWORD="${MONGODB_PASSWORD:-""}"
    MONGODB_ARGS="${MONGODB_ARGS:-""}"
    # slapd
    SLAPCAT_ARGS="${SLAPCAT_ARGS:-""}"
    SLAPD_DIR="${SLAPD_DIR:-/var/lib/ldap}"

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
    FDATE=`date +%Y-%m-%d_%H-%M-%S` # Datestamp e.g 2002-09-21
    FULL_FDATE=`date +%Y-%m-%d_%H-%M-%S.%N` # Datestamp e.g 2002-09-21
    DOY=`date +%j`  # Day of the YEAR 0..366
    DOW=`date +%A`  # Day of the week e.g. Monday
    DNOW=`date +%u` # Day number of the week 1 to 7 where 1 represents Monday
    DOM=`date +%d`  # Date of the Month e.g. 27
    M=`date +%B`    # Month e.g January
    YEAR=`date +%Y` # Datestamp e.g 2002-09-21
    MNUM=`date +%m` # Month e.g 1
    W=`date +%V`    # Week Number e.g 37
    DSB_LOGDIR="${TOP_BACKUPDIR}/logs"
    DSB_LOGFILE="${DSB_LOGDIR}/${__NAME__}_${FULL_FDATE}.log"    # Logfile Name
    DSB_BACKUPFILES="" # thh: added for later mailing
    DSB_RETURN_CODE=""
    DSB_GLOBAL_BACKUP_FAILED="3"
    DSB_BACKUP_FAILED="4"

    activate_IO_redirection
    # source conf file if any
    if [ -e "${DSB_CONF_FILE}" ];then
        . "${DSB_CONF_FILE}"
    fi
    set_compressor

    if [ x"${BACKUP_TYPE}" != "x" ];then
        verify_backup_type
        if [ x"$(fn_exists "${BACKUP_TYPE}_set_connection_vars")" = "x0" ];then
            "${BACKUP_TYPE}_set_connection_vars"
        fi
        "${BACKUP_TYPE}_check_connectivity"
        if [ x"$(fn_exists "${BACKUP_TYPE}_get_all_databases")" = "x0" ];then
            ALL_DBNAMES="$(${BACKUP_TYPE}_get_all_databases)"
        fi
        if [ x"$(fn_exists "${BACKUP_TYPE}_set_vars")" = "x0" ];then
            "${BACKUP_TYPE}_set_vars"
        fi
    fi
    if [ "x${BACKUP_TYPE}" = "xmongodb" ]\
       || [ "x${BACKUP_TYPE}" = "xes" ]\
       || [ "x${BACKUP_TYPE}" = "xredis" ];then
        BACKUP_EXT="tar"
    elif [ "x${BACKUP_TYPE}" = "xslapd" ];then
        BACKUP_EXT="ldif"
    else
        BACKUP_EXT="sql"
    fi

    BACKUP_DB_NAMES="${DBNAMES}"
    # Re source to reoverride any core overriden variable
    if [ -e "${DSB_CONF_FILE}" ];then
        . "${DSB_CONF_FILE}"
    fi
}

do_main() {
    if [ x"${1#--/}" = "x" ];then
        set_colors
        usage
        exit 0
    else
        do_trap
        set_vars "${@}"
        if [ x"${1#--/}" = "x" ];then
            usage
            exit 0
        elif [ x"${DSB_GENERATE_CONFIG}" != "x" ];then
            generate_configuration_file
            die_in_error "end_of_scripts"
        elif [ "x${DO_BACKUP}" != "x" ] || [ "x${DO_PRUNE}" != "x" ] ;then
            if [ -e "${DSB_CONF_FILE}" ];then
                if [ "x${DO_PRUNE}" != "x" ];then
                    func=do_prune
                else
                    func=do_backup
                fi
                ${func}
                die_in_error "end_of_scripts"
            else
                cyan_log "Missing or invalid configuration file: ${DSB_CONF_FILE}"
                exit 1
            fi
        fi
    fi
}

#################### POSTGRESQL
pg_dumpall_() {
    runcmd_as "${PG_DUMPALL}" "${@}"
}

pg_dump_() {
    runcmd_as "${PG_DUMP}" "${@}"
}

psql_() {
    runcmd_as "${PSQL}" -w "${@}"
}

# REAL API IS HERE
postgresql_set_connection_vars() {
    export RUNAS="${RUNAS:-postgres}"
    export PGHOST="${HOST}"
    export PGPORT="${PORT}"
    export PGUSER="$(db_user)"
    export PGPASSWORD="${PASSWORD}"
    if [ x"${PGHOST}" = "xlocalhost" ]; then
        PGHOST=
    fi
}

postgresql_set_vars() {
    if [ x"${DBNAMES}" = "xall" ]; then
        DBNAMES=${ALL_DBNAMES}
        if [ " ${DBEXCLUDE#*" template0 "*} " != " $DBEXCLUDE " ];then
            DBEXCLUDE="${DBEXCLUDE} template0"
        fi
        for exclude in ${DBEXCLUDE};do
            DBNAMES=$(echo ${DBNAMES} | sed "s/\b${exclude}\b//g")
        done
    fi
    if [ x"${DBNAMES}" = "xall" ]; then
        die "${BACKUP_TYPE}: could not get all databases"
    fi
    for i in "psql::${PSQL}" "pg_dumpall::${PG_DUMPALL}" "pg_dump::${PG_DUMP}";do
        var="$(echo ${i}|awk -F:: '{print $1}')"
        bin="$(echo ${i}|awk -F:: '{print $2}')"
        if  [ ! -e "${bin}" ];then
            die "missing ${var}"
        fi
    done
}

postgresql_check_connectivity() {
    who="$(whoami)"
    pgu="$(db_user)"
    psql_ --username="$(db_user)" -c "select * from pg_roles" -d postgres >/dev/null
    die_in_error "Cant connect to postgresql server with ${pgu} as ${who}, did you configured \$RUNAS("$(runas)") in $DSB_CONF_FILE"
}

postgresql_get_all_databases() {
    LANG=C LC_ALL=C psql_ --username="$(db_user)"  -l -A -F: | sed -ne "/:/ { /Name:Owner/d; /template0/d; s/:.*$//; p }"
}

postgresql_dumpall() {
    pg_dumpall_ --username="$(db_user)" $OPTALL > "${2}"
}

postgresql_dump() {
    pg_dump_ --username="$(db_user)" $OPT "${1}" > "${2}"
}

#################### MYSQL
# REAL API IS HERE
mysql__() {
    runcmd_as "${MYSQL}"    $(mysql_common_args) "${@}"
}

mysqldump__() {
    runcmd_as "${MYSQLDUMP}" $(mysql_common_args) "${@}"
}

mysqldump_() {
    mysqldump__ "-u$(db_user)" "$@"
}

mysql_() {
    mysql__ "-u$(db_user)" "$@"
}

mysql_set_connection_vars() {
    export MYSQL_HOST="${HOST:-localhost}"
    export MYSQL_TCP_PORT="${PORT:-3306}"
    export MYSQL_PWD="${PASSWORD}"
    if [ x"${MYSQL_HOST}" = "xlocalhost" ];then
        mkfifo tmppipe
        printf "${MYSQL_SOCK_PATHS}\n\n" > tmppipe &
        while read path
        do
            if [ "x${path}" != "x" ]; then
                export MYSQL_HOST="127.0.0.1"
                export MYSQL_UNIX_PORT="${path}"
            fi
        done < tmppipe
        rm tmppipe
    fi
    if [ -e "${MYSQL_UNIX_PORT}" ];then
        log "Using mysql socket: ${path}"
    fi
}

mysql_set_vars() {
    if [ x"${MYSQLDUMP_AUTOCOMMIT}" = x"" ];then
        MYSQLDUMP_OPTS_COMMON="${MYSQLDUMP_OPTS_COMMON} --no-autocommit"
    fi
    if [ x"${MYSQLDUMP_NO_SINGLE_TRANSACTION}" = x"" ];then
        MYSQLDUMP_OPTS_COMMON="${MYSQLDUMP_OPTS_COMMON} --single-transaction"
    fi
    if [ x"${MYSQLDUMP_COMPLETEINSERTS}" != x"" ];then
        MYSQLDUMP_OPTS_COMMON="${MYSQLDUMP_OPTS_COMMON} --complete-insert"
    else
        MYSQLDUMP_OPTS_COMMON="${MYSQLDUMP_OPTS_COMMON} --extended-insert"
    fi
    if [ x"${MYSQLDUMP_LOCKTABLES}" = x"" ];then
        MYSQLDUMP_OPTS_COMMON="${MYSQLDUMP_OPTS_COMMON} --lock-tables=false"
    fi
    if [ x"${MYSQLDUMP_DEBUG}" != x"" ];then
        MYSQLDUMP_OPTS_COMMON="${MYSQLDUMP_OPTS_COMMON} --debug-info"
    fi
    if [ x"${MYSQLDUMP_NOROUTINES}" = x"" ];then
        MYSQLDUMP_OPTS_COMMON="${MYSQLDUMP_OPTS_COMMON} --routines"
    fi
    MYSQLDUMP_OPTS_COMMON="${MYSQLDUMP_OPTS_COMMON} --quote-names --opt"
    MYSQLDUMP_OPTS="${MYSQLDUMP_OPTS:-"${MYSQLDUMP_OPTS_COMMON}"}"
    MYSQLDUMP_ALL_OPTS="${MYSQLDUMP_ALL_OPTS:-"${MYSQLDUMP_OPTS_COMMON} --all-databases --no-data"}"
    if [ x"${DBNAMES}" = "xall" ]; then
        DBNAMES=${ALL_DBNAMES}
        for exclude in ${DBEXCLUDE};do
            DBNAMES=$(echo ${DBNAMES} | sed "s/\b${exclude}\b//g")
        done
    fi
    if [ x"${DBNAMES}" = "xall" ]; then
        die "${BACKUP_TYPE}: could not get all databases"
    fi
    for i in "mysql::${MYSQL}" "mysqldump::${MYSQLDUMP}";do
        var="$(echo ${i}|awk -F:: '{print $1}')"
        bin="$(echo ${i}|awk -F:: '{print $2}')"
        if  [ ! -e "${bin}" ];then
            die "missing ${var}"
        fi
    done
}

mysql_common_args() {
    args=""
    if [ x"${MYSQL_USE_SSL}" ];then
        args="${args} --ssl"
    fi
    echo "${args}"
}

mysql_check_connectivity() {
    who="$(whoami)"
    pgu="$(db_user)"
    echo "select 1"|mysql_ information_schema&> /dev/null
    die_in_error "Cant connect to mysql server with ${pgu} as ${who}, did you configured \$RUNAS \$PASSWORD \$DBUSER in $DSB_CONF_FILE"
}

mysql_get_all_databases() {
    echo "select schema_name from SCHEMATA;"|mysql_ -N information_schema 2>/dev/null
    die_in_error "Could not get mysql databases"
}

mysql_dumpall() {
    mysqldump_ ${MYSQLDUMP_ALL_OPTS} 2>&1 > "${2}"
}

mysql_dump() {
    mysqldump_ ${MYSQLDUMP_OPTS} -B "${1}" > "${2}"
}


#################### MONGODB
# REAL API IS HERE
mongodb_set_connection_vars() {
    /bin/true
}

mongodb_set_vars() {
    DBNAMES=""
}

mongodb_check_connectivity() {
    test -d "${MONGODB_PATH}/journal"
    die_in_error "no mongodb"
}

mongodb_get_all_databases() {
    /bin/true
}

mongodb_dumpall() {
    DUMPDIR="${2}.dir"
    if [ ! -e ${DUMPDIR} ];then
        mkdir -p "${DUMPDIR}"
    fi
    if [ "x${MONGODB_PASSWORD}"  != "x" ];then
        MONGODB_ARGS="$MONGODB_ARGS -p $MONGODB_PASSWORD"
    fi
    if [ "x${MONGODB_USER}"  != "x" ];then
        MONGODB_ARGS="$MONGODB_ARGS -u $MONGODB_USER"
    fi
    mongodump ${MONGODB_ARGS} --out "${DUMPDIR}"\
        && die_in_error "mongodb dump failed"
    cd "${DUMPDIR}" &&  tar cf "${2}" .
    die_in_error "mongodb tar failed"
    rm -rf "${DUMPDIR}"
}

mongodb_dump() {
    /bin/true
}

#################### redis
# REAL API IS HERE
redis_set_connection_vars() {
    /bin/true
}

redis_set_vars() {
    DBNAMES=""
    export REDIS_PATH="${REDIS_PATH:-"/var/lib/redis"}"
}

redis_check_connectivity() {
    if [ ! -e "${REDIS_PATH}" ];then
        die_in_error "no redis dir"
    fi
    if [ "x${REDIS_PATH}" != "x" ];then
        die_in_error "redis dir is not set"
    fi
    if [ "x$(ls -1 "${REDIS_PATH}"|wc -l|sed -e"s/ //g")" = "x0" ];then
        die_in_error "no redis rdbs in ${REDIS_PATH}"
    fi
}

redis_get_all_databases() {
    /bin/true
}

redis_dumpall() {
    BCK_DIR="$(dirname ${2})"
    if [ ! -e "${BCK_DIR}" ];then
        mkdir -p "${BCK_DIR}"
    fi
    c="${PWD}"
    cd "${REDIS_PATH}" && tar cf "${2}" . && cd "${c}"
    die_in_error "redis $2 dump failed"
}

redis_dump() {
    /bin/true
}

#################### slapd
# REAL API IS HERE
slapd_set_connection_vars() {
    /bin/true
}

slapd_set_vars() {
    DBNAMES=""
}

slapd_check_connectivity() {
    if [ ! -e ${SLAPD_DIR} ];then
        die_in_error "no slapd dir"
    fi
    if [ "x$(ls -1 "${SLAPD_DIR}"|wc -l|sed -e"s/ //g")" = "x0" ];then
        die_in_error "no slapd db in ${SLAPD_DIR}"
    fi
}

slapd_get_all_databases() {
    /bin/true
}

slapd_dumpall() {
    BCK_DIR="$(dirname ${2})"
    if [ ! -e "${BCK_DIR}" ];then
        mkdir -p "${BCK_DIR}"
    fi
    slapcat ${SLAPCAT_ARGS} > "${2}"
    die_in_error "slapd $2 dump failed"
}

slapd_dump() {
    /bin/true
}

# ELASTICSEARCH
es_set_connection_vars() {
    if [ "x${ES_URI}" = "x" ];then
        export ES_URI="http://localhost:9200"
    fi
    export ES_USER="${ES_USER}"
    export ES_PASSWORD="${ES_PASSWORD}"
}

es_set_vars() {
    export BACKUP_DB_NAMES="${BACKUP_DB_NAMES:-${DBNAMES}}"
    if [ x"${DBNAMES}" = "xall" ]; then
        DBNAMES=${ALL_DBNAMES}
        for exclude in ${DBEXCLUDE};do
            DBNAMES=$(echo ${DBNAMES} | sed "s/\b${exclude}\b//g")
        done
    fi
    if [ x"${DBNAMES}" = "xall" ]; then
        die "${BACKUP_TYPE}: could not get all databases"
    fi
}

curl_es() {
    path="${1}"
    shift
    es_args=""
    curl="$(which curl 2>/dev/null)"
    jq="$(which jq 2>/dev/null)"
    if [ ! -f "${curl}" ];then
        die "install curl"
    fi
    if [ ! -f "${jq}" ];then
        die "install jq"
    fi
    if [ "x${ES_USER}" != "x" ];then
        es_args="-u ${ES_USER}:${ES_PASSWORD}"
    fi
    curl -s "${@}" $es_args "${ES_URI}/${path}"
}

es_check_connectivity() {
    curl_es 1>/dev/null || die_in_error "$ES_URI unreachable"
    ES_TMP=$(curl_es "_nodes/_local?pretty"|grep '"work" :'|awk '{print $3}'|sed -e 's/\(^[^"]*"\)\|\("[^"]*$\)//g')
    ES_SNAPSHOTS_DIR="${ES_SNAPSHOTS_DIR:-${ES_TMP}/snapshots}"
    # set backup repository
}

es_get_all_databases() {
    curl_es _cat/indices|awk '{print $3}'
}

es_getreponame() {
    name="dsb_${1}"
    echo "${name}"
}

es_getworkdir() {
    name="${1}"
    # THIS HAVE TO BE ADDED TO PATH.REPO ES CONF !
    echo "${ES_SNAPSHOTS_DIR}/${name}"
}

es_preparerepo() {
    name="${1}"
    directory="$(es_getworkdir ${name})"
    esname="$(es_getreponame ${name})"
    if [ ! -e "${ES_SNAPSHOTS_DIR}" ];then
        die "Invalid es dir"
    fi
    for i in $(seq 3);do
        ret=$(curl_es "_snapshot/${esname}"|jq '.["'"${esname}"'"]["settings"]["location"]')
        if [ "x${ret}" != 'x"'"${directory}"'"' ];then
            sleep 1
        else
            break
        fi
    done
    if [ "x${ret}" = 'x"'"${directory}"'"' ];then
        sleep 1
    fi
    curl_es "_snapshot/${esname}" -XDELETE >/dev/null 2>&1
    die_in_error "Directory API link removal problem for ${name} / ${esname} / ${directory}"
    ret=$(curl_es "_snapshot/${esname}" -XPUT\
        -d '{"type": "fs", "settings": {"location": "'"$(basename ${directory})"'", "compress": false}}')
    if [ "x${ret}" != 'x{"acknowledged":true}' ];then
        echo "${ret}" >&2
        /bin/false
        die "Cannot create repo ${esname} for ${name} (${directory})"
    fi
    for i in $(seq 10);do
        ret=$(curl_es "_snapshot/${esname}"|jq '.["'"${esname}"'"]["settings"]["location"]')
        if [ "x${ret}" != 'x"'"${directory}"'"' ];then
            sleep 1
        else
            break
        fi
    done
    if [ "x${ret}" != 'x"'"$(basename ${directory})"'"' ];then
        echo $ret >&2;/bin/false
        die "Directory snapshot metadata problem for ${name} / ${directory}"
    fi
}


es_dumpall() {
    cwd="${PWD}"
    name="$(basename $(dirname $(dirname ${2})))"
    esname="$(es_getreponame ${name})"
    es_preparerepo "${name}"
    ret=$(curl_es "_snapshot/${esname}/dump?wait_for_completion=true" -XDELETE)
    ret=$(curl_es "_snapshot/${esname}/dump?wait_for_completion=true" -XPUT)
    if [ "x$(echo "${ret}"|grep -q '"state":"SUCCESS"';echo ${?})" = "x0" ];then
        directory=$(es_getworkdir ${name})
        if [ -e "${directory}" ];then
            cd "${directory}"
            tar cf "${2}" .\
                && curl_es "_snapshot/${esname}/dump?wait_for_completion=true"\
                && cd "${cwd}"
            die_in_error "ES tar: ${2} / ${name} / ${esname} failed"
        else
            die_in_error "ES tar: ${2} / ${name} / ${esname} backup workdir ${directory}  pb"
        fi
    else
        echo ${ret} >&2;/bin/false
        die_in_error "ES tar: ${2} / ${name} / ${esname} backup failed"
    fi
}

es_dump() {
    cwd="${PWD}"
    name="$(basename $(dirname $(dirname ${2})))"
    esname="$(es_getreponame ${name})"
    es_preparerepo "${name}"
    ret=$(curl_es "_snapshot/${esname}/dump?wait_for_completion=true" -XDELETE)
    ret=$(curl_es "_snapshot/${esname}/dump?wait_for_completion=true" -XPUT -d '{
        "indices": "'"${name}"'",
        "ignore_unavailable": "true",
        "include_global_state": false
    }')
    if [ "x$(echo "${ret}"|grep -q '"state":"SUCCESS"';echo ${?})" = "x0" ];then
        directory=$(es_getworkdir ${name})
        if [ -e "${directory}" ];then
            cd "${directory}"
            tar cf "${2}" .\
                && curl_es "_snapshot/${esname}/dump?wait_for_completion=true"\
                && cd "${cwd}"
            die_in_error "ESs tar: ${2} / ${name} / ${esname} failed"
        else
            die_in_error "ESs tar: ${2} / ${name} / ${esname} backup workdir ${directory} pb"
        fi
    else
        echo ${ret} >&2;/bin/false
        die_in_error "ESs tar: ${2} / ${name} / ${esname} backup failed"
    fi
}

#################### MAIN
if [ x"${DB_SMART_BACKUP_AS_FUNCS}" = "x" ];then
    do_main "${@}"
fi

# vim:set ft=sh sts=4 ts=4  tw=0:
