#!/bin/bash
#
# Inspired by and based on http://www.heinlein-support.de/projekte/rsync-backup/backup-rotate
# Isaac Hailperin <isaac.hailperin@gmail.com>
# August 2014
# Changelog:
# 06-Nov-2014 | isaac | fixed HOME pointing to /root if called by root via sudo -u <username> 
# 05-Feb-2015 | isaac | gone back to the original client/server architecture.
# 14-May-2016 | isaac | added check_media_mount
# 15-May-2016 | isaac | added debug mode (call with 'debug' as first argument)

CONFIG_FILE="/usr/local/etc/backup_client.conf"

DEBUG=${1}

source ${CONFIG_FILE}


###
# functions
###
###

###
# print debug messages
###
debug(){
    message=${1}
    [ x${DEBUG} == x'debug' ] && echo "$(date +%Y-%m-%d\ %H:%M:%S) DEBUG: ${message}"
}

###
# update the status file
###
update_status(){
    message=${1}
    debug "updateing status file with '${message}'"
    timestamp=$(date +"%d-%b-%Y %T")
    prefix="+ Aktueller Status:"
    sed -i "s/${prefix}.*/${prefix} ${message} (${timestamp})/" ${STATUS_FILE}
}

update_last_success(){
    message=${1}
    debug "updateting '${STATUS_FILE}' with '${message}'"
    prefix="+ Letztes erfolgreiches Backup am"
    sed -i "s/${prefix}.*/${prefix} ${message}/" ${STATUS_FILE}
}

update_log(){
    message=$(echo ${1}| sed "s#\/#\\\/#g"|sed "s#\\n#\\\\n#g" )
    debug "updating log with '$message'"
    timestamp=$(date +"%d-%b-%Y %T")
    prefix="+ Letzte Logmeldung:"
    sed -i "s#${prefix}.*#${prefix} ${message} (${timestamp})#" ${STATUS_FILE}
}

print_dummy_statusfile(){
    if [ ! -f ${STATUS_FILE} ]; then
    cat >${STATUS_FILE} <<EOF
             BACKUP INFO 
             ===========
+ Aktueller Status: 
+ Letztes erfolgreiches Backup am
+ Letzte Logmeldung: 

EOF
    fi
}

# print need sudo configuration
###
print_sudo_additions() {
    echo Please make sure your sudo config contains the following lines:
    echo "${MY_NAME}    ALL=(ALL:ALL) NOPASSWD: /bin/mount -t cifs //${SAMBA_IP}/${SHARE_NAME} ${DATA_MOUNTPOINT} -o credentials=${CREDENTIAL_FILE} -o uid=${MY_UID} -o gid=${MY_GID}"
    echo "${MY_NAME}    ALL=(ALL:ALL) NOPASSWD: /bin/umount ${DATA_MOUNTPOINT}"
}

###
# check last successfull backup
###
check_last_successfull_backup(){
    if [ ! -f ${BACKUP_SUCCESS_FILE} ]; then
        debug "No successfull backup found for today"
        update_log "Bislang keine erfolgreichen Backups."
    else
        last_backup_date=$(cat ${BACKUP_SUCCESS_FILE})
        today=$(date "+%d-%b-%Y")
        if [ "${last_backup_date}" == "${today}" ]; then
            debug "Found current backup, exiting"
            exit
        fi
    fi
}

###
# check if backup is allready running
###
check_concurrent_backup(){
    ps -elf |grep rsync |grep ${LOCALHOME}
    if [ "$?" == "0" ]; then
        debug "backup is allready rounning, exiting"
        exit
    fi
}

###
# mount backup medium
###
mount_backup_medium(){
    if [ ${NO_MOUNT} == "True" ]; then
        return
    fi
    # check if backup nas is up and reachable
    debug "Mounting backup medium"
    ping -c 1 ${SAMBA_IP} >/dev/null
    ret_val_pingcheck="$?"
    if [  "${ret_val_pingcheck}" != "0" ];then
        $LOGGER -p user.err "Could not connect to ${SAMBA_IP}, as this host is unreachble"
        exit 0
    fi
    # mount backup
    # first check if allready mounted:
    mount |grep ${DATA_MOUNTPOINT}
    mounted=$?
    if [ "${mounted}" != "0" ]; then
        sudo mount -t cifs //${SAMBA_IP}/${SHARE_NAME} ${DATA_MOUNTPOINT} -o credentials=${CREDENTIAL_FILE} -o uid=${MY_UID} -o gid=${MY_GID}
        ret_val_mount="$?"
        if [ "${ret_val_mount}" != "0" ]; then
            $LOGGER -p user.err "Could not mount samba share on ${SAMBA_IP}, even though host is up"
            update_log "Kein Backup moeglich, weil Diskstation nicht eingebunden werden konnte."
            print_sudo_additions
            exit 1
        fi
    fi
}

###
# check if backup media is mounted
###
check_media_mount() {
    if [ ${NO_MOUNT_CHECK} == "True" ]; then
        return
    fi
    mount |grep ${DATA_MOUNTPOINT}
    mounted=$?
    if [ "${mounted}" != "0" ]; then
        debug "Did not find mountedbackup medium, exiting"
        update_log "Kein Backup moeglich, weil Backup medium nicht eingebunden ist."
        exit 1
    fi
    debug "Backup medium found"
}

###
# und jetzt das backup
###
do_backup(){
    $LOGGER -p user.info "START Backup of $LOCALHOME to $BACKUP_DIR"
    update_status "Backup gestartet."
    debug "executing backup"
    if [ ! -f $EXCLUDES ];then
        touch $EXCLUDES
    fi
    echo >> $LOGFILE
    echo `date` >> $LOGFILE
    rsync  --exclude-from="$EXCLUDES" --update --delete -av "$LOCALHOME/" "$BACKUP_DIR/" >> $LOGFILE 2>&1
    RET=$?
    case $RET in
    0)
    #alles gut
            today=$(date +"%d-%b-%Y")
            echo ${today} >${BACKUP_SUCCESS_FILE}
            echo ${today} >${BACKUP_SUCCESS_SERVER_FILE}
            update_last_success "${today}" 
            update_status "Backup erfolgreich beendet."
            update_log "Backup erfolgreich beendet."
            $LOGGER -p user.info "Backup finished successfully"
            ;;
    23)
    #z.B. Permission-Errors
            ERR_PERMISSION=$(cat "$LOGFILE"|grep -c 'Permission denied (13)')
     
            $LOGGER -p user.warn "Backup TEILWEISE ERFOLGREICH beendet mit RET-CODE $RET, Log-File: $LOGFILE"
            update_log "TEILWEISE Erfolgreich beendet. Möglicherweise Probleme mit Rechten."
            update_status "TEILWEISE Erfolgreich beendet."
            ;;
    24) #some files vanished before they could be transferred (code 24) at main.c(1070) [sender=3.0.8]
            $LOGGER -p user.warn "Backup TEILWEISE ERFOLGREICH beendet mit RET-CODE $RET (some files vanished before they could be transferred), Log-File: $LOGFILE"
            echo ${today} >${BACKUP_SUCCESS_FILE}
            echo ${today} >${BACKUP_SUCCESS_SERVER_FILE}
            update_last_success "${today}" 
            update_log "TEILWEISE Erfolgreich beendet. Einige Dateien wurden vorm syncen gelöscht."
            update_status "TEILWEISE Erfolgreich beendet."
            ;;
    130)
    #z.B. Abbruch durch <CTRL-C>
            $LOGGER -p user.err "Backup ABGEBROCHEN mit RET-CODE $RET, Log-File: $LOGFILE"
            update_log "Aus unbekanntem Grund beendet Möglicherweise Abbruch durch Benutzer."
            update_status "Abgebrochen."
            ;;
    *)
            $LOGGER -p user.alert "Backup GESCHEITERT mit RET-CODE $RET, Log-File: $LOGFILE"
            update_log "Backup ist GESCHEITERT mit RET-CODE $RET"
            update_status "Backup ist GESCHEITERT."
            ;;
    esac
}

###
# umount
###
unmount_backup_medium(){
    if [ ${NO_MOUNT} == "True" ]; then
        return
    fi
    sudo umount ${DATA_MOUNTPOINT}
    if [ "$?" != "0" ];then 
        print_sudo_additions
    fi
    debug "Successfully umounted backup medium"
}

###
# action
##
print_dummy_statusfile
check_last_successfull_backup # exits if successfull today
check_concurrent_backup # exits if backup is allready running
mount_backup_medium
check_media_mount
do_backup
unmount_backup_medium
