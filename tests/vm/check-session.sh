#!/usr/bin/env bash
#
# Ask the machine one question about its session.
#
# D-021 drives the desktop from outside the guest: press a key at the
# framebuffer, then ask the machine what happened. assert-m3.sh is the whole
# list asked at once; this is one question at a time, because the harness has
# to press a key between them.
#
# Usage: check-session.sh [--wait SECONDS] PREDICATE [ARGS...]
#
# A window takes a moment to map and a process a moment to exit, so --wait
# retries until the answer is yes or the time runs out. Without it every
# caller would grow its own sleep, and each one would be a different length.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source-path=SCRIPTDIR source=lib/checks.sh
source "$SCRIPT_DIR/lib/checks.sh"

# What this is allowed to run. lib/checks.sh also holds helpers that take a
# command to run as the user, and those would turn this into a way to run
# anything as anyone. Naming the questions keeps it a question.
ALLOWED=(
	client_class_present
	client_class_absent
	compositor_answers
	file_picker_open
	graphical_session_open
	keyring_unlocked
	list_clients
	portal_answers
	process_absent
	screenshot_works
	user_process_running
	user_unit_active
)

WAIT=0

die() {
	printf 'error: %s\n' "$1" >&2
	exit 2
}

while [ $# -gt 0 ]; do
	case "$1" in
	--wait)
		WAIT="${2:-0}"
		shift 2
		;;
	*)
		break
		;;
	esac
done

PREDICATE="${1:-}"
[ -n "$PREDICATE" ] || die "usage: check-session.sh [--wait SECONDS] PREDICATE [ARGS...]"
shift

allowed=false
for name in "${ALLOWED[@]}"; do
	[ "$name" = "$PREDICATE" ] && allowed=true
done
[ "$allowed" = true ] || die "'$PREDICATE' is not one of the questions this can ask: ${ALLOWED[*]}"

deadline=$((SECONDS + WAIT))
while true; do
	if "$PREDICATE" "$@"; then
		printf 'yes: %s %s\n' "$PREDICATE" "$*"
		exit 0
	fi
	[ "$SECONDS" -ge "$deadline" ] && break
	sleep 1
done

printf 'no: %s %s\n' "$PREDICATE" "$*"
exit 1
