#!/usr/bin/env bats
#
# The sleep timing is the one M4 criterion the guest cannot measure, so it is
# measured here, against QEMU's monitor. That makes this script the only
# evidence that the 30 minute timeout is 30 minutes, and it gets tested
# against a fake monitor rather than trusted.
#
# No QEMU: fixtures/fake-monitor.py speaks the same protocol.

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	WATCH="$REPO_ROOT/tests/vm/suspend-watch.py"
	FAKE_MONITOR="$BATS_TEST_DIRNAME/fixtures/fake-monitor.py"
	SOCKET="$BATS_TEST_TMPDIR/monitor.sock"
	RECORD="$BATS_TEST_TMPDIR/commands"
	REPLIES="$BATS_TEST_TMPDIR/replies"
}

teardown() {
	if [ -n "${FAKE_PID:-}" ]; then
		kill "$FAKE_PID" 2>/dev/null || true
	fi
}

# The fake monitor echoes once its canned replies run out, and an echo is not
# a status line. A test that watches for a whole deadline therefore has to
# supply more replies than the poll interval can consume.
repeated() {
	local count="$1" text="$2" n
	for n in $(seq 1 "$count"); do
		printf '%s\n' "$text"
	done
}

start_fake_monitor() {
	printf '%s\n' "$@" >"$REPLIES"
	python3 "$FAKE_MONITOR" "$SOCKET" "$RECORD" "$REPLIES" &
	FAKE_PID=$!
	local attempt
	for attempt in $(seq 1 50); do
		[ -S "$SOCKET" ] && return 0
		sleep 0.1
	done
	return 1
}

@test "reports the seconds a guest took to suspend" {
	start_fake_monitor "VM status: running" "VM status: running" "VM status: suspended"
	run python3 "$WATCH" --monitor "$SOCKET" --wait 30 --poll 0.1
	[ "$status" -eq 0 ]
	# The elapsed seconds, which the harness compares against the window.
	[[ "$output" =~ ^[0-9]+$ ]]
	grep -q "info status" "$RECORD"
}

@test "fails when the guest never suspends, and says what it was doing" {
	local lines
	mapfile -t lines < <(repeated 40 "VM status: running")
	start_fake_monitor "${lines[@]}"
	run python3 "$WATCH" --monitor "$SOCKET" --wait 1 --poll 0.1
	[ "$status" -ne 0 ]
	[[ "$output" == *"still 'running'"* ]]
}

@test "a paused guest is not a suspended one" {
	# QEMU pauses a guest for reasons that have nothing to do with S3, and a
	# run that counted one as sleep would report a timing that never happened.
	local lines
	mapfile -t lines < <(repeated 40 "VM status: paused")
	start_fake_monitor "${lines[@]}"
	run python3 "$WATCH" --monitor "$SOCKET" --wait 1 --poll 0.1
	[ "$status" -ne 0 ]
	[[ "$output" == *"still 'paused'"* ]]
}

@test "waking sends system_wakeup and waits for the guest to be running again" {
	start_fake_monitor "" "VM status: running"
	run python3 "$WATCH" --monitor "$SOCKET" --wake
	[ "$status" -eq 0 ]
	grep -q "system_wakeup" "$RECORD"
}

@test "refuses without something to do" {
	run python3 "$WATCH" --monitor "$SOCKET"
	[ "$status" -ne 0 ]
	[[ "$output" == *"--wait"* ]]
}
