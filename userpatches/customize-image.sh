#!/bin/bash

# NOTE: If you want to transfer files between chroot and host
# userpatches/overlay directory on host is bind-mounted to /tmp/overlay in chroot
# The SD card's root path is accessible via $SDCARD variable.

# Function to handle errors
handle_error() {
    echo "Error occurred in script at line: $1"
    exit 1
}

# Trap errors
trap 'handle_error $LINENO' ERR

# Copy DTB files to the boot partition
cp /tmp/overlay/boot/dtb/rockchip/*.dtb $SDCARD/boot/dtb/rockchip/

# Copy rules files to the rules.d folder
cp /tmp/overlay/etc/udev/rules.d/*.rules $SDCARD/etc/udev/rules.d/

# Update package list and install packages
apt-get update
apt-get install -y ustreamer git python3-numpy python3-matplotlib libatlas-base-dev git

# Add user 'mks'
sudo adduser --gecos "" --disabled-password mks
sudo usermod -c "mks" mks

# Set the user's login shell to bash
sudo usermod -s /bin/bash mks

# Manually create home directory for 'mks' if it doesn't exist
home_dir="${SDCARD}/home/mks"
if [ ! -d "$home_dir" ]; then
    sudo mkdir "$home_dir"
    sudo chown mks:mks "$home_dir"
    sudo chmod 750 "$home_dir"
    sudo cp -a /etc/skel/. "$home_dir/"
    sudo chown -R mks:mks "$home_dir"
fi

# Set password for both 'mks' and 'root' to 'makerbase'
echo 'mks:makerbase' | chpasswd
echo 'root:makerbase' | chpasswd

rm -f /root/.not_logged_in_yet

# Add 'mks' to 'gpio' and 'spiusers' groups, create groups if they don't exist
sudo groupadd gpio || true
sudo groupadd spiusers || true
sudo usermod -aG sudo,netdev,audio,video,dialout,plugdev,disk,games,users,systemd-journal,input,gpio,spiusers mks

# Create and configure GPIO script
SCRIPT_PATH="/usr/local/bin/set_gpio.sh"
echo -e "#!/bin/bash\n/usr/bin/gpioset gpiochip1 14=0; /usr/bin/gpioset gpiochip1 15=0; sleep 0.5; /usr/bin/gpioset gpiochip1 15=1" > "$SCRIPT_PATH"
chmod +x "$SCRIPT_PATH"

# Configure /etc/rc.local for startup script execution
RC_LOCAL="/etc/rc.local"
if [ ! -f "$RC_LOCAL" ]; then
    echo -e "#!/bin/bash\n\nexit 0" > "$RC_LOCAL"
    chmod +x "$RC_LOCAL"
fi
sed -i "/^exit 0/i $SCRIPT_PATH" "$RC_LOCAL"

# Add cron job to run sync command every 10 minutes
CRON_ENTRY="*/10 * * * * /bin/sync"
(crontab -l 2>/dev/null | grep -qF "$CRON_ENTRY") || (crontab -l 2>/dev/null; echo "$CRON_ENTRY") | crontab -

# Clone Git repository as user 'mks'
git clone https://github.com/halfmanbear/OpenNept4une.git /home/mks/OpenNept4une
