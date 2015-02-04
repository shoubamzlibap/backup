#!/bin/bash
#
# Inspired by and based on http://www.heinlein-support.de/projekte/rsync-backup/backup-rotate
# Isaac Hailperin <isaac.hailperin@gmail.com>
# August 2014
# Changelog:
# 06-Nov-2014 - fixed HOME pointing to /root if called by root via sudo -u <username> 
# 23-Jan-2015 - gone back to the original client/server architecture.

# TODO:
# * status.html does not work on linux. Maybe a security feature?
# * count retries and stop after a certain number
# * delete unused code (e.g. lock related functions)


CONFIG_FILE="backup_client.conf"

source ${CONFIG_FILE}

###
# functions
###
###

###
# update the status file
###
update_status(){
    message=${1}
    timestamp=$(date +"%d-%b-%Y %T")
    prefix="+ Aktueller Status:"
    sed -i "s/${prefix}.*/${prefix} ${message} (${timestamp})/" ${STATUS_FILE}
}

update_last_success(){
    message=${1}
    prefix="+ Letztes erfolgreiches Backup am"
    sed -i "s/${prefix}.*/${prefix} ${message}/" ${STATUS_FILE}
}

update_log(){
    message=$(echo ${1}| sed "s#\/#\\\/#g"|sed "s#\\n#\\\\n#g" )
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
    echo "${MY_NAME}    ALL=(ALL:ALL) NOPASSWD: /bin/mount -t cifs //${SAMBA_IP}/${SHARE_NAME} ${DATA_PATH} -o credentials=${CREDENTIAL_FILE} -o uid=${MY_UID} -o gid=${MY_GID}"
    echo "${MY_NAME}    ALL=(ALL:ALL) NOPASSWD: /bin/umount ${DATA_PATH}"
}

###
# create a lock
###
create_lock(){
    lock_dir=${1}
    mkdir ${lock_dir} 2>/dev/null
    if [ $? != 0 ]; then
        ${LOGGER} "could not create ${lock_dir}"
        exit 1
    fi
}

###
# create a lock without failing if it allready exists
###
create_soft_lock(){
    lock_dir=${1}
    mkdir ${lock_dir} 2>/dev/null
    if [ $? != 0 ]; then
        if [ -d ${lock_dir} ];then
            return
        fi
        ${LOGGER} "could not create ${lock_dir}"
        exit 1
    fi
}

###
# delete a lock
###
delete_lock(){
    lock_dir=${1}
    if [ -d ${lock_dir} ]; then
        rmdir ${lock_dir}
        if [ $? != 0 ]; then
            message="${lock_dir} could not be deleted."
            ${LOGGER} "${message}"
        fi
    else
        message="Folgendes Verzeichnis existiert nicht, obwohl es das sollte: ${lock_dir}."
        message="The following directory does not exists, even though it should: ${lock_dir}."
        ${LOGGER} "${message}"
    fi
}



###
# check last successfull backup
###
check_last_successfull_backup(){
    if [ ! -f ${BACKUP_SUCCESS_FILE} ]; then
        update_log "Bislang keine erfolgreichen Backups."
    else
        last_backup_date=$(cat ${BACKUP_SUCCESS_FILE})
        today=$(date "+%d-%b-%Y")
        if [ "${last_backup_date}" == "${today}" ]; then
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
    ping -c 1 ${SAMBA_IP} >/dev/null
    ret_val_pingcheck="$?"
    if [  "${ret_val_pingcheck}" != "0" ];then
        $LOGGER -p user.err "Could not connect to ${SAMBA_IP}, as this host is unreachble"
        exit 0
    fi
    # mount backup
    # first check if allready mounted:
    mount |grep ${DATA_PATH}
    mounted=$?
    if [ "${mounted}" != "0" ]; then
        sudo mount -t cifs //${SAMBA_IP}/${SHARE_NAME} ${DATA_PATH} -o credentials=${CREDENTIAL_FILE} -o uid=${MY_UID} -o gid=${MY_GID}
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
# und jetzt das backup
###
do_backup(){
    $LOGGER -p user.info "START Backup of $LOCALHOME to $BACKUP_DIR"
    update_status "Backup gestartet."
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
            update_log "TEILWEISE Erfolgreich beendet.\nMöglicherweise Probleme mit Rechten."
            update_status "TEILWEISE Erfolgreich beendet."
            ;;
    24) #some files vanished before they could be transferred (code 24) at main.c(1070) [sender=3.0.8]
            $LOGGER -p user.warn "Backup TEILWEISE ERFOLGREICH beendet mit RET-CODE $RET (some files vanished before they could be transferred), Log-File: $LOGFILE"
            echo ${today} >${BACKUP_SUCCESS_FILE}
            echo ${today} >${BACKUP_SUCCESS_SERVER_FILE}
            update_last_success "${today}" 
            update_log "TEILWEISE Erfolgreich beendet.\nEinige Dateien wurden vorm syncen gelöscht."
            update_status "TEILWEISE Erfolgreich beendet."
            ;;
    130)
    #z.B. Abbruch durch <CTRL-C>
            $LOGGER -p user.err "Backup ABGEBROCHEN mit RET-CODE $RET, Log-File: $LOGFILE"
            update_log "Aus unbekanntem Grund beendet\nMöglicherweise Abbruch durch Benutzer."
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
    sudo umount ${DATA_PATH}
    if [ "$?" != "0" ];then 
        print_sudo_additions
    fi
}

###
# action
##
print_dummy_statusfile
check_last_successfull_backup # exits if successfull today
check_concurrent_backup # exits if backup is allready running
mount_backup_medium
do_backup
unmount_backup_medium
