#!/bin/bash

# Post-Install Cleanup
bash -c "$(wget -qLO - https://github.com/community-scripts/ProxmoxVE/raw/main/misc/post-pve-install.sh)"

# Kernel Cleanup
bash -c "$(wget -qLO - https://github.com/community-scripts/ProxmoxVE/raw/main/misc/kernel-clean.sh)"

# Install Microcode
bash -c "$(wget -qLO - https://github.com/community-scripts/ProxmoxVE/raw/main/misc/microcode.sh)"

# Install and Configure Syncthing
apt install extrepo
extrepo enable syncthing
apt update
apt install syncthing

adduser syncthing
systemctl enable syncthing@syncthing.service --now
while ! systemctl status syncthing@syncthing.service | grep -q "GUI"; do sleep 1; done
sed -i -e 's/<address>127\.0\.0\.1:8384<\/address>/<address>0.0.0.0:8384<\/address>/' /home/syncthing/.local/state/syncthing/config.xml
systemctl restart syncthing@syncthing.service --now

# Install Netdata
wget -O /tmp/netdata-kickstart.sh https://my-netdata.io/kickstart.sh && sh /tmp/netdata-kickstart.sh --stable-channel --disable-telemetry

# Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh
tailscale up