#!/bin/bash

# housekeeping
set -e

### Check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

### List of required commands
REQUIRED_COMMANDS=("curl" "lsblk" "zpool" "sanoid" "syncoid")

### Check for presence of required commands
for cmd in "${REQUIRED_COMMANDS[@]}"; do
  if ! command_exists "$cmd"; then
    echo "Error: '$cmd' command not found."
    exit 1
  fi
done

# Constants and Variables

readonly SCRIPT_NAME="$(basename "$0")"
readonly LOG_FILE="${SCRIPT_NAME}_error.log"

### Parse command-line arguments if provided
while [[ $# -gt 0 ]]; do
  case "$1" in
    --gotify)
      # Handle empty --gotify argument
      if [[ -z "$2" || "$2" == --* ]]; then
        echo "Error: Missing value for '--gotify' option. Omit the '--gotify' option completely if not using Gotify."
        exit 1
      else
        GOTIFY_URL="$2"
      fi
      shift 2
      ;;
    --from)
      # Handle empty --from argument
      if [[ -z "$2" || "$2" == --* ]]; then
        echo "Error: Missing value for '--from' option. Omit the '--from' option completely if using the default."
        exit 1
      else
        SOURCE_ZPOOL="$2"
      fi
      shift 2
      ;;
    --to)
      # Handle empty --to argument
      if [[ -z "$2" || "$2" == --* ]]; then
        echo "Error: Missing value for '--to' option. Omit the '--too' option completely if using the default."
        exit 1
      else
        TARGET_ZPOOL="$2"
      fi
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

### Hardcoded details if not provided via command-line
if [[ -z "$GOTIFY_URL" ]]; then
  readonly GOTIFY_URL="https://gotify.example.com/message?token=ABC123"
fi
if [[ -z "$SOURCE_ZPOOL" ]]; then
  readonly SOURCE_ZPOOL="tank"
fi
if [[ -z "$TARGET_ZPOOL" ]]; then
  readonly TARGET_ZPOOL="tank-backup"
fi

### Validate required arguments
if [[ -z "$GOTIFY_URL" || -z "$SOURCE_ZPOOL" || -z "$TARGET_ZPOOL" ]]; then
  echo "Usage: $0 --gotify <gotify_url> --from <source_zpool> --to <target_zpool>"
  exit 1
fi

### Confirm variable values
echo "Confirm the inputs to be used:"
echo "GOTIFY_URL: $GOTIFY_URL"
echo "SOURCE_ZPOOL: $SOURCE_ZPOOL"
echo "TARGET_ZPOOL: $TARGET_ZPOOL"

### Ask for confirmation
read -rp "Are these values correct? (y/n): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  echo "Script execution aborted."
  exit 1
fi

### Ask for confirmation to skip scrub
read -rp "Skip scrub on target pool for faster removal? (y/n): " skip_scrub
if [[ "$skip_scrub" == "y" || "$skip_scrub" == "Y" ]]; then
  SKIP_SCRUB=true
else
  SKIP_SCRUB=false
fi

STAGE="INIT"

# Functions

### Logging Setup

handle_error() {
    echo "$(date)" ">>> ERROR ... occurred in line $1" | tee -a "$LOG_FILE"
    gotify_high "$(cat "$LOG_FILE")"
    exit 1
  }

trap 'handle_error $LINENO' ERR

### Notification System

gotify_low() {
  if [[ -n "$GOTIFY_URL" ]]; then
    MESSAGE="$1"
    curl ""$GOTIFY_URL"" -F "title=$(hostname)" -F "message=$STAGE: $MESSAGE" -F "priority=0"
  fi
}

gotify_medium() {
  if [[ -n "$GOTIFY_URL" ]]; then
    MESSAGE="$1"
    curl ""$GOTIFY_URL"" -F "title=$(hostname)" -F "message=$STAGE: $MESSAGE" -F "priority=4"
  fi
}

gotify_high() {
  if [[ -n "$GOTIFY_URL" ]]; then
    MESSAGE="$1"
    curl ""$GOTIFY_URL"" -F "title=$(hostname)" -F "message=$STAGE: $MESSAGE" -F "priority=8"
  fi
}

### Pool Detection

zpool_detect_import() {
  STAGE="IMPORT"
  local zpool_presence=$(zpool status -P "$1")
  if [[ ! "$zpool_presence" == *"state: ONLINE"* ]] && lsblk -f | grep -q "$1"; then
    zpool import "$1"
    gotify_low "\"$1\" found and imported!"
  fi
}

### Scrub Detection

get_scrub_status() {
  local pool_name="$1"

  # Get the status of the pool
  local status=$(zpool status -P "$pool_name")
  echo "Checking the scrub status for '$pool_name'"

  # Check if the status indicates an active scrub
  if [[ "$status" == *"scan: scrub in progress"* ]]; then
    echo "The ZFS pool '$pool_name' has an active scrub."
    SCRUB_STATUS="ACTIVE"
  else
    echo "The ZFS pool '$pool_name' does not have an active scrub."
    SCRUB_STATUS="INACTIVE"
  fi
}

# Rest of the Owl (aka. Main Program)

zpool_detect_import "$TARGET_ZPOOL"

## snapshot pruning

STAGE="PRUNE-1"
sanoid --cron --verbose # pruning on both pools
gotify_low "Initial pruning complete."

## Pause active scrub on source pool as a precaution
STAGE="SCRUB-PAUSE"
get_scrub_status "$SOURCE_ZPOOL"
if [[ $SCRUB_STATUS == "ACTIVE" ]]; then
  zpool scrub -p "$SOURCE_ZPOOL"
  echo "Paused active scrub on the source pool."
  SCRUB_STATUS="PAUSED"
fi

## Syncoid to target
STAGE="SYNC"
syncoid --skip-parent --recursive --compress lzo "$SOURCE_ZPOOL" "$TARGET_ZPOOL"
gotify_low "Sync to target complete."

## Resume or start scrub on source pool
STAGE="SCRUB-SOURCE"
get_scrub_status "$SOURCE_ZPOOL"
if [[ $SCRUB_STATUS == "INACTIVE" ]]; then
  zpool scrub "$SOURCE_ZPOOL"
  echo "Started scrub on the source pool."
elif [[ $SCRUB_STATUS == "PAUSED" ]]; then
  zpool scrub "$SOURCE_ZPOOL"
  echo "Unpaused scrub on the source pool."
fi
unset SCRUB_STATUS

## Scrub the backup and wait until complete
STAGE="SCRUB-TARGET"
get_scrub_status "$TARGET_ZPOOL"
if [[ $SCRUB_STATUS == "ACTIVE" ]]; then
  zpool scrub -s "$TARGET_ZPOOL"
  echo "Stopped scrub on the target pool. It shouldn't have been running."
fi
unset SCRUB_STATUS
if [[ $SKIP_SCRUB == "false" ]]; then
  gotify_low "Initiating scrub on \"$TARGET_ZPOOL\". This process may take up to 24 hours."
  zpool scrub -w "$TARGET_ZPOOL" # The '-w' option is a recent addition to ZFS
  gotify_low "Scrub on \"$TARGET_ZPOOL\" was successful!"
fi

## Clean up redundant snapshots using sanoid --cron
STAGE="PRUNE-2"
sanoid --cron --verbose
gotify_low "Final pruning of snapshots complete."

## Export the backup pool
STAGE="EXPORT"
zpool export "$TARGET_ZPOOL"
gotify_high "Backup pool \"$TARGET_ZPOOL\" has been exported and is safe to remove."
echo "Script execution completed successfully."

exit 0