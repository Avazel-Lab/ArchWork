#!/usr/bin/env bats
#
# Every test here makes a guard refuse. Tests that only prove the happy path
# would pass against a script with no guards at all.

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	export REPO_ROOT

	FIXTURE="$BATS_TEST_TMPDIR/fixture"
	mkdir -p "$FIXTURE/sys/block/vda" "$FIXTURE/dev"
	export ARCHWORK_SYS_BLOCK="$FIXTURE/sys/block"
	export ARCHWORK_DEV_PREFIX="$FIXTURE/dev/"
	export ARCHWORK_PROC_MOUNTS="$FIXTURE/mounts"
	: >"$ARCHWORK_PROC_MOUNTS"

	# A block device we can point guards at without owning a disk.
	mknod "$FIXTURE/dev/vda" b 254 0 2>/dev/null || skip "cannot create block device nodes here"
	mknod "$FIXTURE/dev/vda1" b 254 1 2>/dev/null || true

	# shellcheck source=/dev/null
	source "$REPO_ROOT/scripts/lib/guards.sh"
}

# guard_is_whole_disk

@test "refuses when no device is given" {
	run guard_is_whole_disk ""
	[ "$status" -ne 0 ]
	[[ "$output" == *"never defaults a device path"* ]]
}

@test "refuses a relative path" {
	run guard_is_whole_disk "vda"
	[ "$status" -ne 0 ]
	[[ "$output" == *"absolute path under"* ]]
}

@test "refuses a path outside the device tree" {
	run guard_is_whole_disk "/tmp/not-a-device"
	[ "$status" -ne 0 ]
	[[ "$output" == *"absolute path under"* ]]
}

@test "refuses a device that does not exist" {
	run guard_is_whole_disk "$FIXTURE/dev/doesnotexist"
	[ "$status" -ne 0 ]
	[[ "$output" == *"not a block device"* ]]
}

@test "refuses a partition rather than a whole disk" {
	# vda1 is a block device but has no /sys/block entry, which is exactly
	# how a partition presents itself.
	run guard_is_whole_disk "$FIXTURE/dev/vda1"
	[ "$status" -ne 0 ]
	[[ "$output" == *"partition or something this script cannot identify"* ]]
}

# guard_not_mounted

@test "refuses a mounted device" {
	echo "/dev/vda /mnt ext4 rw 0 0" >"$ARCHWORK_PROC_MOUNTS"
	run guard_not_mounted "/dev/vda"
	[ "$status" -ne 0 ]
	[[ "$output" == *"in use"* ]]
}

@test "refuses a device whose partition is mounted" {
	echo "/dev/vda1 /boot vfat rw 0 0" >"$ARCHWORK_PROC_MOUNTS"
	run guard_not_mounted "/dev/vda"
	[ "$status" -ne 0 ]
	[[ "$output" == *"/dev/vda1 on /boot"* ]]
}

@test "refuses when the mount table cannot be read" {
	export ARCHWORK_PROC_MOUNTS="$FIXTURE/nonexistent"
	run guard_not_mounted "/dev/vda"
	[ "$status" -ne 0 ]
	[[ "$output" == *"cannot prove"* ]]
}

@test "accepts an unmounted device" {
	echo "/dev/sdb1 /mnt ext4 rw 0 0" >"$ARCHWORK_PROC_MOUNTS"
	run guard_not_mounted "/dev/vda"
	[ "$status" -eq 0 ]
}

# guard_not_boot_medium

@test "refuses the medium the system booted from" {
	echo "/dev/vda1 /run/archiso/bootmnt iso9660 ro 0 0" >"$ARCHWORK_PROC_MOUNTS"
	run guard_not_boot_medium "/dev/vda"
	[ "$status" -ne 0 ]
	[[ "$output" == *"booted from"* ]]
}

@test "refuses a device carrying the running root" {
	echo "/dev/vda2 / btrfs rw 0 0" >"$ARCHWORK_PROC_MOUNTS"
	run guard_not_boot_medium "/dev/vda"
	[ "$status" -ne 0 ]
}

# guard_virtual_or_acknowledged

@test "refuses bare metal without the override flag" {
	systemd-detect-virt() { echo none; }
	export -f systemd-detect-virt
	run guard_virtual_or_acknowledged "false"
	[ "$status" -ne 0 ]
	[[ "$output" == *"--i-know-this-wipes-my-disk"* ]]
}

@test "accepts bare metal with the override flag" {
	systemd-detect-virt() { echo none; }
	export -f systemd-detect-virt
	run guard_virtual_or_acknowledged "true"
	[ "$status" -eq 0 ]
}

@test "accepts a virtual machine without the override flag" {
	systemd-detect-virt() { echo kvm; }
	export -f systemd-detect-virt
	run guard_virtual_or_acknowledged "false"
	[ "$status" -eq 0 ]
	[[ "$output" == *"kvm"* ]]
}

# guard_confirm_target

@test "refuses when the typed confirmation does not match" {
	run bash -c "source '$REPO_ROOT/scripts/lib/guards.sh'; echo '/dev/wrong' | guard_confirm_target '/dev/vda'"
	[ "$status" -ne 0 ]
	[[ "$output" == *"Nothing was written"* ]]
}

@test "refuses an empty confirmation" {
	run bash -c "source '$REPO_ROOT/scripts/lib/guards.sh'; echo '' | guard_confirm_target '/dev/vda'"
	[ "$status" -ne 0 ]
}

@test "accepts a confirmation that matches exactly" {
	run bash -c "source '$REPO_ROOT/scripts/lib/guards.sh'; echo '/dev/vda' | guard_confirm_target '/dev/vda'"
	[ "$status" -eq 0 ]
}

# guard_check_all short-circuits on the first refusal

@test "check_all refuses a mounted device before asking about virtualisation" {
	echo "$FIXTURE/dev/vda /mnt ext4 rw 0 0" >"$ARCHWORK_PROC_MOUNTS"
	systemd-detect-virt() { echo none; }
	export -f systemd-detect-virt
	run guard_check_all "$FIXTURE/dev/vda" "false"
	[ "$status" -ne 0 ]
	[[ "$output" != *"--i-know-this-wipes-my-disk"* ]]
}
