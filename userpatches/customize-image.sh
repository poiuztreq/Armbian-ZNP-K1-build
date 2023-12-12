#!/bin/bash

# NOTE: If you want to transfer files between chroot and host
# userpatches/overlay directory on host is bind-mounted to /tmp/overlay in chroot
# The sd card's root path is accessible via $SDCARD variable.

RELEASE=$1
LINUXFAMILY=$2
BOARD=$3
BUILD_DESKTOP=$4

Main() {
    InstallNeptune4Setup
    esac
} # Main

InstallNeptune4Setup()
{
    # Update package list
    apt-get update

    # Install ustreamer, git, and Python packages
    apt-get install -y ustreamer git python3-numpy python3-matplotlib libatlas-base-dev

    # Add user 'mks'
    useradd -m -G sudo -s /bin/bash mks

    # Set password for both 'mks' and 'root' to 'makerbase'
    echo 'mks:makerbase' | chpasswd
    echo 'root:makerbase' | chpasswd

    # Add 'mks' to 'gpio' group, create group if it doesn't exist
    groupadd gpio || true
    usermod -a -G gpio mks

    # Add 'mks' to 'spiusers' group, create group if it doesn't exist
    groupadd spiusers || true
    usermod -a -G spiusers mks

    # GPIO script setup
    SetupGpioScript

    # Add cron job to run sync command every 10 minutes
    SetupCronJob

    # Clone OpenNept4une repository
    CloneOpenNept4une
} # Installx

SetupGpioScript()
{
    # Path of the script to be created
    SCRIPT_PATH="/usr/local/bin/set_gpio.sh"

    # Create and write the GPIO command to the script
    echo -e "#!/bin/bash\n/usr/bin/gpioset gpiochip1 14=0; /usr/bin/gpioset gpiochip1 15=0; sleep 0.5; /usr/bin/gpioset gpiochip1 15=1" | sudo tee "$SCRIPT_PATH" >/dev/null

    # Make the script executable
    sudo chmod +x "$SCRIPT_PATH"

    # Check if /etc/rc.local exists
    RC_LOCAL="/etc/rc.local"
    if [ ! -f "$RC_LOCAL" ]; then
        # Create /etc/rc.local if it doesn't exist
        echo "#!/bin/bash" | sudo tee "$RC_LOCAL" >/dev/null
        echo "exit 0" | sudo tee -a "$RC_LOCAL" >/dev/null
        sudo chmod +x "$RC_LOCAL"
    fi

    # Insert the script path before 'exit 0' in /etc/rc.local
    sudo sed -i "/^exit 0/i $SCRIPT_PATH" "$RC_LOCAL"
}

SetupCronJob()
{
    # Add cron job to run sync command every 10 minutes
    CRON_ENTRY="*/10 * * * * /bin/sync"
    if ! (crontab -l 2>/dev/null | grep -F "/bin/sync"); then
        (crontab -l 2>/dev/null; echo "$CRON_ENTRY") | crontab -
        echo "Sync command added to the crontab to run every 10 minutes."
    else
        echo "The sync command is already in the crontab."
    fi
}

CloneOpenNept4une()
{
    su - mks -c "git clone https://github.com/halfmanbear/OpenNept4une.git /home/mks/OpenNept4une"
}

Main "$@"
