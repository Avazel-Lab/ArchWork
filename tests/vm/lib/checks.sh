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
