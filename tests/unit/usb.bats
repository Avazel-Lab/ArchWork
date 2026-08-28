#!/usr/bin/env bats
#
# The installation medium writer, and the removable-device guard it adds.
#
# Nothing here needs CAP_MKNOD. tests/unit/guards.bats has to create block
# device nodes and skips wholesale when it cannot, which is how eighteen guard
# tests once reported green in CI without running. These tests exercise the
# sysfs fixture and the argument handling instead, so they run everywhere.

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	export REPO_ROOT

	FIXTURE="$BATS_TEST_TMPDIR/fixture"
	mkdir -p "$FIXTURE/sys/block/sdc" "$FIXTURE/sys/block/nvme0n1" "$FIXTURE/dev"
	export ARCHWORK_SYS_BLOCK="$FIXTURE/sys/block"
	export ARCHWORK_DEV_PREFIX="$FIXTURE/dev/"
	export ARCHWORK_PROC_MOUNTS="$FIXTURE/mounts"
	: >"$ARCHWORK_PROC_MOUNTS"

	# A USB stick reports 1, an internal disk reports 0.
	echo 1 >"$FIXTURE/sys/block/sdc/removable"
	echo 0 >"$FIXTURE/sys/block/nvme0n1/removable"

	ISO="$BATS_TEST_TMPDIR/archlinux.iso"
	printf 'not really an iso' >"$ISO"

	# shellcheck source=/dev/null
	source "$REPO_ROOT/scripts/lib/guards.sh"
}

usb() {
	run bash "$REPO_ROOT/scripts/make-install-usb.sh" "$@"
}

# guard_is_removable_or_acknowledged

@test "refuses an internal disk" {
	run guard_is_removable_or_acknowledged "$FIXTURE/dev/nvme0n1" "false"
	[ "$status" -ne 0 ]
	[[ "$output" == *"reports removable=0"* ]]
}

@test "refuses a device sysfs says nothing about" {
	run guard_is_removable_or_acknowledged "$FIXTURE/dev/sdz" "false"
	[ "$status" -ne 0 ]
	[[ "$output" == *"cannot prove"* ]]
}

@test "an unreadable removable flag is not excused by the override" {
	# The override permits a device that says it is not removable. It does
	# not permit a device that says nothing, because that is the case where
	# the script cannot identify the target with certainty.
	run guard_is_removable_or_acknowledged "$FIXTURE/dev/sdz" "true"
	[ "$status" -ne 0 ]
	[[ "$output" == *"cannot prove"* ]]
}

@test "accepts an internal disk with the override flag" {
	run guard_is_removable_or_acknowledged "$FIXTURE/dev/nvme0n1" "true"
	[ "$status" -eq 0 ]
	[[ "$output" == *"--i-know-this-wipes-my-disk was given"* ]]
}

@test "accepts a removable stick without the override flag" {
	run guard_is_removable_or_acknowledged "$FIXTURE/dev/sdc" "false"
	[ "$status" -eq 0 ]
}

# make-install-usb.sh argument handling, all of it before any guard runs

@test "refuses without an image" {
	usb --dry-run "$FIXTURE/dev/sdc"
	[ "$status" -ne 0 ]
	[[ "$output" == *"--iso is required"* ]]
}

@test "refuses an image it cannot read" {
	usb --dry-run --iso "$BATS_TEST_TMPDIR/absent.iso" "$FIXTURE/dev/sdc"
	[ "$status" -ne 0 ]
	[[ "$output" == *"cannot read the ISO"* ]]
}

@test "refuses a directory given as the image" {
	usb --dry-run --iso "$BATS_TEST_TMPDIR" "$FIXTURE/dev/sdc"
	[ "$status" -ne 0 ]
	[[ "$output" == *"not a regular file"* ]]
}

@test "refuses two device paths" {
	usb --dry-run --iso "$ISO" "$FIXTURE/dev/sdc" "$FIXTURE/dev/sdd"
	[ "$status" -ne 0 ]
	[[ "$output" == *"more than one device given"* ]]
}

@test "refuses an unknown option" {
	usb --write-it-anyway --iso "$ISO" "$FIXTURE/dev/sdc"
	[ "$status" -ne 0 ]
	[[ "$output" == *"unknown option"* ]]
}

@test "refuses a checksum that does not match, before writing anything" {
	usb --dry-run --iso "$ISO" --sha256 0000000000000000000000000000000000000000000000000000000000000000 \
		"$FIXTURE/dev/sdc"
	[ "$status" -ne 0 ]
	[[ "$output" == *"checksum mismatch"* ]]
	[[ "$output" != *"would run"* ]]
}

@test "a matching checksum gets past verification and on to the device guards" {
	local sum
	sum="$(sha256sum "$ISO" | cut -d' ' -f1)"
	usb --dry-run --iso "$ISO" --sha256 "$sum" "$FIXTURE/dev/sdc"
	# $FIXTURE/dev/sdc is a path, not a device node, so guard_is_whole_disk
	# refuses next. That is the point: verification passed, and the run still
	# stopped before writing.
	[ "$status" -ne 0 ]
	[[ "$output" == *"ISO matches"* ]]
	[[ "$output" == *"not a block device"* ]]
	[[ "$output" != *"would run"* ]]
}

@test "a real write needs root" {
	if [ "$(id -u)" -eq 0 ]; then
		# Running as root, so prove the refusal is not raised instead.
		usb --iso "$ISO" "$FIXTURE/dev/sdc"
		[[ "$output" != *"needs root"* ]]
		return 0
	fi

	usb --iso "$ISO" "$FIXTURE/dev/sdc"
	[ "$status" -ne 0 ]
	[[ "$output" == *"needs root"* ]]
}

@test "help exits clean and names the override" {
	usb --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"--i-know-this-wipes-my-disk"* ]]
}
