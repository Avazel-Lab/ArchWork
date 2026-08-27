#!/usr/bin/env bash
# Guards for scripts that write to block devices.
#
# Sourced by scripts/archwork-install.sh. Kept separate so that bats can test
# every refusal without root and without a disk. A guard that has never
# refused anything is decoration.
#
# Every function here returns non-zero with a message on stderr rather than
# exiting, so callers decide what a refusal means.

set -euo pipefail

# Where to look for block devices. Overridable so tests can point at a fixture
# tree instead of the real /sys.
: "${ARCHWORK_SYS_BLOCK:=/sys/block}"
: "${ARCHWORK_PROC_MOUNTS:=/proc/mounts}"
: "${ARCHWORK_DEV_PREFIX:=/dev/}"

guard_err() {
	printf 'refused: %s\n' "$1" >&2
	return 1
}

# A whole disk, not a partition, and one the kernel actually knows about.
guard_is_whole_disk() {
	local device="${1:-}"

	if [ -z "$device" ]; then
		guard_err "no target device given. This script never defaults a device path."
		return 1
	fi

	case "$device" in
	"$ARCHWORK_DEV_PREFIX"*) ;;
	*)
		guard_err "target must be an absolute path under ${ARCHWORK_DEV_PREFIX%/}, got '$device'"
		return 1
		;;
	esac

	if [ ! -b "$device" ]; then
		guard_err "'$device' is not a block device"
		return 1
	fi

	local name="${device#"$ARCHWORK_DEV_PREFIX"}"
	name="${name//\//!}"

	if [ ! -d "$ARCHWORK_SYS_BLOCK/$name" ]; then
		guard_err "'$device' has no entry in $ARCHWORK_SYS_BLOCK, so it is a partition or something this script cannot identify with certainty"
		return 1
	fi

	return 0
}

# Refuse anything currently mounted, including its partitions.
guard_not_mounted() {
	local device="${1:-}"
	local mounted=""

	if [ ! -r "$ARCHWORK_PROC_MOUNTS" ]; then
		guard_err "cannot read $ARCHWORK_PROC_MOUNTS, so cannot prove '$device' is unmounted"
		return 1
	fi

	# Match the device itself and any partition of it, so /dev/vda catches
	# /dev/vda1. Trailing digits or a p-prefixed number are partitions.
	while read -r source target _; do
		case "$source" in
		"$device" | "$device"[0-9]* | "$device"p[0-9]*)
			mounted="$mounted $source on $target,"
			;;
		esac
	done <"$ARCHWORK_PROC_MOUNTS"

	if [ -n "$mounted" ]; then
		guard_err "'$device' is in use:${mounted%,}"
		return 1
	fi

	return 0
}

# Refuse the medium we booted from. Wiping the running ISO is a bad afternoon.
guard_not_boot_medium() {
	local device="${1:-}"

	if guard_not_mounted "$device" >/dev/null 2>&1; then
		return 0
	fi

	while read -r source target _; do
		case "$target" in
		/run/archiso/* | /run/initramfs/* | /)
			case "$source" in
			"$device" | "$device"[0-9]* | "$device"p[0-9]*)
				guard_err "'$device' is the medium this system booted from"
				return 1
				;;
			esac
			;;
		esac
	done <"$ARCHWORK_PROC_MOUNTS"

	return 0
}

# A virtual machine, or an explicit acknowledgement. Nothing else.
guard_virtual_or_acknowledged() {
	local acknowledged="${1:-false}"
	local virt

	virt="$(systemd-detect-virt 2>/dev/null || echo none)"

	if [ "$virt" != "none" ]; then
		printf 'running in a virtual machine (%s)\n' "$virt"
		return 0
	fi

	if [ "$acknowledged" = "true" ]; then
		printf 'not a virtual machine, but --i-know-this-wipes-my-disk was given\n'
		return 0
	fi

	guard_err "this is not a virtual machine. Pass --i-know-this-wipes-my-disk if you mean it."
	return 1
}

# Show the operator what they are about to destroy, then make them type it back.
# Reading a device path back is deliberate: y/n is too easy to answer wrongly.
guard_confirm_target() {
	local device="${1:-}"
	local answer=""

	printf '\nAbout to destroy every byte on %s\n\n' "$device"
	lsblk --nodeps --output NAME,SIZE,MODEL,SERIAL "$device" 2>/dev/null || true
	printf '\nCurrent partition table:\n'
	sfdisk --dump "$device" 2>/dev/null || printf '  (none, or unreadable)\n'
	printf '\nType the device path to confirm, anything else to abort: '

	read -r answer

	if [ "$answer" != "$device" ]; then
		guard_err "confirmation did not match. Nothing was written."
		return 1
	fi

	return 0
}

# Run every non-interactive guard. The confirmation prompt stays separate so a
# dry run can skip it.
guard_check_all() {
	local device="${1:-}"
	local acknowledged="${2:-false}"

	guard_is_whole_disk "$device" || return 1
	guard_not_mounted "$device" || return 1
	guard_not_boot_medium "$device" || return 1
	guard_virtual_or_acknowledged "$acknowledged" || return 1

	return 0
}
