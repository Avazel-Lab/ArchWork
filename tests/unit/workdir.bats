#!/usr/bin/env bats
#
# The guard that stops a run starting somewhere it cannot finish.
#
# On 2026-09-01 a vm-power run went into /tmp, which is a 16 GiB tmpfs on the
# development machine, filled it, and QEMU paused the guest on ENOSPC. From
# outside, a paused guest and a slow one are the same thing, so it sat there
# for nine and a half hours. prepare_work_dir had carried a comment about
# exactly this hazard since M1. These are the tests for it being a check.

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	export REPO_ROOT
	# shellcheck source=../vm/lib/workdir.sh
	source "$REPO_ROOT/tests/vm/lib/workdir.sh"
	WORK_DIR_MIN_GIB=24
}

# A df that answers for a filesystem this machine has not got. The real one
# takes -Pk for space and -PT for type, so the fake has to tell them apart.
fake_df() {
	local fstype="$1" free_gib="$2"
	local fake="$BATS_TEST_TMPDIR/df"
	cat >"$fake" <<-SH
		#!/usr/bin/env bash
		if [ "\$1" = "-PT" ]; then
			echo "Filesystem Type 1024-blocks Used Available Capacity Mounted"
			echo "/dev/fake $fstype 100 100 100 50% /fake"
		else
			echo "Filesystem 1024-blocks Used Available Capacity Mounted"
			echo "/dev/fake 100 100 $((free_gib * 1048576)) 50% /fake"
		fi
	SH
	chmod +x "$fake"
	DF="$fake"
}

@test "a roomy disk-backed directory is accepted" {
	fake_df ext4 200
	run work_dir_refusal "$BATS_TEST_TMPDIR"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "a tmpfs is refused however much of it there is" {
	# The failure that actually happened. 16 GiB looks like plenty until two
	# runs want 10 each, and it is RAM either way.
	fake_df tmpfs 400
	run work_dir_refusal "$BATS_TEST_TMPDIR"
	[ "$status" -ne 0 ]
	[[ "$output" == *"RAM"* ]]
	[[ "$output" == *"tmpfs"* ]]
}

@test "ramfs is refused on the same grounds" {
	fake_df ramfs 400
	run work_dir_refusal "$BATS_TEST_TMPDIR"
	[ "$status" -ne 0 ]
	[[ "$output" == *"RAM"* ]]
}

@test "a real disk without room is refused, and says how much there is" {
	fake_df ext4 9
	run work_dir_refusal "$BATS_TEST_TMPDIR"
	[ "$status" -ne 0 ]
	[[ "$output" == *"9 GiB free"* ]]
	[[ "$output" == *"24"* ]]
}

@test "exactly the minimum is enough, one less is not" {
	fake_df btrfs 24
	run work_dir_refusal "$BATS_TEST_TMPDIR"
	[ "$status" -eq 0 ]

	fake_df btrfs 23
	run work_dir_refusal "$BATS_TEST_TMPDIR"
	[ "$status" -ne 0 ]
}

@test "a directory that is not there is refused rather than created" {
	fake_df ext4 200
	run work_dir_refusal "$BATS_TEST_TMPDIR/nothing-here"
	[ "$status" -ne 0 ]
	[[ "$output" == *"does not exist"* ]]
}

@test "a df that says nothing is a refusal, not a pass" {
	# The dangerous direction: an unreadable filesystem must not read as a
	# roomy one.
	local fake="$BATS_TEST_TMPDIR/df"
	printf '#!/usr/bin/env bash\nexit 1\n' >"$fake"
	chmod +x "$fake"
	DF="$fake"
	run work_dir_refusal "$BATS_TEST_TMPDIR"
	[ "$status" -ne 0 ]
	[[ "$output" == *"cannot read"* ]]
}

# What happens to the work directory when a run ends.
#
# The rule is that a run which failed keeps its disk and a run which passed
# throws it away, because the disk of a failed run is the only thing that can
# be asked what went wrong. Run 21 left one behind, and booting it and reading
# the guest's journal is what found D-037 after three guesses made from
# outside had all been wrong.

@test "a run that failed keeps its work directory, even without --keep" {
	run work_dir_disposition 1 false
	[ "$status" -eq 0 ]
	[ "$output" = "keep-failed" ]
}

@test "a run that failed keeps it whatever --keep says" {
	run work_dir_disposition 1 true
	[ "$output" = "keep-failed" ]
}

@test "any non-zero status counts as failed, not just 1" {
	run work_dir_disposition 137 false
	[ "$output" = "keep-failed" ]
}

@test "a run that passed throws its 28 GB disk away" {
	run work_dir_disposition 0 false
	[ "$output" = "discard" ]
}

@test "a run that passed keeps it when --keep asked, which is what --resume needs" {
	run work_dir_disposition 0 true
	[ "$output" = "keep-asked" ]
}
