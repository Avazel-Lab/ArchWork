#!/usr/bin/env bats
#
# How the installer names the partitions it is about to create.
#
# This exists because the rule was wrong for exactly the device path D-017
# tells the operator to use. partition_path appends a number, and p before it
# when the path ends in a digit, which is right for /dev/vda1 and
# /dev/nvme0n1p1 and wrong for a by-id path: udev names those SERIAL-part1,
# and the serial ends in a letter often enough that no rule about digits can
# see it.
#
# Getting that wrong destroys the partition table and then fails, because
# sfdisk runs before the first mkfs. Hence tests rather than a careful read.

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	export REPO_ROOT
	INSTALLER="$REPO_ROOT/scripts/archwork-install.sh"
}

# partition_path reads TARGET_DEVICE from the script's scope, so the function
# is pulled out and called rather than the whole installer being run.
partition_path_for() {
	TARGET_DEVICE="$1"
	# shellcheck disable=SC2016 # the body is extracted verbatim, not expanded here
	eval "$(sed -n '/^partition_path()/,/^}/p' "$INSTALLER")"
	partition_path "$2"
}

@test "a sata disk takes a bare number" {
	run partition_path_for /dev/sda 1
	[ "$output" = "/dev/sda1" ]
}

@test "an nvme disk takes p before the number" {
	run partition_path_for /dev/nvme0n1 2
	[ "$output" = "/dev/nvme0n1p2" ]
}

@test "a virtio disk takes a bare number" {
	run partition_path_for /dev/vda 1
	[ "$output" = "/dev/vda1" ]
}

@test "resolve_target_device turns a by-id path into a kernel name" {
	# The shape of the failure this prevents: a by-id path ending in a letter
	# would have produced SERIAL1, and udev makes SERIAL-part1.
	local link="$BATS_TEST_TMPDIR/nvme-Model_2TB_S4J4NX0R804138P"
	local target="$BATS_TEST_TMPDIR/nvme0n1"
	: >"$target"
	ln -s "$target" "$link"

	TARGET_DEVICE="$link"
	TARGET_DEVICE_GIVEN=""
	die() {
		printf '%s\n' "$1" >&2
		return 1
	}
	eval "$(sed -n '/^resolve_target_device()/,/^}/p' "$INSTALLER")"
	resolve_target_device

	[ "$TARGET_DEVICE" = "$target" ]
	[ "$TARGET_DEVICE_GIVEN" = "$link" ]
}

@test "a resolved by-id path then names its partitions correctly" {
	local link="$BATS_TEST_TMPDIR/nvme-Model_2TB_S4J4NX0R804138P"
	local target="$BATS_TEST_TMPDIR/nvme0n1"
	: >"$target"
	ln -s "$target" "$link"

	TARGET_DEVICE="$link"
	TARGET_DEVICE_GIVEN=""
	die() { return 1; }
	eval "$(sed -n '/^resolve_target_device()/,/^}/p' "$INSTALLER")"
	resolve_target_device

	eval "$(sed -n '/^partition_path()/,/^}/p' "$INSTALLER")"
	run partition_path 1
	[ "$output" = "$target"p1 ]
}

@test "an unresolvable device is refused rather than guessed at" {
	TARGET_DEVICE="$BATS_TEST_TMPDIR/no-such-disk"
	TARGET_DEVICE_GIVEN=""
	die() {
		printf '%s\n' "$1" >&2
		exit 1
	}
	eval "$(sed -n '/^resolve_target_device()/,/^}/p' "$INSTALLER")"

	run resolve_target_device
	[ "$status" -ne 0 ]
}
