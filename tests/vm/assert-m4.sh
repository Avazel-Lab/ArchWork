#!/usr/bin/env bash
#
# The M4 exit criteria, measured rather than read.
#
# Runs inside the VM as root, in three parts, because the criteria are
# timings and the clock they run against is the compositor's idea of idle.
# Only real input resets that clock, and nothing inside the guest can produce
# real input: the keystroke comes from the harness through QEMU, and the
# epoch second it happened is handed in here as T0.
#
#   config      the shipped configuration, asserted before any waiting
#   inhibited   30 minutes idle with a sleep inhibitor held. Dim and
#               display-off must still fire; sleep must not
#   woke        after the harness has watched the machine suspend and woken
#               it again
#
# The sleep timing itself is not measured here. A guest cannot time its own
# suspend, so run-install.sh watches for it from outside and asserts the
# window. Everything that can be seen from in here is in here.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source-path=SCRIPTDIR source=lib/checks.sh
source "$SCRIPT_DIR/lib/checks.sh"

MODE="${1:-}"
USER_NAME="${2:-gary}"
T0="${3:-}"

CONF="/home/$USER_NAME/.config/hypr/hypridle.conf"

# The timings security-power.md states, in seconds, and the slack an
# observation is allowed. hypridle polls, the harness polls, and a VM under
# load is not a stopwatch, so a minute late is a pass and a second early is
# not: firing early means the listener is on a clock nobody asked for.
DIM_AT=300
DISPLAY_OFF_AT=900
SLEEP_AT=1800
SLACK=60

usage() {
	printf 'usage: assert-m4.sh config|inhibited|woke [USER] [T0_EPOCH]\n' >&2
	exit 2
}

# An observation with a window around it, reported as one line whether it
# passes, fails or times out.
check_timing() {
	local description="$1" expected="$2" deadline="$3"
	shift 3

	local observed
	if ! observed="$(seconds_until "$T0" "$deadline" "$@")"; then
		printf '  FAIL  %s\n        nothing happened within %ds of the keystroke\n' \
			"$description" "$deadline"
		CHECK_FAILURES=$((CHECK_FAILURES + 1))
		return 1
	fi

	if within_window "$observed" "$expected" "$((expected + SLACK))"; then
		printf '  ok    %s\n        at %ds, wanted %d to %d\n' \
			"$description" "$observed" "$expected" "$((expected + SLACK))"
		return 0
	fi

	printf '  FAIL  %s\n        at %ds, wanted %d to %d\n' \
		"$description" "$observed" "$expected" "$((expected + SLACK))"
	CHECK_FAILURES=$((CHECK_FAILURES + 1))
	return 1
}

assert_config() {
	printf '\nM4 configuration (D-028)\n'

	check "hypridle is running as the user" hypridle_running "$USER_NAME"
	check "hypridle.conf is the one in the repository clone" \
		config_is_repo_dotfile "$CONF" "$USER_NAME"
	check "a listener dims at ${DIM_AT}s" \
		hypridle_listener_has "$CONF" "$DIM_AT" brightnessctl
	check "a listener switches the display off at ${DISPLAY_OFF_AT}s" \
		hypridle_listener_has "$CONF" "$DISPLAY_OFF_AT" 'action = "off"'
	check "a listener sleeps at ${SLEEP_AT}s" \
		hypridle_listener_has "$CONF" "$SLEEP_AT" 'systemctl suspend'
	check "the inhibit control is installed" test -x /usr/local/bin/archwork-inhibit
	check "nothing is inhibiting sleep before the run starts" sleep_inhibitor_absent
	check "the display is on before the run starts" all_monitors_dpms "$USER_NAME" true
}

# The third criterion, which is the one with a mechanism worth doubting:
# "while inhibited, the display still dims and still switches off. Only sleep
# is suppressed." Nothing in the code couples the inhibitor to the two
# listeners, so this is here to catch a future change that couples them.
assert_inhibited() {
	printf '\nM4 timings under a held sleep inhibitor, idle since T0\n'

	check "systemd-inhibit --list shows a sleep lock in block mode" sleep_inhibitor_held
	check "the lock is the one archwork-inhibit holds" sleep_inhibitor_is_ours

	if backlight_present; then
		check_timing "the display dims" "$DIM_AT" "$((DIM_AT + SLACK))" \
			backlight_at_or_below 15
	else
		skip "the display dims at ${DIM_AT}s" \
			"no backlight device, so brightnessctl no-ops here and nothing observable changes (D-028). The listener is asserted in the configuration check above and nowhere else."
	fi

	check_timing "the display switches off" "$DISPLAY_OFF_AT" "$((DISPLAY_OFF_AT + SLACK))" \
		all_monitors_dpms "$USER_NAME" false

	# Past the sleep timeout, with slack, and still here to say so.
	local target="$((T0 + SLEEP_AT + SLACK))" now
	now="$(date +%s)"
	if [ "$now" -lt "$target" ]; then
		sleep "$((target - now))"
	fi

	check "the machine did not sleep while the lock was held" no_suspend_logged_since "$T0"
	check "the display is still off, so the inhibitor touched only sleep" \
		all_monitors_dpms "$USER_NAME" false
	check "the lock is still held at the end of the window" sleep_inhibitor_held
}

# After the harness has seen the machine suspend and woken it. The suspend's
# own timing is asserted out there; what is left is that the machine really
# slept rather than stalled, and that it locked on the way down.
assert_woke() {
	printf '\nM4 after the machine slept and was woken\n'

	check "logind recorded a sleep" suspend_logged_since "$T0"
	check "the session locked before sleeping" user_process_running "$USER_NAME" hyprlock
	check "the display came back on" all_monitors_dpms "$USER_NAME" true
	check "nothing is inhibiting sleep" sleep_inhibitor_absent
}

case "$MODE" in
config) assert_config ;;
inhibited)
	[ -n "$T0" ] || usage
	assert_inhibited
	;;
woke)
	[ -n "$T0" ] || usage
	assert_woke
	;;
*) usage ;;
esac

printf '\n'
if [ "$CHECK_SKIPS" -gt 0 ]; then
	printf '%d skipped. Read the skip lines above: this run is not evidence for what it could not observe.\n' "$CHECK_SKIPS"
fi

if [ "$CHECK_FAILURES" -eq 0 ]; then
	printf 'M4 %s: all observed criteria pass.\n' "$MODE"
	exit 0
fi

printf 'M4 %s: %d criteria failed.\n' "$MODE" "$CHECK_FAILURES"
exit 1
