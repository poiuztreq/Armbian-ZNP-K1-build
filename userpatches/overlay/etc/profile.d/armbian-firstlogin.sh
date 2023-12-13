#!/bin/bash
#
# Copyright (c) Authors: https://www.armbian.com/authors
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

# read distribution status
# shellcheck source=/dev/null
[[ -f /etc/lsb-release ]] && . /etc/lsb-release
[[ -f /etc/os-release ]] && . /etc/os-release
[[ -z "$DISTRIB_CODENAME" ]] && DISTRIB_CODENAME="${VERSION_CODENAME}"
[[ -n "$DISTRIB_CODENAME" && -f /etc/armbian-distribution-status ]] && DISTRIBUTION_STATUS=$(grep "$DISTRIB_CODENAME" /etc/armbian-distribution-status | cut -d"=" -f2)

. /etc/armbian-release

check_abort() {
    echo -e "\nDisabling user account creation procedure\n"
    rm -f /root/.not_logged_in_yet
    trap - INT
    exit 0
}

set_shell() {
    USER_SHELL="bash"
    SHELL_PATH="/bin/bash"
    chsh -s "${SHELL_PATH}"
    sed -i "s|^SHELL=.*|SHELL=${SHELL_PATH}|" /etc/default/useradd
    sed -i "s|^DSHELL=.*|DSHELL=${SHELL_PATH}|" /etc/adduser.conf
}

add_profile_sync_settings() {
	if [[ ! -f /usr/bin/psd ]]; then
		return 0
	fi

	/usr/bin/psd > /dev/null 2>&1
	config_file="${HOME}/.config/psd/psd.conf"
	if [ -f "${config_file}" ]; then
		# test for overlayfs
		sed -i 's/#USE_OVERLAYFS=.*/USE_OVERLAYFS="yes"/' "${config_file}"
		case $(/usr/bin/psd p 2> /dev/null | grep Overlayfs) in
			*active*)
				echo -e "\nConfigured profile sync daemon with overlayfs."
				;;
			*)
				echo -e "\nConfigured profile sync daemon."
				sed -i 's/USE_OVERLAYFS="yes"/#USE_OVERLAYFS="no"/' "${config_file}"
				;;
		esac
	fi
	systemctl --user enable psd.service > /dev/null 2>&1
	systemctl --user start psd.service > /dev/null 2>&1
}

add_user() {
    RealUserName="mks"
    RealName="mks"
    adduser --quiet --disabled-password --home /home/"$RealUserName" --gecos "$RealName" "$RealUserName"
    echo "makerbase" | passwd "$RealUserName" --stdin
    for additionalgroup in sudo netdev audio video disk tty users games dialout plugdev input bluetooth systemd-journal ssh gpio spi-dev; do
        usermod -aG "${additionalgroup}" "${RealUserName}"
    done
    echo -e "\nUser \e[0;92m${RealName}\x1B[0m (\e[0;92m${RealUserName}\x1B[0m) has been created with sudo privileges."
}

if [[ -f /root/.not_logged_in_yet && -n $(tty) ]]; then
	# disable autologin
	rm -f /etc/systemd/system/getty@.service.d/override.conf
	rm -f /etc/systemd/system/serial-getty@.service.d/override.conf
	systemctl daemon-reload

	declare desktop_dm="none"
	declare -i desktop_is_sddm=0 desktop_is_lightdm=0 desktop_is_gdm3=0
	if [[ -f /usr/bin/sddm ]]; then
		desktop_dm="sddm"
		desktop_is_sddm=1
	fi
	if [[ -f /usr/sbin/lightdm ]]; then
		desktop_dm="lightdm"
		desktop_is_lightdm=1
	fi
	if [[ -f /usr/sbin/gdm3 ]]; then
		desktop_dm="gdm3"
		desktop_is_gdm3=1
	fi

	echo -e "\nWaiting for system to finish booting ..."
	systemctl is-system-running --wait > /dev/null

	# enable hiDPI support
	if [[ "$(cut -d, -f1 < /sys/class/graphics/fb0/virtual_size 2> /dev/null)" -gt 1920 ]]; then
		# lightdm
		[[ -f /etc/lightdm/slick-greeter.conf ]] && echo "enable-hidpi = on" >> /etc/lightdm/slick-greeter.conf
		# xfce
		[[ -f /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml ]] && sed -i 's|<property name="WindowScalingFactor" type="int" value=".*|<property name="WindowScalingFactor" type="int" value="2">|g' /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml

		# framebuffer console larger font
		setfont /usr/share/consolefonts/Uni3-TerminusBold32x16.psf.gz
	fi

	clear

	echo -e "Welcome to \e[1m\e[97m${VENDOR}\x1B[0m! \n"
	echo -e "Documentation: \e[1m\e[92m${VENDORDOCS}\x1B[0m | Community support: \e[1m\e[92m${VENDORSUPPORT}\x1B[0m\n"
	GET_IP=$(bash /etc/update-motd.d/30-armbian-sysinfo | grep IP | sed "s/.*IP://" | sed 's/^[ \t]*//')
	[[ -n "$GET_IP" ]] && echo -e "IP address: $GET_IP\n"

	trap '' 2
	REPEATS=3
	while [ -f "/root/.not_logged_in_yet" ]; do

		read_password "Create root"

		# only allow one login. Once you enter root password, kill others.
		loginfrom=$(who am i | awk '{print $2}')
		who -la | grep root | grep -v "$loginfrom" | awk '{print $7}' | xargs --no-run-if-empty kill -9

		first_input="makerbase"
		echo ""
		read_password "Repeat root"
		second_input="makerbase"
		echo ""
		if [[ "$first_input" == "$second_input" ]]; then
			# minimal might not have this
			if command -v cracklib-check > /dev/null 2>&1; then
				result="$(cracklib-check <<< "$second_input")"
				okay="$(awk -F': ' '{ print $2}' <<< "$result")"
				if [[ "$okay" != "OK" ]]; then
					echo -e "\n\e[0;31mWarning:\x1B[0m Weak password, $okay \b!"
				fi
			fi
			(
				echo "$first_input"
				echo "$second_input"
			) | passwd root > /dev/null 2>&1
			break
		elif [[ -n $second_input ]]; then
			echo -e "Rejected - \e[0;31mpasswords do not match.\x1B[0m Try again [${REPEATS}]."
			REPEATS=$((REPEATS - 1))
		fi
		[[ "$REPEATS" -eq 0 ]] && exit
	done
	trap - INT TERM EXIT

	# display support status
	if [ "$IMAGE_TYPE" != "nightly" ]; then
		if [[ "$BRANCH" == "edge" ]]; then
			echo -e "\nSupport status: \e[0;31mcommunity support\x1B[0m (edge kernel branch)"
		elif [[ "$DISTRIBUTION_STATUS" != "supported" ]]; then
			echo -e "\nSupport status: \e[0;31mcommunity support\x1B[0m (unsupported userspace)"
		elif [[ "$BOARD_TYPE" != "conf" ]]; then
			echo -e "\nSupport status: \e[0;31mcommunity support\x1B[0m (looking for a dedicated maintainer)"
		fi
	else

		echo -e "\e[0;31m\nWARNING!\x1B[0m\n\nYou are using an \e[0;31mautomated build\x1B[0m meant only for developers to provide"
		echo -e "constructive feedback to improve build system, OS settings or UX.\n"

		echo -e "If this does not apply to you, \e[0;31mSTOP NOW!\x1B[0m  Especially don't use this "
		echo -e "image for production since things might not work as expected or at "
		echo -e "all. They may  break anytime with next update."

	fi

	# ask user to select shell
	set_shell
 	add_user

	# re-enable passing locale environment via ssh
	sed -e '/^#AcceptEnv LANG/ s/^#//' -i /etc/ssh/sshd_config
	# restart sshd daemon
	systemctl reload ssh.service

	# rpardini: hacks per-dm, very much legacy stuff that works by a miracle
	if [[ "${desktop_dm}" == "lightdm" ]] && [ -n "$RealName" ]; then

		# 1st run goes without login
		mkdir -p /etc/lightdm/lightdm.conf.d
		cat <<- EOF > /etc/lightdm/lightdm.conf.d/22-armbian-autologin.conf
			[Seat:*]
			autologin-user=$RealUserName
			autologin-user-timeout=0
			user-session=xfce
		EOF

		# select gnome session (has to be first or it breaks budgie/cinnamon desktop autologin and user-session)
		# @TODO: remove this, gnome should use gdm3, not lightdm
		[[ -x $(command -v gnome-session) ]] && sed -i "s/user-session.*/user-session=ubuntu/" /etc/lightdm/lightdm.conf.d/11-armbian.conf
		[[ -x $(command -v gnome-session) ]] && sed -i "s/user-session.*/user-session=ubuntu/" /etc/lightdm/lightdm.conf.d/22-armbian-autologin.conf

		# select awesome session
		[[ -x $(command -v awesome) ]] && sed -i "s/user-session.*/user-session=awesome/" /etc/lightdm/lightdm.conf.d/11-armbian.conf
		[[ -x $(command -v awesome) ]] && sed -i "s/user-session.*/user-session=awesome/" /etc/lightdm/lightdm.conf.d/22-armbian-autologin.conf

		# select budgie session
		[[ -x $(command -v budgie-desktop) ]] && sed -i "s/user-session.*/user-session=budgie-desktop/" /etc/lightdm/lightdm.conf.d/11-armbian.conf
		[[ -x $(command -v budgie-desktop) ]] && sed -i "s/user-session.*/user-session=budgie-desktop/" /etc/lightdm/lightdm.conf.d/22-armbian-autologin.conf

		# select cinnamon session
		[[ -x $(command -v cinnamon) ]] && sed -i "s/user-session.*/user-session=cinnamon/" /etc/lightdm/lightdm.conf.d/11-armbian.conf
		[[ -x $(command -v cinnamon) ]] && sed -i "s/user-session.*/user-session=cinnamon/" /etc/lightdm/lightdm.conf.d/22-armbian-autologin.conf

		# select deepin session
		[[ -x $(command -v deepin-wm) ]] && sed -i "s/user-session.*/user-session=deepin/" /etc/lightdm/lightdm.conf.d/11-armbian.conf
		[[ -x $(command -v deepin-wm) ]] && sed -i "s/user-session.*/user-session=deepin/" /etc/lightdm/lightdm.conf.d/22-armbian-autologin.conf

		# select ice-wm session
		[[ -x $(command -v icewm-session) ]] && sed -i "s/user-session.*/user-session=icewm-session/" /etc/lightdm/lightdm.conf.d/11-armbian.conf
		[[ -x $(command -v icewm-session) ]] && sed -i "s/user-session.*/user-session=icewm-session/" /etc/lightdm/lightdm.conf.d/22-armbian-autologin.conf

		# select i3 session
		[[ -x $(command -v i3) ]] && sed -i "s/user-session.*/user-session=i3/" /etc/lightdm/lightdm.conf.d/11-armbian.conf
		[[ -x $(command -v i3) ]] && sed -i "s/user-session.*/user-session=i3/" /etc/lightdm/lightdm.conf.d/22-armbian-autologin.conf

		# select lxde session
		[[ -x $(command -v startlxde) ]] && sed -i "s/user-session.*/user-session=LXDE/" /etc/lightdm/lightdm.conf.d/11-armbian.conf
		[[ -x $(command -v startlxde) ]] && sed -i "s/user-session.*/user-session=LXDE/" /etc/lightdm/lightdm.conf.d/22-armbian-autologin.conf

		# select lxqt session
		[[ -x $(command -v startlxqt) ]] && sed -i "s/user-session.*/user-session=lxqt/" /etc/lightdm/lightdm.conf.d/11-armbian.conf
		[[ -x $(command -v startlxqt) ]] && sed -i "s/user-session.*/user-session=lxqt/" /etc/lightdm/lightdm.conf.d/22-armbian-autologin.conf

		# select mate session
		[[ -x $(command -v mate-wm) ]] && sed -i "s/user-session.*/user-session=mate/" /etc/lightdm/lightdm.conf.d/11-armbian.conf
		[[ -x $(command -v mate-wm) ]] && sed -i "s/user-session.*/user-session=mate/" /etc/lightdm/lightdm.conf.d/22-armbian-autologin.conf

		# select plasma wayland session # @TODO: rpardini: dead code? kde-plasma desktop should use sddm, not lightdm.
		[[ -x $(command -v plasmashell) ]] && sed -i "s/user-session.*/user-session=plasmawayland/" /etc/lightdm/lightdm.conf.d/11-armbian.conf
		[[ -x $(command -v plasmashell) ]] && sed -i "s/user-session.*/user-session=plasmawayland/" /etc/lightdm/lightdm.conf.d/22-armbian-autologin.conf

		# select sway wayland session
		[[ -x $(command -v sway) ]] && sed -i "s/user-session.*/user-session=sway/" /etc/lightdm/lightdm.conf.d/11-armbian.conf
		[[ -x $(command -v sway) ]] && sed -i "s/user-session.*/user-session=sway/" /etc/lightdm/lightdm.conf.d/22-armbian-autologin.conf

		# select xmonad session
		[[ -x $(command -v xmonad) ]] && sed -i "s/user-session.*/user-session=xmonad/" /etc/lightdm/lightdm.conf.d/11-armbian.conf
		[[ -x $(command -v xmonad) ]] && sed -i "s/user-session.*/user-session=xmonad/" /etc/lightdm/lightdm.conf.d/22-armbian-autologin.conf

		ln -sf /lib/systemd/system/lightdm.service /etc/systemd/system/display-manager.service

		if [[ -f /var/run/resize2fs-reboot ]]; then
			# Let the user reboot now otherwise start desktop environment
			printf "\n\n\e[0;91mWarning: a reboot is needed to finish resizing the filesystem \x1B[0m \n"
			printf "\e[0;91mPlease reboot the system now \x1B[0m \n\n"
		else
			echo -e "\n\e[1m\e[39mNow starting desktop environment...\x1B[0m\n"
			sleep 1
			service lightdm start 2> /dev/null
			if [ -f /root/.desktop_autologin ]; then
				rm /root/.desktop_autologin
			else
				systemctl -q enable armbian-disable-autologin.timer
				systemctl start armbian-disable-autologin.timer
			fi
			# logout if logged at console
			who -la | grep root | grep -q tty1 && exit 1
		fi

	elif [[ "${desktop_dm}" == "gdm3" ]] && [ -n "$RealName" ]; then
		# 1st run goes without login
		mkdir -p /etc/gdm3
		cat <<- EOF > /etc/gdm3/custom.conf
			[daemon]
			AutomaticLoginEnable = true
			AutomaticLogin = $RealUserName
		EOF

		ln -sf /lib/systemd/system/gdm3.service /etc/systemd/system/display-manager.service

		if [[ -f /var/run/resize2fs-reboot ]]; then
			# Let the user reboot now otherwise start desktop environment
			printf "\n\n\e[0;91mWarning: a reboot is needed to finish resizing the filesystem \x1B[0m \n"
			printf "\e[0;91mPlease reboot the system now \x1B[0m \n\n"
		else
			echo -e "\n\e[1m\e[39mNow starting desktop environment...\x1B[0m\n"
			sleep 1
			service gdm3 start 2> /dev/null
			if [ -f /root/.desktop_autologin ]; then
				rm /root/.desktop_autologin
			else
				(
					sleep 20
					sed -i "s/AutomaticLoginEnable.*/AutomaticLoginEnable = false/" /etc/gdm3/custom.conf
				) &
			fi
			# logout if logged at console
			who -la | grep root | grep -q tty1 && exit 1
		fi
	elif [[ "${desktop_dm}" == "sddm" ]] && [ -n "$RealName" ]; then
		# No hacks for sddm. User will have to input password again, and have  chance to choose session wayland
		echo -e "\n\e[1m\e[39mNow starting desktop environment via ${desktop_dm}...\x1B[0m\n"
		systemctl enable --now sddm
	else
		# no display manager detected
		# Display reboot recommendation if necessary
		if [[ -f /var/run/resize2fs-reboot ]]; then
			printf "\n\n\e[0;91mWarning: a reboot is needed to finish resizing the filesystem \x1B[0m \n"
			printf "\e[0;91mPlease reboot the system now \x1B[0m \n\n"
		fi
	fi
fi
f
