#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
#==============================================================#
#   Description: backup script                                 #
#   Author: Teddysun <i@teddysun.com>                          #
#   Visit:  https://teddysun.com                               #
#==============================================================#

[[ $EUID -ne 0 ]] && echo 'Error: This script must be run as root!' && exit 1

### START OF CONFIG ###

# Encrypt flag(true:encrypt, false:not encrypt)
ENCRYPTFLG=true

# KEEP THE PASSWORD SAFE.
# The password used to encrypt the backup
# To decrypt backups made by this script, run the following command:
# openssl enc -aes256 -in [encrypted backup] -out decrypted_backup.tgz -pass pass:[backup password] -d -md sha1
BACKUPPASS="mypassword"

# Directory to store backups
LOCALDIR="/root/backups/"

# Temporary directory used during backup creation
TEMPDIR="/root/backups/temp/"

# File to log the outcome of backups
LOGFILE="/root/backups/backup.log"

# OPTIONAL: If you want MySQL to be backed up, enter the root password below
MYSQL_ROOT_PASSWORD=""

# Below is a list of files and directories that will be backed up in the tar backup
# For example:
# File: /data/www/default/test.tgz
# Directory: /data/www/default/test/
# if you want not to be backed up, leave it blank.
BACKUP[0]=""

# Date & Time
BACKUPDATE=$(date +%Y%m%d%H%M%S)

# Backup file name
TARFILE="${LOCALDIR}""$(hostname)"_"${BACKUPDATE}".tgz

# Backup MySQL dump file name
SQLFILE="${TEMPDIR}mysql_${BACKUPDATE}.sql"

### END OF CONFIG ###

log() {
    echo "$(date "+%Y-%m-%d %H:%M:%S")" "$1"
    echo -e "$(date "+%Y-%m-%d %H:%M:%S")" "$1" >> ${LOGFILE}
}

### START OF CHECKS ###

# Check if the backup folders exist and are writeable
if [ ! -d "${LOCALDIR}" ]; then
    mkdir -p ${LOCALDIR}
fi
if [ ! -d "${TEMPDIR}" ]; then
    mkdir -p ${TEMPDIR}
fi

# This section checks for all of the binaries used in the backup
BINARIES=( cat cd du date dirname echo openssl mysql mysqldump pwd rm tar )

# Iterate over the list of binaries, and if one isn't found, abort
for BINARY in "${BINARIES[@]}"; do
    if [ ! "$(command -v "$BINARY")" ]; then
        log "$BINARY is not installed. Install it and try again"
        exit 1
    fi
done

STARTTIME=$(date +%s)

cd "${LOCALDIR}" || exit

### END OF CHECKS ###


### START OF MYSQL BACKUP ###

if [ -z ${MYSQL_ROOT_PASSWORD} ]; then
    log "MySQL root password not set, MySQL back up skip"
else
    log "MySQL dump start"
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" <<EOF
exit
EOF
    if [ $? -ne 0 ]; then
        log "MySQL root password is incorrect. Please check it and try again"
        exit 1
    fi
    mysqldump -u root -p"${MYSQL_ROOT_PASSWORD}" --all-databases > "${SQLFILE}"
    if [ $? -ne 0 ]; then
        log "MySQL backup failed"
        exit 1
    fi
    log "MySQL dump completed"
    log "MySQL dump file name: ${SQLFILE}"
    #Add MySQL backup dump file to BACKUP list
    BACKUP=(${BACKUP[*]} ${SQLFILE})
fi

### END OF MYSQL BACKUP ###


### START OF TAR BACKUP ###

log "Backup progress start"

log "Tar backup file start"
tar -zcPf ${TARFILE} ${BACKUP[*]}
if [ $? -ne 0 ]; then
    log "Tar backup file failed"
    exit 1
fi
log "Tar backup file completed"

# Encrypt tar file
if ${ENCRYPTFLG}; then
    log "Encrypt backup file start"
    openssl enc -aes256 -in "${TARFILE}" -out "${TARFILE}.enc" -pass pass:"${BACKUPPASS}" -md sha1
    log "Encrypt backup file completed"

    # Delete unencrypted tar
    log "Delete unencrypted tar file"
    rm -f "${TARFILE}"
fi

log "Backup progress complete"
if ${ENCRYPTFLG}; then
    BACKUPSIZE=$(du -h ${TARFILE}.enc | cut -f1)
    log "File name: ${TARFILE}.enc, File size: ${BACKUPSIZE}"
else
    BACKUPSIZE=$(du -h ${TARFILE} | cut -f1)
    log "File name: ${TARFILE}, File size: ${BACKUPSIZE}"
fi

# Transfer file to Google Drive
# If you want to install gdrive command, please visit website:
# https://github.com/prasmussen/gdrive
# of cause, you can use below command to install it
# For x86_64: wget -O /usr/bin/gdrive http://dl.teddysun.com/files/gdrive-linux-x64; chmod +x /usr/bin/gdrive
# For i386: wget -O /usr/bin/gdrive http://dl.teddysun.com/files/gdrive-linux-386; chmod +x /usr/bin/gdrive

if [ ! "$(command -v "gdrive")" ]; then
    log "gdrive is not installed"
    log "File transfer skipped. please install it and try again"
else
    log "Tranferring tar backup to Google Drive"
    if ${ENCRYPTFLG}; then
        gdrive upload --no-progress ${TARFILE}.enc >> ${LOGFILE}
    else
        gdrive upload --no-progress ${TARFILE} >> ${LOGFILE}
    fi
    log "File transfer completed"
fi

### END OF TAR BACKUP ###


ENDTIME=$(date +%s)
DURATION=$((ENDTIME - STARTTIME))
log "All done"
log "Backup and transfer completed in ${DURATION} seconds"
