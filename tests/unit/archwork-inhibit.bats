#!/usr/bin/env bats
#
# archwork-inhibit never touches a real systemd --user manager here: systemctl
# and systemd-run are stubbed on PATH, and each call is logged so a test can
# check what was asked for rather than what a real logind session did with it.

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

	FAKE_BIN="$BATS_TEST_TMPDIR/bin"
	mkdir -p "$FAKE_BIN"
	CALL_LOG="$BATS_TEST_TMPDIR/calls.log"
	: >"$CALL_LOG"
	export CALL_LOG
	ACTIVE_FILE="$BATS_TEST_TMPDIR/active"
	export ACTIVE_FILE

	cat >"$FAKE_BIN/systemctl" <<'FAKE'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >>"$CALL_LOG"
case "$*" in
*"is-active --quiet archwork-inhibit.service"*)
	[ -f "$ACTIVE_FILE" ]
	exit $?
	;;
*"show archwork-inhibit.service --property=Description --value"*)
	cat "$ACTIVE_FILE" 2>/dev/null
	exit 0
	;;
*"stop archwork-inhibit.service"*)
	rm -f "$ACTIVE_FILE"
	exit 0
	;;
esac
exit 0
FAKE
	chmod +x "$FAKE_BIN/systemctl"

	cat >"$FAKE_BIN/systemd-run" <<FAKE
#!/usr/bin/env bash
printf 'systemd-run %s\n' "\$*" >>"$CALL_LOG"
for arg in "\$@"; do
	case "\$arg" in
	--description=*) printf '%s\n' "\${arg#--description=}" >"$ACTIVE_FILE" ;;
	esac
done
exit 0
FAKE
	chmod +x "$FAKE_BIN/systemd-run"

	PATH="$FAKE_BIN:$PATH"
	export PATH
	ARCHWORK_LIB_ONLY=1
	export ARCHWORK_LIB_ONLY
	# shellcheck source=/dev/null
	source "$REPO_ROOT/scripts/archwork-inhibit"
}

@test "refuses an unknown duration" {
	run start "3d"
	[ "$status" -ne 0 ]
	[[ "$output" == *"unknown duration"* ]]
}

@test "refuses with no argument at all" {
	run main
	[ "$status" -ne 0 ]
	[[ "$output" == *"a duration or an option is required"* ]]
}

@test "1h holds sleep for 3600 seconds" {
	run start "1h"
	[ "$status" -eq 0 ]
	grep -q 'sleep 3600' <(grep systemd-run "$CALL_LOG")
}

@test "2h holds sleep for 7200 seconds" {
	run start "2h"
	[ "$status" -eq 0 ]
	grep -q 'sleep 7200' <(grep systemd-run "$CALL_LOG")
}

@test "4h holds sleep for 14400 seconds" {
	run start "4h"
	[ "$status" -eq 0 ]
	grep -q 'sleep 14400' <(grep systemd-run "$CALL_LOG")
}

@test "indefinite holds sleep with no time limit at all" {
	run start "indefinite"
	[ "$status" -eq 0 ]
	grep -q 'sleep infinity' <(grep systemd-run "$CALL_LOG")
	[[ "$output" == *"manually re-enabled"* ]]
}

@test "only --what=sleep is ever inhibited" {
	run start "1h"
	[ "$status" -eq 0 ]
	grep -q -- '--what=sleep' <(grep systemd-run "$CALL_LOG")
}

@test "a second start replaces the first rather than stacking" {
	start "1h" >/dev/null
	run start "2h"
	[ "$status" -eq 0 ]
	[ "$(grep -c systemctl "$CALL_LOG")" -ge 1 ]
	grep -q 'stop archwork-inhibit.service' "$CALL_LOG"
}

@test "--status reports no inhibition before anything starts" {
	run status
	[ "$status" -eq 0 ]
	[[ "$output" == *"not inhibited"* ]]
}

@test "--status reports the held lock once one starts" {
	start "1h" >/dev/null
	run status
	[ "$status" -eq 0 ]
	[[ "$output" == *"Sleep inhibited until"* ]]
}

@test "--cancel ends an active inhibition" {
	start "1h" >/dev/null
	run cancel
	[ "$status" -eq 0 ]
	run status
	[[ "$output" == *"not inhibited"* ]]
}

@test "--cancel is harmless with nothing active" {
	run cancel
	[ "$status" -eq 0 ]
}

@test "--help exits clean and names every duration" {
	run main --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"1h"* ]]
	[[ "$output" == *"2h"* ]]
	[[ "$output" == *"4h"* ]]
	[[ "$output" == *"indefinite"* ]]
}
