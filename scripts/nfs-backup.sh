#!/bin/bash

NFS_SERVER="192.168.1.1"
NFS_SHARE="/tank/data/share"
MOUNT_POINT="/mnt/HOST"
SOURCE_DIR="/srv/data"

# --------------------------------------------------------

if [ ! -d "$MOUNT_POINT" ]; then
    mkdir -p "$MOUNT_POINT"
fi

exec 200>/root/BACKUP.lock
flock -n 200 || exit 1

# Mount the NFS share; clean up in case of error
mount -t nfs "${NFS_SERVER}:${NFS_SHARE}" "$MOUNT_POINT"
trap 'sleep 10; umount $MOUNT_POINT' EXIT

# Verify if the mount was successful
if mount | grep -q "$MOUNT_POINT"; then
    echo "Successfully mounted ${NFS_SERVER}:${NFS_SHARE} to ${MOUNT_POINT}"
else
    echo "Failed to mount ${NFS_SERVER}:${NFS_SHARE}"
    exit 1
fi

# Mirror contents from source to target including deletions
echo "Starting mirroring from $SOURCE_DIR to $MOUNT_POINT..."
rsync -hPa --delete "$SOURCE_DIR/" "$MOUNT_POINT/"

# Check for rsync success; trap will unmount automatically
if [ $? -eq 0 ]; then
    echo "Mirroring completed successfully."
else
    echo "Mirroring failed."
    exit 1
fi

# Add to crontab: 55 * * * * bash /root/nfs-backup.sh