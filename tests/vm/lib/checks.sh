#!/usr/bin/env bash
#
# Assertion helpers for the VM checks. A library: nothing here runs on its own.
#
# These live apart from assert-m1.sh so that each is a named predicate rather
# than an inline shell expression, which keeps the assertion list readable and
# keeps quoting out of it.

CHECK_FAILURES=0

check() {
	local description="$1"
	shift

	if "$@" >/dev/null 2>&1; then
		printf '  ok    %s\n' "$description"
	else
		printf '  FAIL  %s\n' "$description"
		CHECK_FAILURES=$((CHECK_FAILURES + 1))
	fi
}

# For criteria stated as an absence, such as no @swap on the desktop.
check_not() {
	local description="$1"
	shift

	if "$@" >/dev/null 2>&1; then
		printf '  FAIL  %s\n' "$description"
		CHECK_FAILURES=$((CHECK_FAILURES + 1))
	else
		printf '  ok    %s\n' "$description"
	fi
}

has_subvolume() {
	btrfs subvolume list / | awk '{print $NF}' | grep -qx "$1"
}

mount_has_option() {
	findmnt --noheadings --output OPTIONS --target "$1" | grep -q "$2"
}

file_contains() {
	grep -q "$2" "$1"
}

file_matches() {
	grep -qE "$2" "$1"
}

swap_active_on() {
	swapon --show=NAME --noheadings | grep -q "$1"
}

root_is_luks2() {
	local slave
	for slave in /sys/class/block/*/slaves/*; do
		[ -e "$slave" ] || continue
		if cryptsetup luksDump "/dev/${slave##*/}" 2>/dev/null | grep -q 'Version:.*2'; then
			return 0
		fi
	done
	return 1
}

root_fstype_is() {
	findmnt --noheadings --output FSTYPE / | grep -qx "$1"
}

# The subvolume a path actually resolves to, so that /var/lib can be compared
# against /. findmnt reports it in brackets after the device.
subvolume_of() {
	findmnt --noheadings --output SOURCE --target "$1" | sed -n 's/.*\[\(.*\)\]/\1/p'
}

# /var/lib must roll back with @. If it sits on its own subvolume then a
# rollback of @ leaves /var/lib/pacman describing packages that are not on
# disk, and every later update fights the filesystem.
var_lib_rolls_back_with_root() {
	[ "$(subvolume_of /)" = "$(subvolume_of /var/lib)" ]
}

# A leftover @TOKEN@ in the command line means the installer substituted
# nothing there, which is an unbootable or silently broken system.
check_no_token() {
	! grep -qE '@[A-Z_]+@' "$1"
}

check_recovery_no_autodetect() {
	! grep -q autodetect /etc/mkinitcpio-recovery.conf
}

# D-016: the machine configures itself, so it must arrive able to do so.
repo_present() {
	test -d "/home/$1/src/ArchWork/.git"
}

repo_owned_by_user() {
	[ "$(stat -c '%U' "/home/$1/src/ArchWork")" = "$1" ]
}

# A clone keeps its source as origin, which on the target is a path on the ISO
# that no longer exists. It works perfectly until the first git pull.
repo_origin_is_upstream() {
	local origin
	origin="$(git -C "/home/$1/src/ArchWork" remote get-url origin 2>/dev/null)"
	case "$origin" in
	"" | /* | file:*) return 1 ;;
	*) return 0 ;;
	esac
}

command_installed() {
	command -v "$1" >/dev/null 2>&1
}

# --- The graphical session (M3, D-021) --------------------------------------
#
# These assertions arrive over SSH, which is outside the graphical session and
# inherits nothing from it: no runtime directory, no bus address, no Hyprland
# instance. Each has to be handed in, so the helpers below build that
# environment rather than every check repeating it.

session_runtime_dir() {
	printf '/run/user/%s' "$(id -u "$1")"
}

# Hyprland names its socket directory after the instance signature. Newest
# first, so a directory left by an earlier crashed instance does not win.
hypr_signature() {
	local dir
	dir="$(session_runtime_dir "$1")/hypr"
	[ -d "$dir" ] || return 1

	find "$dir" -mindepth 1 -maxdepth 1 -printf '%T@ %f\n' 2>/dev/null |
		sort -rn | head -1 | cut -d' ' -f2- | grep .
}

wayland_display() {
	local runtime socket
	runtime="$(session_runtime_dir "$1")"
	for socket in "$runtime"/wayland-*; do
		case "$socket" in
		*.lock) continue ;;
		esac
		[ -S "$socket" ] || continue
		basename "$socket"
		return 0
	done
	return 1
}

as_user() {
	local user="$1" runtime
	shift
	runtime="$(session_runtime_dir "$user")"

	runuser -u "$user" -- env \
		XDG_RUNTIME_DIR="$runtime" \
		DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime/bus" \
		"$@"
}

# For anything that has to talk to the compositor: hyprctl finds its instance
# through the signature, and Wayland clients through the display name.
as_user_in_session() {
	local user="$1" signature display
	shift
	signature="$(hypr_signature "$user")" || return 1
	display="$(wayland_display "$user")" || return 1

	as_user "$user" env \
		HYPRLAND_INSTANCE_SIGNATURE="$signature" \
		WAYLAND_DISPLAY="$display" \
		"$@"
}

user_process_running() {
	pgrep -u "$1" -x "$2" >/dev/null 2>&1
}

# A session logind opened, rather than a process that happens to be running.
# Only the former means a password went through PAM.
graphical_session_open() {
	local user="$1" id
	while read -r id; do
		[ -n "$id" ] || continue
		[ "$(loginctl show-session "$id" --property=Name --value)" = "$user" ] || continue
		[ "$(loginctl show-session "$id" --property=Type --value)" = "wayland" ] || continue
		[ "$(loginctl show-session "$id" --property=Active --value)" = "yes" ] || continue
		return 0
	done < <(loginctl list-sessions --no-legend | awk '{print $1}')
	return 1
}

session_on_seat() {
	local user="$1" seat="$2" id
	while read -r id; do
		[ -n "$id" ] || continue
		[ "$(loginctl show-session "$id" --property=Name --value)" = "$user" ] || continue
		[ "$(loginctl show-session "$id" --property=Seat --value)" = "$seat" ] || continue
		return 0
	done < <(loginctl list-sessions --no-legend | awk '{print $1}')
	return 1
}

compositor_answers() {
	as_user_in_session "$1" hyprctl version >/dev/null
}

wayland_socket_present() {
	wayland_display "$1" >/dev/null
}

secret_service_present() {
	as_user "$1" timeout 15 gdbus call --session \
		--dest org.freedesktop.DBus \
		--object-path /org/freedesktop/DBus \
		--method org.freedesktop.DBus.GetNameOwner \
		org.freedesktop.secrets >/dev/null 2>&1
}

# D-012: the password typed at greetd unlocked the keyring through PAM. A
# keyring that exists but is locked would prompt at first use, which is the
# second prompt D-004 accepted a login password in order to avoid, so Locked
# being false is the entire criterion.
keyring_unlocked() {
	local reply
	reply="$(as_user "$1" timeout 15 gdbus call --session \
		--dest org.freedesktop.secrets \
		--object-path /org/freedesktop/secrets/collection/login \
		--method org.freedesktop.DBus.Properties.Get \
		org.freedesktop.Secret.Collection Locked 2>/dev/null)" || return 1

	case "$reply" in
	*false*) return 0 ;;
	*) return 1 ;;
	esac
}

# Weaker than the M3 criterion, which asks for a file picker from a GTK and a
# Qt application. This says the portal is reachable and activates, which is
# what has to be true before any picker can open.
portal_answers() {
	as_user "$1" timeout 20 gdbus call --session \
		--dest org.freedesktop.portal.Desktop \
		--object-path /org/freedesktop/portal/desktop \
		--method org.freedesktop.DBus.Peer.Ping >/dev/null 2>&1
}

screenshot_works() {
	local target="/tmp/archwork-m3-screenshot.png"
	rm -f "$target"
	as_user_in_session "$1" grim "$target" >/dev/null 2>&1 || return 1
	[ -s "$target" ]
}

# A window the compositor has, rather than a process that started. A terminal
# that launched and then died leaves the process check happy and the screen
# empty, which is the failure worth catching.
client_class_present() {
	as_user_in_session "$1" hyprctl -j clients 2>/dev/null |
		jq -e --arg class "$2" 'any(.[]; .class == $class)' >/dev/null 2>&1
}

client_class_absent() {
	! client_class_present "$1" "$2"
}

process_absent() {
	! user_process_running "$1" "$2"
}

user_unit_active() {
	as_user "$1" systemctl --user is-active --quiet "$2"
}
