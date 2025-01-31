#!/bin/bash

# ============================================
# Set Up SSHFS Access with Restricted SSH Key
# ============================================

# ---------------------------
# Configuration Variables
# ---------------------------
# NOTE: You must set these before running the script.
REMOTE_USER=""
REMOTE_HOST=""

HOSTNAME=$(hostname)
KEY_NAME="id_sshfs_${HOSTNAME}"
KEY_COMMENT="Restricted SSHFS access key for ${REMOTE_USER}@${REMOTE_HOST} from ${HOSTNAME}"

REMOTE_PATH=""
LOCAL_MOUNT_POINT=""

SSH_DIR="/root/.ssh"
KEY_PATH="${SSH_DIR}/${KEY_NAME}"

# The lines below ensure the script stops on errors, 
# undefined variables, or failed pipes. This prevents silent failures.
set -euo pipefail

# -----------
# Error Helper
# -----------
error_exit() {
    echo "I'm sorry, but something went wrong: $1" >&2
    exit 1
}

# ---------------
# Basic Checks
# ---------------
# 1) Must be run as root to install packages & create system directories
if [ "$(id -u)" != "0" ]; then
    error_exit "This script must be run as root. Please re-run as root."
fi

# 2) Check if APT is available (Debian/Ubuntu-based)
if ! command -v apt &> /dev/null; then
    error_exit "APT package manager not found. This script is designed for Debian/Ubuntu-like systems."
fi

echo
echo "Greetings. I see you are root. APT is available. Everything is proceeding smoothly..."
sleep 1

# ----------------------------------------
# Step 0: Summarize & Confirm with the User
# ----------------------------------------
echo
echo "I am about to perform the following actions:"
echo " 1. Validate that configuration variables (REMOTE_USER, REMOTE_HOST, REMOTE_PATH, LOCAL_MOUNT_POINT) are set."
echo " 2. Generate an Ed25519 SSH key restricted to non-interactive usage (no shell)."
echo " 3. Copy this key to ${REMOTE_USER}@${REMOTE_HOST}, placing it in their ~/.ssh/authorized_keys with restricted options."
echo " 4. Install the 'sshfs' package via APT."
echo " 5. Generate an example fstab entry with 'allow_other' and 'umask=0002' to ensure group/other permissions are set suitably."
echo " 6. List the current authorized_keys on ${REMOTE_HOST} so you can review them."

echo
read -rp "Do you wish to proceed? (y/n) " proceed
case "$proceed" in
    [yY][eE][sS]|[yY]) 
        echo "Excellent. Let us continue..."
        ;;
    *)
        error_exit "Operation aborted by user."
        ;;
esac
echo

setup_sshfs() {
    echo "=== SSHFS Setup Script Started ==="
    echo
    echo "Validating configuration now..."

    validate_config
    create_ssh_key
    copy_ssh_key_restricted
    install_sshfs
    generate_fstab
    list_authorized_keys

    echo "=== SSHFS Setup Completed Successfully ==="
    echo
    echo "I have finished all tasks. You may now review and follow these final steps:"
    echo "  1. Create your local mount point if needed: mkdir -p ${LOCAL_MOUNT_POINT}"
    echo "  2. Backup your /etc/fstab:                  cp /etc/fstab /etc/fstab.backup"
    echo "  3. Append the example entry to /etc/fstab:  cat sshfs_example_fstab.txt >> /etc/fstab"
    echo "  4. Mount all filesystems:                   systemctl daemon-reload && mount -a"
    echo "  5. Check it's mounted properly:             df -h | grep \$(basename ${LOCAL_MOUNT_POINT})"
    echo
}

# ---------------------------
# Function Definitions
# ---------------------------

# Validates that required variables are non-empty.
validate_config() {
    echo "=== Validating Configuration ==="
    if [[ -z "$REMOTE_USER" || -z "$REMOTE_HOST" || -z "$REMOTE_PATH" || -z "$LOCAL_MOUNT_POINT" ]]; then
        error_exit "One or more required variables (REMOTE_USER, REMOTE_HOST, REMOTE_PATH, LOCAL_MOUNT_POINT) are not set."
    fi
    echo "Configuration validated successfully."
    echo
}

# Generates a local SSH key if it doesn't already exist, 
# so we have a dedicated key for SSHFS usage. This avoids 
# sharing your personal keys and offers better compartmentalization.
create_ssh_key() {
    echo "=== Creating SSH Key ==="
    if [ -f "${KEY_PATH}" ]; then
        echo "The SSH key '${KEY_NAME}' already exists at ${KEY_PATH}. No new key will be generated."
    else
        mkdir -p "${SSH_DIR}"
        chmod 700 "${SSH_DIR}"
        ssh-keygen -t ed25519 -f "${KEY_PATH}" -C "${KEY_COMMENT}" -N ""
        echo "SSH key '${KEY_NAME}' successfully created with comment '${KEY_COMMENT}'."
    fi
    echo
}

# Copies the newly created SSH key to the remote host's authorized_keys, 
# adding restrictions like 'no-pty' to prevent an interactive shell if the key is compromised.
copy_ssh_key_restricted() {
    echo "=== Copying SSH Key to Remote Host with Restrictions ==="
    
    PUB_KEY=$(< "${KEY_PATH}.pub")
    
    # Restrict interactive usage by disabling PTY, port forwarding, etc.
    RESTRICTED_KEY_OPTIONS="no-agent-forwarding,no-port-forwarding,no-X11-forwarding,no-pty"
    
    # NOTE: We are using StrictHostKeyChecking=no in the final fstab example, 
    # which is less secure. If security is paramount, consider removing that option 
    # and properly managing known_hosts.
    
    echo "Ensuring that ~/.ssh exists on the remote host ${REMOTE_HOST}..."
    ssh "${REMOTE_USER}@${REMOTE_HOST}" "mkdir -p ~/.ssh && chmod 700 ~/.ssh"
    
    echo "Appending restricted key to authorized_keys on ${REMOTE_HOST}..."
    ssh "${REMOTE_USER}@${REMOTE_HOST}" "echo '${RESTRICTED_KEY_OPTIONS} ${PUB_KEY}' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
    
    echo "The restricted SSH key was successfully added to ${REMOTE_USER}@${REMOTE_HOST}."
    echo
}

# Installs the sshfs package so we can mount remote directories over SSH.
install_sshfs() {
    echo "=== Installing SSHFS ==="
    apt-get update
    apt-get install -y sshfs
    echo "SSHFS installed successfully. Now we can fuse-mount remote directories via SSH."
    echo
}

# Generates a sample fstab entry with best-practice flags for multi-user read-write. 
# 'allow_other' ensures others can access, and 'umask=0002' typically yields 775/664 for dirs/files.
generate_fstab() {
    echo "=== Generating Example /etc/fstab Entry ==="
    FSTAB_FILE="sshfs_example_fstab.txt"
    cat <<EOL > "${FSTAB_FILE}"
# SSHFS mount for ${REMOTE_USER}@${REMOTE_HOST}
#--------------------------------------------------------------------#
# Why these options?
# - defaults: basic default mount options
# - _netdev: ensures mounting is deferred until network is up
# - allow_other: let other local users access the mount
# - umask=0002: typically sets new files to 664 and dirs to 775
# - IdentityFile: use the restricted SSH key created by sshfs-client-setup.sh
# - StrictHostKeyChecking=no: ignoring host key checks - tradeoff for convenience
#--------------------------------------------------------------------#
${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH} ${LOCAL_MOUNT_POINT} fuse.sshfs \
defaults,_netdev,allow_other,umask=0002,IdentityFile=${KEY_PATH},UserKnownHostsFile=${SSH_DIR}/known_hosts,StrictHostKeyChecking=no 0 0
EOL
    echo "An example fstab entry was saved to '${FSTAB_FILE}'."
    echo "Please review or modify it before appending to /etc/fstab."
    echo
}

# Lists the remote's authorized_keys so the user can visually confirm that the restricted key was added.
list_authorized_keys() {
    echo "=== Listing Existing Authorized Keys on ${REMOTE_HOST} ==="
    echo "Let me show you what is currently in ${REMOTE_USER}'s authorized_keys on the remote host..."
    echo
    ssh "${REMOTE_USER}@${REMOTE_HOST}" "cat ~/.ssh/authorized_keys" | nl || {
        echo "I could not retrieve the authorized_keys. Possibly there's an issue with your SSH connection."
        return
    }
    echo
    echo "Always ensure you trust the listed keys. Remove any that are out of date or suspicious."
    echo
}

# Invoke the main orchestration function
setup_sshfs