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
apt-get install -y ustreamer git python3-numpy python3-matplotlib libatlas-base-dev

# Add user 'mks'
useradd -m -G sudo -s /bin/bash mks || true

# Set password for both 'mks' and 'root' to 'makerbase'
echo 'mks:makerbase' | chpasswd
echo 'root:makerbase' | chpasswd

# Add 'mks' to 'gpio' and 'spiusers' groups, create groups if they don't exist
groupadd gpio || true
groupadd spiusers || true
usermod -a -G gpio,spiusers mks

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

mkdir /home/mks

# Clone Git repository as user 'mks'
su - mks -c "git clone https://github.com/halfmanbear/OpenNept4une.git /home/mks/OpenNept4une"
