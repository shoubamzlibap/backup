#!/bin/bash
#
# Inspired by and based on http://www.heinlein-support.de/projekte/rsync-backup/backup-rotate
# Isaac Hailperin <isaac.hailperin@gmail.com>
# Changelog:
# 05-Feb-2015 | isaac | gone back to original client/server architecture

source backup_server.conf

# log facility
# note that on synology diskstations, everything below "WARNING" gets discarded.
LOGGER="logger -p WARNING -t backup" 

SUCCESS="True"

###
# check if an event was successfull today
# sets SUCCESS=False if not successfull today
# $1: file that should be checked
###
check_success_today() {
    SUCCESS_FILE=${1}
    if [ -f ${SUCCESS_FILE} ]; then
        last_success_date=$(cat ${SUCCESS_FILE})
        today=$(date "+%d-%b-%Y")
        if [ "${last_success_date}" != "${today}" ]; then
            SUCCESS="False"
        fi
    else
        SUCCESS="False"
    fi
}

###
# check last successfull backup
# sets SUCCESS=False if no successfull backup today
###
check_successfull_backup(){
    BACKUP_SUCCESS_FILE=${1}/${SUCCESS_FILE}
    check_success_today ${BACKUP_SUCCESS_FILE}
}

###
# check last successfull rotation of backup
# sets SUCCESS=False if no successfull backup today
###
check_successfull_rotate() {
    ROTATE_SUCCESS_FILE=${1}/${ROTATE_SUCCESS}
    if [ ! -f ${ROTATE_SUCCESS_FILE} ]; then
        echo "never rotated" >${ROTATE_SUCCESS_FILE}
    fi      
    check_success_today ${ROTATE_SUCCESS_FILE}
}

###
# Pruefe auf freien Plattenplatz
###
check_disk_free(){
    DATA_PATH=${1}
    GETPERCENTAGE='s/.* \([0-9]\{1,3\}\)%.*/\1/'
    if $CHECK_HDMINFREE ; then
        KBISFREE=$(df "$DATA_PATH" | tail -n1 | sed -e "$GETPERCENTAGE")
        INODEISFREE=$(df -i "$DATA_PATH" | tail -n1 | sed -e "$GETPERCENTAGE")
        if [ $KBISFREE -ge "$HDMINFREE" -o $INODEISFREE -ge $HDMINFREE ] ; then
            $LOGGER "Fatal: Not enough space left for rotating backups!"
            exit
        fi
    fi
}

###
# rotate snapshots 
###
rotate_snapshots(){
    BACKUP_DIR=${1}
    $LOGGER "Start rotating snapshots for ${BACKUP_DIR}"
    # Create backup dir if not present
    if ! [ -d "$BACKUP_DIR" ] ; then
            mkdir -p "$BACKUP_DIR"
    fi
    # remove oldest snapshot
    if [ -d "$BACKUP_DIR/daily.7" ] ; then
            rm -rf "$BACKUP_DIR/daily.7"
    fi
    # all other snapshots are moved by one
    for OLD in 6 5 4 3 2 1  ; do
            if [ -d "$BACKUP_DIR/daily.$OLD" ] ; then
                NEW=$[ $OLD + 1 ]
                # save the date
                touch "$BACKUP_DIR/.timestamp" -r "$BACKUP_DIR/daily.$OLD"
                mv "$BACKUP_DIR/daily.$OLD" "$BACKUP_DIR/daily.$NEW"
                # apply saved date
                touch "$BACKUP_DIR/daily.$NEW" -r "$DATA_PATH/.timestamp"
            fi
    done
    # copy level 0 snapshot by hardlinking it to level 1
    if [ -d "$BACKUP_DIR/daily.0" ] ; then
            cp -al "$BACKUP_DIR/daily.0" "$BACKUP_DIR/daily.1"
    fi
    $LOGGER "Finished rotating snapshots for ${BACKUP_DIR}"
    today=$(date +"%d-%b-%Y")
    echo ${today} >${BACKUP_DIR}/${ROTATE_SUCCESS}
}

###
# action
##
for client in ${CLIENT_DIRS}; do
    check_disk_free ${client}
    check_successfull_backup ${client} # sets SUCCESS=False if no successfull backup today
    if [ ${SUCCESS} == "False" ]; then
        SUCCESS="True"
        continue
    fi
    check_successfull_rotate ${client} # sets SUCCESS=False if rotation was attempted today
    if [ ${SUCCESS} == "False" ]; then
        SUCCESS="True"
    else
        continue
    fi
    rotate_snapshots ${client} 
done
