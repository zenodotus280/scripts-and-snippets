#!/bin/bash
# can be either as configured in `.ssh/config`, root@host, or similar
SOURCE_SSH=source.internal

TARGET_ZPOOL=tank
TARGET_DATASET=data

# only if mbuffer is installed on target (receiver)
BANDWIDTH_LIMIT=999M

# This script must be run from the target; SSH is used to pull data in rather than pushing data out

# Get the resume token
TOKEN=$(zfs get -H -o value receive_resume_token $TARGET_ZPOOL/$TARGET_DATASET)

# Resume if a token exists (i.e., if the previous send was interrupted)
if [ -n "$TOKEN" ] && [ "$TOKEN" != "-" ]; then
    if command -v mbuffer &> /dev/null; then
        # mbuffer can rate limit; pv not needed if using the -v option on the sending side.
        ssh $SOURCE_SSH "zfs send -v -t $TOKEN" | mbuffer -q -s 128k -m 5G -r $BANDWIDTH_LIMIT | zfs recv -Fs $SOURCE_POOL/$SOURCE_DATASET
    else
        ssh $SOURCE_SSH "zfs send -v -t $TOKEN" | zfs recv -Fs $TARGET_ZPOOL/$TARGET_DATASET
    fi
else
    echo "No valid resume token found. Run 'zfs send/recv' manually to verify the state of the transfer."
fi
