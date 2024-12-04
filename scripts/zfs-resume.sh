#!/bin/bash
# -----------------------------------------------------------------------------
# The script is intended or one-off bulk transfers.
# For more routine replication you should try sanoid+syncoid here:
# https://github.com/jimsalterjrs/sanoid
# -----------------------------------------------------------------------------

# can be either as configured in `.ssh/config`, root@host, or similar
SOURCE_SSH=source.internal

TARGET_ZPOOL=tank
TARGET_DATASET=data

# only used if mbuffer is installed on target (receiver)
BANDWIDTH_LIMIT=999M

# -----------------------------------------------------------------------------

if ! ssh $SOURCE_SSH "exit" &>/dev/null; then
    echo "Error: Unable to connect to $SOURCE_SSH. Check your SSH configuration."
    exit 1
fi

# The pool can't be force-created so fail if it doesn't exist.
if ! zfs list -H -o name $TARGET_ZPOOL &>/dev/null; then
    echo "Error: Target pool '$TARGET_ZPOOL' does not exist. Create it first."
    exit 1
fi

# Warn that the target dataset wasn't present; proceed regardless.
if ! zfs list -H -o name $TARGET_ZPOOL/$TARGET_DATASET &>/dev/null; then
    echo "Target dataset $TARGET_ZPOOL/$TARGET_DATASET does not exist. It will be created during transfer."
fi

# mbuffer can rate limit; pv not needed if using the -v option on the sending side.
if command -v mbuffer &>/dev/null; then
    echo "Bandwidth limit set to $BANDWIDTH_LIMIT."
    MB_CMD="mbuffer -q -s 128k -m 1G -r $BANDWIDTH_LIMIT"
else
    echo "Warning: mbuffer is not installed. Proceeding without bandwidth limiting."
    MB_CMD="cat"  # Acts as a no-op pipe
fi

print_instructions() {
    cat <<EOF

No valid resume token found. You may need to manually start or verify the transfer.

Suggested commands based on your scenario and the variables set in this script:

1. **Incomplete transfer with no token:**
   Verify what was transferred to the target, then delete and start over:
   zfs destroy $TARGET_ZPOOL/$TARGET_DATASET
   ssh $SOURCE_SSH "zfs send -v SOURCE_ZPOOL/SOURCE_DATASET" | zfs recv -Fs $TARGET_ZPOOL/$TARGET_DATASET

2. **Target dataset exists but doesn't have the latest snapshots:**
   Ensure the snapshot you want to send exists on the source and use incremental send:
   ssh $SOURCE_SSH "zfs send -v -I <last_common_snapshot> SOURCE_ZPOOL/SOURCE_DATASET@<new_snapshot>" | zfs recv -Fs $TARGET_ZPOOL/$TARGET_DATASET

3. **Recursively send the entire pool and all datasets:**
   ssh $SOURCE_SSH "zfs send -Rv SOURCE_ZPOOL" | $MB_CMD | zfs recv -Fs $TARGET_ZPOOL

Don't trust me!
Check for yourself:

man zfs-{send,recv,destroy}

https://openzfs.github.io/openzfs-docs/man/master/8/zfs-send.8.html
https://openzfs.github.io/openzfs-docs/man/master/8/zfs-recv.8.html
https://openzfs.github.io/openzfs-docs/man/master/8/zfs-destroy.8.html

EOF
}

# -----------------------------------------------------------------------------

# Get the resume token from the target. 
TOKEN=$(zfs get -H -o value receive_resume_token $TARGET_ZPOOL/$TARGET_DATASET)

# Resume only if a token exists otherwise print some instructions to assist.
if [ -n "$TOKEN" ] && [ "$TOKEN" != "-" ]; then
    ssh $SOURCE_SSH "zfs send -v -t $TOKEN" | $MB_CMD | zfs recv -Fs $TARGET_ZPOOL/$TARGET_DATASET
else
    print_instructions
fi
