#!/usr/bin/env bats
#
# The key mapping, proven without QEMU.
#
# sendkey names keys by position and the guest's keymap decides what they
# type, so a mapping bug does not announce itself: it types a different
# password, and the run reports a login that did not work with nothing to say
# why. --print renders the commands without a monitor, which is what makes
# that testable anywhere.

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	SENDKEY="$REPO_ROOT/tests/vm/sendkey.py"
	FAKE_MONITOR="$BATS_TEST_DIRNAME/fixtures/fake-monitor.py"
}

teardown() {
	if [ -n "${FAKE_PID:-}" ]; then
		kill "$FAKE_PID" 2>/dev/null || true
	fi
}

@test "types lower case, digits and the hyphen" {
	run python3 "$SENDKEY" --print --text "gary-1"
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "sendkey g" ]
	[ "${lines[4]}" = "sendkey minus" ]
	[ "${lines[5]}" = "sendkey 1" ]
}

@test "shifts for capitals" {
	run python3 "$SENDKEY" --print --text "Ab"
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "sendkey shift-a" ]
	[ "${lines[1]}" = "sendkey b" ]
}

@test "presses return after the text when asked" {
	run python3 "$SENDKEY" --print --text "x" --enter
	[ "$status" -eq 0 ]
	[ "${lines[1]}" = "sendkey ret" ]
}

@test "refuses a character whose key moves between the uk and us layouts" {
	# The trap this guards against: the installer sets KEYMAP=uk, where this
	# key types " rather than @. A password holding one would be typed wrongly
	# and the failure would look like a greeter that rejected a good password.
	run python3 "$SENDKEY" --print --text 'user@host'
	[ "$status" -eq 2 ]
	[[ "$output" == *"uk and us"* ]]
}

@test "presses a keybinding, modifiers and all" {
	# How the harness reaches a desktop keybinding: meta_l is what Hyprland
	# calls SUPER, so this is SUPER + Return, the terminal bind.
	run python3 "$SENDKEY" --print --key meta_l-ret
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "sendkey meta_l-ret" ]
}

@test "refuses a key name it does not know" {
	run python3 "$SENDKEY" --print --key "any" --text "x"
	[ "$status" -eq 2 ]
	[[ "$output" == *"unknown key"* ]]
}

@test "refuses a modifier it does not know" {
	# QEMU would reject this too, and the run would report a desktop that did
	# not respond to a keybinding rather than a typo in the test.
	run python3 "$SENDKEY" --print --key "hyper-x"
	[ "$status" -eq 2 ]
	[[ "$output" == *"unknown modifier"* ]]
}

@test "refuses to send with nothing to type" {
	run python3 "$SENDKEY" --print
	[ "$status" -ne 0 ]
}

@test "will not send without a monitor socket" {
	run python3 "$SENDKEY" --text "x"
	[ "$status" -ne 0 ]
	[[ "$output" == *"--monitor"* ]]
}

@test "sends one key per character over the monitor socket" {
	# Against a stand-in that greets and prompts the way QEMU's monitor does.
	# --print stops short of the socket, and the socket is where the greeter
	# login either works or hangs, so it gets a test of its own.
	python3 "$FAKE_MONITOR" "$BATS_TEST_TMPDIR/monitor.sock" "$BATS_TEST_TMPDIR/received" &
	FAKE_PID=$!

	local waited=0
	while [ ! -S "$BATS_TEST_TMPDIR/monitor.sock" ]; do
		sleep 0.1
		waited=$((waited + 1))
		[ "$waited" -gt 50 ] && fail "the stand-in monitor never opened its socket"
	done

	run python3 "$SENDKEY" \
		--monitor "$BATS_TEST_TMPDIR/monitor.sock" \
		--text "hunter2" --enter --delay 0
	[ "$status" -eq 0 ]

	[ "$(head -1 "$BATS_TEST_TMPDIR/received")" = "sendkey h" ]
	[ "$(tail -1 "$BATS_TEST_TMPDIR/received")" = "sendkey ret" ]
	[ "$(wc -l <"$BATS_TEST_TMPDIR/received")" -eq 8 ]

	# It types passwords, so what it reports is a count. Run logs get pasted
	# into issues and commit messages.
	[[ "$output" == *"typed 7 character(s)"* ]]
	[[ "$output" != *"hunter2"* ]]
}
