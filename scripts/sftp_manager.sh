#!/bin/bash
# shellcheck disable=SC2174

# A simple SFTP Manager using:
# chroot
# openssh
# bash
# systemd

clear
set -eo pipefail

# This can be a local or remote path. I keep the data separate from the OS.
PATH_TO_SHARE="/mnt/data/clients"

# `chroot` needs a subfolder for permissions to work correctly. "FILES" or similarly named would also work.
LOCAL_FOLDER_NAME="UPLOADS_DOWNLOADS"

# run `bash sftp_manager.sh --init` to configure the SFTP server
if [ "$1" = "--init" ]; then

    # avoid locale errors
    localectl set-locale LANG=en_US.UTF-8
    locale-gen en_US.UTF-8
    
    # set up SFTP
    addgroup sftp
    sed -i -E 's/^#?(PermitRootLogin\s+)(yes|without-password|prohibit-password)/\1no/' /etc/ssh/sshd_config
    {
        echo ""
        echo "Match group sftp"
        echo "ChrootDirectory /mnt/data/clients/%u" # %u will use the user's name for a folder
        echo "ForceCommand internal-sftp" # restrict to only the SFTP subsystem (no shell)
    } >> /etc/ssh/sshd_config      
    systemctl restart ssh
fi

sanitize_input() {
    # Sanitize user input to enforce only letters and numbers
    local input="${1//[^[:alnum:]]/}"
    echo "$input"
}

list_sftp_users() {
     awk -F':' '{print $1}' /etc/passwd | xargs -n1 groups | grep sftp | awk '{print $1}' || echo "No users!"; sleep 2
}

list_users() {
    clear
    echo "The following users exist:"
    echo ""
    list_sftp_users
    echo ""
    echo "The following directories exist (only the top level of each user shown):"
    echo ""
    find "$PATH_TO_SHARE" -maxdepth 1
    echo ""
}

add_user() {
    clear
    echo "Type the username that you want to create. Do not use spaces!"
    read -r USERNAME
    USERNAME=$(sanitize_input "$USERNAME")
    echo "User will be called $USERNAME."
    sleep 2
    useradd "$USERNAME" -g sftp
    mkdir -p -m 700 "$PATH_TO_SHARE/$USERNAME/$LOCAL_FOLDER_NAME"
    chown "$USERNAME:sftp" "$PATH_TO_SHARE/$USERNAME/$LOCAL_FOLDER_NAME"
    passwd "$USERNAME"
}

remove_user() {
    clear
    echo "The following users exist:"
    echo ""
    list_sftp_users
    echo ""
    echo "Type the username that you want to destroy. This will remove the user *and* their data."
    read -r USERNAME
    USERNAME=$(sanitize_input "$USERNAME")

    if [[ -z $USERNAME ]]; then
        echo "Invalid username. Please try again."
        return
    fi

    echo "The following higher level directories exist and will be deleted:"
    echo ""
    find "$PATH_TO_SHARE/$USERNAME" -maxdepth 3
    echo ""
    echo "Are you sure you want to remove everything associated with $USERNAME? Type 'destroy' if so."
    read -r confirmation

    if [[ "$confirmation" == "destroy" ]]; then
        rm -rf "${PATH_TO_SHARE:?}/$USERNAME"
        deluser "$USERNAME"
        echo "$USERNAME has been removed and their data deleted."
    else
        echo "$USERNAME was not deleted since 'destroy' (without single quotes) wasn't typed."
    fi
}

# the main loop
while true; do
    clear
    echo "What do you want to do?"
    echo ""
    PS3=' Enter a number >>> '
    options=("List users" "Add user and create directory" "Remove user and their files" "Quit")
    select opt in "${options[@]}"
    do
        case $opt in
            "List users")
                list_users
                sleep 3
                break
                ;;
            "Add user and create directory")
                add_user
                sleep 3
                break
                ;;
            "Remove user and their files")
                remove_user
                sleep 3
                break
                ;;
            "Quit")
                exit 0
                ;;
            *)
                echo "'$REPLY' isn't an option."
                ;;
        esac
    done
done
