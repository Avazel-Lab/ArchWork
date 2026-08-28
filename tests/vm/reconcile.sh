#!/usr/bin/env bash
#
# Run the reconciliation on the machine being reconciled.
#
# Copied to the guest and run there by tests/vm/run-install.sh. It runs
# bootstrap.sh, which is the command a real machine runs: the same guards, the
# same inventory, the same local connection. A test path that reimplemented
# any of that would prove the reimplementation works and say nothing about the
# thing an operator actually types (D-016).
#
# Usage: reconcile.sh check | run

set -euo pipefail

REPO="$HOME/src/ArchWork"
MODE="${1:-run}"

die() {
	printf 'error: %s\n' "$1" >&2
	exit 1
}

[ -x "$REPO/bootstrap.sh" ] ||
	die "no bootstrap.sh at $REPO. The installer should have cloned it (D-016)."

case "$MODE" in
check)
	exec "$REPO/bootstrap.sh" --dry-run
	;;
run)
	exec "$REPO/bootstrap.sh"
	;;
*)
	printf 'error: unknown mode %s. Use check or run.\n' "$MODE" >&2
	exit 1
	;;
esac
