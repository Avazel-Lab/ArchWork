#!/usr/bin/env bats
#
# The parts of the M4 assertions that can be proven without an hour of VM.
#
# assert-m4.sh spends 65 minutes measuring three timings, so its helpers are
# the last place anything should be trusted on a reading. The pairing check
# below is the one that matters: a hypridle.conf with the dim and sleep
# commands swapped has all three timeouts present and correct, and a check
# that only looked for the numbers would pass a machine that suspends after
# five minutes.

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	export REPO_ROOT
	CONF="$REPO_ROOT/dotfiles/hypr/hypridle.conf"
	# Sourcing this replaces bats' own skip with the one in checks.sh, so no
	# test in this file can skip itself. Nothing here wants to.
	# shellcheck source=../vm/lib/checks.sh
	source "$REPO_ROOT/tests/vm/lib/checks.sh"
}

@test "the shipped config has the three timings M4 asks for" {
	hypridle_listener_has "$CONF" 300 brightnessctl
	hypridle_listener_has "$CONF" 900 'action = "off"'
	hypridle_listener_has "$CONF" 1800 "systemctl suspend"
}

@test "a timeout paired with the wrong command does not count" {
	! hypridle_listener_has "$CONF" 300 "systemctl suspend"
	! hypridle_listener_has "$CONF" 1800 brightnessctl
}

@test "a timeout that is not in the config does not count" {
	! hypridle_listener_has "$CONF" 600 brightnessctl
}

@test "a command outside any listener block does not count" {
	# general { } holds hyprlock and dpms on. Neither is a listener, and
	# neither has a timeout, so nothing there may satisfy a timing.
	local conf="$BATS_TEST_TMPDIR/hypridle.conf"
	cat >"$conf" <<'CONF'
general {
    lock_cmd = hyprlock
    after_sleep_cmd = hyprctl dispatch 'hl.dsp.dpms({ action = "on" })'
}

listener {
    timeout = 900
}
CONF
	! hypridle_listener_has "$conf" 900 'action = "on"'
}

@test "the timing window rejects early as firmly as late" {
	within_window 900 900 960
	within_window 960 900 960
	! within_window 899 900 960
	! within_window 961 900 960
}

@test "seconds_until counts from the caller's clock, not from when it started" {
	local since observed
	since="$(($(date +%s) - 42))"
	observed="$(seconds_until "$since" 300 true)"
	# 42 or 43, depending on which side of a second the two date calls fell.
	[ "$observed" -ge 42 ]
	[ "$observed" -le 43 ]
}

@test "seconds_until gives up once the deadline has passed" {
	local since
	since="$(($(date +%s) - 100))"
	run seconds_until "$since" 10 false
	[ "$status" -ne 0 ]
}

@test "a dim below the threshold passes and one above it fails" {
	local root="$BATS_TEST_TMPDIR/backlight"
	mkdir -p "$root/intel_backlight"
	printf '100\n' >"$root/intel_backlight/max_brightness"
	BACKLIGHT_ROOT="$root"

	backlight_present
	printf '10\n' >"$root/intel_backlight/brightness"
	backlight_at_or_below 15
	printf '80\n' >"$root/intel_backlight/brightness"
	! backlight_at_or_below 15
}

@test "no backlight device means no backlight to dim" {
	BACKLIGHT_ROOT="$BATS_TEST_TMPDIR/empty"
	mkdir -p "$BACKLIGHT_ROOT"
	! backlight_present
}

@test "skip is counted apart from a pass" {
	CHECK_FAILURES=0
	CHECK_SKIPS=0
	check "a passing check" true
	skip "an unobservable criterion" "no backlight here"
	[ "$CHECK_FAILURES" -eq 0 ]
	[ "$CHECK_SKIPS" -eq 1 ]
}

@test "the config check follows the directory link the dotfiles role makes" {
	# ~/.config/hypr is the symlink, not the file inside it, so test -L on
	# hypridle.conf is false on a correctly configured machine. This check
	# used to be exactly that, and would have failed every real run.
	HOME_ROOT="$BATS_TEST_TMPDIR/home"
	local home="$HOME_ROOT/someone"
	mkdir -p "$home/src/ArchWork/dotfiles/hypr" "$home/.config"
	: >"$home/src/ArchWork/dotfiles/hypr/hypridle.conf"
	ln -s "$home/src/ArchWork/dotfiles/hypr" "$home/.config/hypr"

	config_is_repo_dotfile "$home/.config/hypr/hypridle.conf" someone

	# A copy left behind by hand resolves somewhere else and does not count.
	rm "$home/.config/hypr"
	mkdir -p "$home/.config/hypr"
	: >"$home/.config/hypr/hypridle.conf"
	! config_is_repo_dotfile "$home/.config/hypr/hypridle.conf" someone
}

@test "a check whose predicate does not exist fails, and says so" {
	CHECK_FAILURES=0
	run check "something nobody defined" no_such_predicate_anywhere
	[ "$status" -ne 0 ]
	[[ "$output" == *"no such check: no_such_predicate_anywhere"* ]]
}

@test "check_not refuses a predicate that does not exist rather than passing it" {
	# The dangerous half. A missing command "fails", so an absence check would
	# report ok and prove nothing. A typo would go green.
	CHECK_FAILURES=0
	run check_not "an absence nobody can test" no_such_predicate_anywhere
	[ "$status" -ne 0 ]
	[[ "$output" != *"  ok "* ]]
}

@test "the M4 script only calls predicates that exist" {
	# The bug this file exists to stop coming back: assert-m4.sh called
	# hypridle_running, nothing defined it, and a 65 minute run blamed the
	# machine. Every predicate the script names has to be real.
	local script="$REPO_ROOT/tests/vm/assert-m4.sh"
	local name
	while read -r name; do
		[ -n "$name" ] || continue
		command -v "$name" >/dev/null 2>&1 || {
			echo "assert-m4.sh calls $name, which nothing defines"
			return 1
		}
	# Continuation lines are joined first: a check whose predicate sits on
	# the next line is exactly the shape this would otherwise miss.
	done < <(sed -e :a -e '/\\$/N; s/\\\n//; ta' "$script" |
		grep -oE 'check(_timing|_not)? "[^"]*"( [0-9]+)*[[:space:]]+[a-z_]+' |
		sed -E 's/.*"([ 0-9]+)?[[:space:]]*//' | grep -vE '^(test|systemctl)$')
}

@test "no dotfile calls hyprctl dispatch with a bare dispatcher name" {
	# The second bug a real run found in this phase, and the one that cost a
	# whole 65 minute window. D-026 moved hyprctl's dispatch argument to Lua,
	# so `hyprctl dispatch dpms off` is a syntax error rather than a
	# dispatcher call. hypridle ignores the exit status of what it runs, so
	# the display never switched off and nothing anywhere said why.
	#
	# The mechanical half is checkable without a compositor: the argument has
	# to be quoted, because every Lua form needs parens the shell would
	# otherwise eat. A bare word after `dispatch` is the old syntax.
	local hit
	hit="$(grep -rn "hyprctl dispatch [^'\"]" "$REPO_ROOT/dotfiles" |
		grep -vE ':[0-9]+:[[:space:]]*#' || true)"
	if [ -n "$hit" ]; then
		echo "these pass an unquoted argument to hyprctl dispatch:"
		echo "$hit"
		return 1
	fi
}
