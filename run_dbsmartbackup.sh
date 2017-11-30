#!/usr/bin/env bash
#
# Wrapper to embed dbs in a cron
# * * * * * root /path/to/run_dbsmartbackup.sh /path/to/conf

if [ -f /etc/db_smart_backup_deactivated ];then
    exit 0
fi

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
__NAME__="RUN_DB_SMARTBACKUP"
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
# a running socket in the standard debian location
CONF="${DB_SMARTBACKUPS_CONF-${1}}"
LOG="${LOG:-/var/log/run_dbsmartbackup-${CONF//\//_}.log}"
if [ ! -e $CONF ];then
    echo "invalid $CONF" > $LOG
    RET=1
fi
go_run_db_smart_backup "${CONF}"
if [ x"${DEBUG}" != "x" ];then
    set +x
fi
if [ "x${QUIET}" != "x" ] && [ "x${RET}" != "x0" ];then
    cat "${LOG}"
fi
if [ -f $LOG ];then
    rm -f $LOG
fi
exit $RET
# vim:set et sts=4 ts=4 tw=00:
