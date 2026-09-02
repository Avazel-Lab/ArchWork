#!/usr/bin/env bash
# Whether a directory can hold a run to the end.
#
# This is host-side, unlike lib/checks.sh next to it, which is copied onto the
# guest and asserts things about the machine being built. Nothing here ever
# leaves this machine.
#
# It exists because the hazard was already documented and that was not enough.
# prepare_work_dir has carried a comment since M1 saying that a tmpfs TMPDIR
# puts the guest disk in RAM, and on 2026-09-01 a run went into /tmp anyway,
# filled a 16 GiB tmpfs, and QEMU paused the guest on ENOSPC. It sat paused for
# nine and a half hours looking exactly like a slow run. D-017 makes the same
# argument about loadkeys: a trap that is documented is still a trap, and
# removing it is worth doing.

# What a run actually needs. The guest disk reached 9.8 GiB on the M4 runs, and
# --repeat keeps the previous run's image until the next one starts, so the
# floor is two of them plus room for the qcow2 to grow past what we have seen.
WORK_DIR_MIN_GIB="${WORK_DIR_MIN_GIB:-24}"

# Injectable so the unit tests can answer for a filesystem this machine has not
# got. On a machine it is always the real one.
DF="${DF:-df}"

work_dir_free_gib() {
	"$DF" -Pk "$1" 2>/dev/null | awk 'NR == 2 { printf "%d", $4 / 1048576 }'
}

work_dir_fstype() {
	"$DF" -PT "$1" 2>/dev/null | awk 'NR == 2 { print $2 }'
}

# Prints nothing and returns 0 when the directory will do. Otherwise prints why
# on stdout and returns 1, so the caller can put it in its own error.
work_dir_refusal() {
	local dir="$1" free fstype

	if [ ! -d "$dir" ]; then
		printf '%s does not exist' "$dir"
		return 1
	fi

	fstype="$(work_dir_fstype "$dir")"
	if [ "$fstype" = "tmpfs" ] || [ "$fstype" = "ramfs" ]; then
		printf '%s is %s, which is RAM. The guest disk grows past 9 GiB, so a run there competes with the machine for memory and stops the moment the filesystem fills' \
			"$dir" "$fstype"
		return 1
	fi

	free="$(work_dir_free_gib "$dir")"
	if [ -z "$free" ]; then
		printf 'cannot read how much space %s has' "$dir"
		return 1
	fi
	if [ "$free" -lt "$WORK_DIR_MIN_GIB" ]; then
		printf '%s has %s GiB free and a run needs %s' \
			"$dir" "$free" "$WORK_DIR_MIN_GIB"
		return 1
	fi

	return 0
}
