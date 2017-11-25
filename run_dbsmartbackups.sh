#!/usr/bin/env bash
#
# Search in /etc/dbsmartbackup for any database configuration
# Run db_smart_backup.sh whenever it is applicable on those configurations
#
# pg: /etc/dbsmartbackup/postgresql.conf
# mysql: /etc/dbsmartbackup/mysql.conf
# mongodb: /etc/dbsmartbackup/mongod.conf
# slapd: /etc/dbsmartbackup/slapd.conf
# redis: /etc/dbsmartbackup/redis.conf
#
if [ -f /etc/db_smart_backup_deactivated ];then
    exit 0
fi

LOG="${LOG:-/var/log/run_dbsmartbackup.log}"
QUIET="${QUIET:-}"
RET=0
for i in ${@};do
    if [ "x${i}" = "x--no-colors" ];then
        export NO_COLORS="1"
    fi
    if [ "x${i}" = "x--quiet" ];then
        QUIET="1"
    fi
    if [ "x${i}" = "x--help" ] || \
       [ "x${i}" = "x--h" ]  \
        ;then
        HELP="1"
    fi
done
__NAME__="RUN_DB_SMARTBACKUPS"
if [ "x${HELP}" != "x" ];then
    echo "${0} [--quiet] [--no-colors]"
    echo "Run all found db_smart_backups configurations"
    exit 1
fi
if [ x"${DEBUG}" != "x" ];then
    set -x
fi

is_container() {
    echo  "$(cat -e /proc/1/environ |grep container=|wc -l|sed -e "s/ //g")"
}

filter_host_pids() {
    pids=""
    if [ "x$(is_container)" != "x0" ];then
        pids="${pids} $(echo "${@}")"
    else
        for pid in ${@};do
            if [ "x$(grep -q /lxc/ /proc/${pid}/cgroup 2>/dev/null;echo "${?}")" != "x0" ];then
                pids="${pids} $(echo "${pid}")"
            fi
         done
    fi
    echo "${pids}" | sed -e "s/\(^ \+\)\|\( \+$\)//g"
}

go_run_db_smart_backup() {
    conf="${1}"
    if [ "x${QUIET}" != "x" ];then
        db_smart_backup.sh "${conf}" 2>&1 1>> "${LOG}"
        if [ "x${?}" != "x0" ];then
            RET=1
        fi
    else
        db_smart_backup.sh "${conf}"
        if [ "x${?}" != "x0" ];then
            RET=1
        fi
    fi
}
if [ "x${PG_CONFS}" = "x" ];then
    # /etc/postgresql matches debia,n
    # /var/lib/pgsql matches redhat
    PG_CONFS=$(find /etc/postgresql /var/lib/pgsql -name postgresql.conf 2>/dev/null)
fi
if [ "x${PG_CONFS}" = "x" ];then
    PG_CONFS=/etc/postgresql.conf
fi
PORTS=$(egrep -h "^port\s=\s" ${PG_CONFS} 2>/dev/null|awk -F= '{print $2}'|awk '{print $1}'|sort -u)
DB_SMARTBACKUPS_CONFS="${DB_SMARTBACKUPS_CONFS:-"/etc/dbsmartbackup"}"
# try to run postgresql backup to any postgresql version if we found
# a running socket in the standard debian location
CONF="${DB_SMARTBACKUPS_CONFS}/postgresql.conf"
for port in ${PORTS};do
    socket_path="/var/run/postgresql/.s.PGSQL.$port"
    if [ -e "${socket_path}" ];then
        # search back from which config the port comes from
        for i in  /etc/postgresql/*/*/post*.conf;do
            if [ x"${port}" = x"$(egrep -h "^port\s=\s" "$i"|awk -F= '{print $2}'|awk '{print $1}')" ];then
                # search the postgres version to export binaries
                export PGVER="$(basename $(dirname $(dirname ${i})))"
                export PGVER="${PGVER:-9.3}"
                break
            fi
        done
        if [ -e "${CONF}" ];then
            export PGHOST="/var/run/postgresql"
            export HOST="${PGHOST}"
            export PGPORT="$port"
            export PORT="${PGPORT}"
            export PATH="/usr/lib/postgresql/${PGVER}/bin:${PATH}"
            if [ "x${QUIET}" = "x" ];then
                echo "$__NAME__: Running backup for postgresql ${socket_path}: ${VER} (${CONF} $(which psql))"
            fi
            go_run_db_smart_backup "${CONF}"
            unset PGHOST HOST PGPORT PORT
        fi
    fi
done
# try to run mysql backups if the config file is present
# and we found a mysqld process
CONF="${DB_SMARTBACKUPS_CONFS}/mysql.conf"
if [ "x$(which mysql 2>/dev/null)" != "x" ] && [ x"$(filter_host_pids $(ps aux|grep mysqld|grep -v grep)|wc -w)" != "x0" ] &&  [ -e "${CONF}" ];then
    if [ "x${QUIET}" = "x" ];then
        echo "$__NAME__: Running backup for mysql: $(mysql --version) (${CONF} $(which mysql))"
    fi
    go_run_db_smart_backup "${CONF}"
fi
if [ x"${DEBUG}" != "x" ];then
    set +x
fi
# try to run redi  backups if the config file is present
CONF="${DB_SMARTBACKUPS_CONFS}/redis.conf"
if [ "x$(which redis-server)" != "x" ] && [ x"$(filter_host_pids $(ps aux|grep redis-server|grep -v grep)|wc -w)" != "x0" ] &&  [ -e "${CONF}" ];then
    if [ "x${QUIET}" = "x" ];then
        echo "$__NAME__: Running backup for redis: $(redis-server --version|head -n1) (${CONF} $(which redis-server))"
    fi
    go_run_db_smart_backup "${CONF}"
fi
# try to run mongodb backups if the config file is present
CONF="${DB_SMARTBACKUPS_CONFS}/mongod.conf"
if [ "x$(which mongod 2>/dev/null )" != "x" ] && [ x"$(filter_host_pids $(ps aux|grep mongod|grep -v grep)|wc -w)" != "x0" ] &&  [ -e "${CONF}" ];then
    if [ "x${QUIET}" = "x" ];then
        echo "$__NAME__: Running backup for mongod: $(mongod --version|head -n1) (${CONF} $(which mongod))"
    fi
    go_run_db_smart_backup "${CONF}"
fi
# try to run slapd backups if the config file is present
# and we found a mysqld process
CONF="${DB_SMARTBACKUPS_CONFS}/slapd.conf"
if [ x"$(filter_host_pids $(ps aux|grep slapd|grep -v grep|awk '{print $2}')|wc -w)" != "x0" ] &&  [ -e "${CONF}" ];then
    if [ "x${QUIET}" = "x" ];then
        echo "$__NAME__: Running backup for slapd"
    fi
    go_run_db_smart_backup "${CONF}"
fi
# try to run ES backups if the config file is present
# and we found a mysqld process
CONF="${DB_SMARTBACKUPS_CONFS}/elasticsearch.conf"
if [ x"$(filter_host_pids $(ps aux|grep org.elasticsearch.bootstrap.Elasticsearch|grep -v grep|awk '{print $2}')|wc -w)" != "x0" ] &&  [ -e "${CONF}" ];then
    if [ "x${QUIET}" = "x" ];then
        echo "$__NAME__: Running backup for elasticsearch"
    fi
    go_run_db_smart_backup "${CONF}"
fi
if [ x"${DEBUG}" != "x" ];then
    set +x
fi
if [ "x${QUIET}" != "x" ] && [ "x${RET}" != "x0" ];then
    cat "${LOG}"
fi
exit $RET
# vim:set et sts=4 ts=4 tw=00:
