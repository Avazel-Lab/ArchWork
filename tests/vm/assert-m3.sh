#!/usr/bin/env bash
#
# M3 exit criteria that are asserted from inside the session.
#
# Runs inside the VM as root, after the harness has logged in by typing at the
# real greeter (D-021). Everything here therefore describes a session that a
# password went through PAM to open, which is what makes the keyring criterion
# below mean anything.
#
# What is not here: the criteria a person judges from the captures a run
# saves, and the ones the harness drives from outside because they need the
# framebuffer. Both are named in D-021.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source-path=SCRIPTDIR source=lib/checks.sh
source "$SCRIPT_DIR/lib/checks.sh"

USER_NAME="${1:-gary}"

printf '\nM3 session criteria, user %s\n\n' "$USER_NAME"

printf 'Session entry (D-004, D-021)\n'
check "greetd is running" systemctl is-active greetd
check "a wayland session is open and active" graphical_session_open "$USER_NAME"
check "the session belongs to seat0" session_on_seat "$USER_NAME" seat0
check "Hyprland is running as the user" user_process_running "$USER_NAME" Hyprland
check "the compositor answers hyprctl" compositor_answers "$USER_NAME"
check "a wayland socket exists in the runtime directory" wayland_socket_present "$USER_NAME"

printf '\nThe wallpaper, which is the keybinding cheat sheet\n'
check "hyprpaper is running as the user" user_process_running "$USER_NAME" hyprpaper
check "hyprpaper.conf is the one in the repository clone" \
	config_is_repo_dotfile "/home/$USER_NAME/.config/hypr/hyprpaper.conf" "$USER_NAME"
# Loaded, not merely configured. A hyprpaper that could not read its image is
# still a running hyprpaper, and an unreadable cheat sheet helps nobody.
check "the sheet is loaded and not just named in the config" \
	hyprpaper_loaded "$USER_NAME" wallpaper-keybindings.png

printf '\nSecret Service (D-004, D-012)\n'
check "gnome-keyring-daemon is running as the user" user_process_running "$USER_NAME" gnome-keyring-d
check "the Secret Service is on the session bus" secret_service_present "$USER_NAME"
check "the login keyring is unlocked, so nothing prompts a second time" keyring_unlocked "$USER_NAME"

printf '\nTailscale alongside NetworkManager (D-002, D-019, D-022)\n'
check "tailscaled is enabled at boot" systemctl is-enabled tailscaled.service
check "tailscaled is running" systemctl is-active tailscaled.service
check "the daemon answers, signed in or not" tailscale_daemon_answers
check "the tailscale interface exists" tailscale_interface_present
check "NetworkManager is still running" systemctl is-active NetworkManager.service
check "the default route is not Tailscale's" default_route_not_via tailscale0
check "systemd-resolved is still masked" unit_is_masked systemd-resolved.service
check "names still resolve without it" name_resolution_works archlinux.org

printf '\nDesktop integration (desktop-shell.md)\n'
check "the desktop portal answers on the session bus" portal_answers "$USER_NAME"
check "grim captures the screen from inside the session" screenshot_works "$USER_NAME"

printf '\n'
if [ "$CHECK_FAILURES" -eq 0 ]; then
	printf 'All M3 session criteria pass.\n'
	exit 0
fi

printf '%d M3 session criteria failed.\n' "$CHECK_FAILURES"
exit 1
