#!/usr/bin/env bats
#
# The update workflow's ordering and its stopping points.
#
# M5's first exit criterion is a sequence: snapshot, Arch, AUR, reconcile,
# health. The order is the safety property, so these tests assert the order and
# where it stops, not that pacman works.

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	export REPO_ROOT
	SCRIPT="$REPO_ROOT/scripts/archwork-update"

	# Every external step becomes a stub that appends its name to a log, so a
	# test can read back what ran and in what order.
	ORDER="$BATS_TEST_TMPDIR/order"
	export ORDER
	: >"$ORDER"

	stub() {
		local name="$1" exit_code="${2:-0}"
		local path="$BATS_TEST_TMPDIR/$name"
		cat >"$path" <<-SH
			#!/usr/bin/env bash
			printf '%s\n' "$name" >> "\$ORDER"
			exit $exit_code
		SH
		chmod +x "$path"
		printf '%s' "$path"
	}
}

run_update() {
	PACMAN="$PACMAN_STUB" PARU="$PARU_STUB" \
		ARCHWORK_SNAPSHOT="$SNAPSHOT_STUB" ARCHWORK_HEALTH="$HEALTH_STUB" \
		run bash "$SCRIPT" "$@"
}

default_stubs() {
	PACMAN_STUB="$(stub pacman)"
	PARU_STUB="$(stub paru)"
	SNAPSHOT_STUB="$(stub snapshot)"
	HEALTH_STUB="$(stub health)"

	# The AUR step drops privileges with runuser, which needs real root. The
	# stub strips "-u USER --" and runs the rest, which is what runuser does
	# once it has changed user.
	cat >"$BATS_TEST_TMPDIR/runuser" <<-'SH'
		#!/usr/bin/env bash
		while [ $# -gt 0 ]; do
			case "$1" in
			-u) shift 2 ;;
			--) shift; break ;;
			*) break ;;
			esac
		done
		exec "$@"
	SH
	chmod +x "$BATS_TEST_TMPDIR/runuser"
}

@test "it refuses to run without root, rather than half updating" {
	default_stubs
	if [ "$(id -u)" -eq 0 ]; then skip "these tests assume an unprivileged runner"; fi
	run_update --skip-reconcile
	[ "$status" -ne 0 ]
	[[ "$output" == *"needs root"* ]]
}

@test "a dry run touches nothing and still names every step" {
	default_stubs
	run_update --dry-run --skip-reconcile
	[ "$status" -eq 0 ]
	[[ "$output" == *"Pre-update snapshot"* ]]
	[[ "$output" == *"Arch packages"* ]]
	[[ "$output" == *"AUR packages"* ]]
	[[ "$output" == *"Health checks"* ]]
	# would run, not ran.
	[[ "$output" == *"would run"* ]]
	[ ! -s "$ORDER" ]
}

# The root check is injectable like every other external command, so the real
# path can be driven without a root test runner.
fake_root() {
	local fake="$BATS_TEST_TMPDIR/id"
	printf '#!/usr/bin/env bash\necho 0\n' >"$fake"
	chmod +x "$fake"
	printf '%s' "$fake"
}

run_as_root() {
	ID="$(fake_root)" PACMAN="$PACMAN_STUB" PARU="$PARU_STUB" \
		ARCHWORK_SNAPSHOT="$SNAPSHOT_STUB" ARCHWORK_HEALTH="$HEALTH_STUB" \
		run bash "$SCRIPT" "$@"
}

@test "the steps run in the order the criterion states" {
	# M5's first exit criterion is a sequence, and the order is the safety
	# property: a snapshot taken after pacman protects nothing.
	default_stubs
	PATH="$BATS_TEST_TMPDIR:$PATH" run_as_root --skip-reconcile
	[ "$status" -eq 0 ]
	run cat "$ORDER"
	[ "${lines[0]}" = "snapshot" ]
	[ "${lines[1]}" = "pacman" ]
	[ "${lines[2]}" = "paru" ]
	[ "${lines[3]}" = "health" ]
}

@test "a failed pacman stops the run and says the snapshot is the way back" {
	default_stubs
	PACMAN_STUB="$(stub pacman 1)"
	PATH="$BATS_TEST_TMPDIR:$PATH" run_as_root --skip-reconcile
	[ "$status" -ne 0 ]
	[[ "$output" == *"snapshot above is the way back"* ]]
	# Nothing after pacman may have run.
	run cat "$ORDER"
	[[ "$output" != *"paru"* ]]
	[[ "$output" != *"health"* ]]
}

@test "a snapshot that fails stops the update before anything is changed" {
	# Someone running this asked for the safe workflow by name, so a broken
	# safety net is worth stopping for. set -e used to do this by accident and
	# without a message, which is not the same thing.
	default_stubs
	SNAPSHOT_STUB="$(stub snapshot 1)"
	PATH="$BATS_TEST_TMPDIR:$PATH" run_as_root --skip-reconcile
	[ "$status" -ne 0 ]
	[[ "$output" == *"nothing has been updated"* ]]
	run cat "$ORDER"
	[[ "$output" != *"pacman"* ]]
}

@test "--no-snapshot updates anyway, and says what that costs" {
	default_stubs
	SNAPSHOT_STUB="$(stub snapshot 1)"
	PATH="$BATS_TEST_TMPDIR:$PATH" run_as_root --skip-reconcile --no-snapshot
	[ "$status" -eq 0 ]
	[[ "$output" == *"no way back"* ]]
	run cat "$ORDER"
	[[ "$output" == *"pacman"* ]]
	# The snapshot must not have been attempted at all.
	[[ "$output" != *"snapshot"* ]]
}

@test "a missing snapshot script stops the update rather than skipping it" {
	# The dangerous shape: "not installed" reading as "nothing to do".
	default_stubs
	SNAPSHOT_STUB="$BATS_TEST_TMPDIR/not-installed"
	PATH="$BATS_TEST_TMPDIR:$PATH" run_as_root --skip-reconcile
	[ "$status" -ne 0 ]
	[[ "$output" == *"no way back"* ]]
	run cat "$ORDER"
	[[ "$output" != *"pacman"* ]]
}

@test "failing health checks fail the run and name the way back" {
	default_stubs
	HEALTH_STUB="$(stub health 1)"
	PATH="$BATS_TEST_TMPDIR:$PATH" run_as_root --skip-reconcile
	[ "$status" -ne 0 ]
	[[ "$output" == *"archwork-rollback"* ]]
}

@test "a missing clone is refused before anything is changed" {
	default_stubs
    # No --skip-reconcile and a repo path that does not exist: the script has
    # to notice before it snapshots or updates, not after.
	PACMAN="$PACMAN_STUB" PARU="$PARU_STUB" \
		ARCHWORK_SNAPSHOT="$SNAPSHOT_STUB" ARCHWORK_HEALTH="$HEALTH_STUB" \
		run bash "$SCRIPT" --repo "$BATS_TEST_TMPDIR/nothing-here" --dry-run
	[ "$status" -ne 0 ]
	[[ "$output" == *"not an ArchWork clone"* ]]
	[ ! -s "$ORDER" ]
}

@test "help exits clean and describes the order" {
	run bash "$SCRIPT" --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"pre-update Btrfs snapshot"* ]]
	[[ "$output" == *"health checks"* ]]
}

@test "an unknown option is refused rather than ignored" {
	run bash "$SCRIPT" --definitely-not-an-option
	[ "$status" -ne 0 ]
	[[ "$output" == *"unknown option"* ]]
}
