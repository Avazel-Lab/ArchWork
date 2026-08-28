#!/usr/bin/env bash
#
# Run the M2 reconciliation on the machine being reconciled.
#
# Copied to the guest and run there by tests/vm/run-install.sh. The machine
# configures itself (D-016), so this is the same command a real machine runs:
# the committed inventory, a local connection, no network transport.
#
# Usage: reconcile.sh check | run

set -euo pipefail

REPO="$HOME/src/ArchWork"
MODE="${1:-run}"

die() {
	printf 'error: %s\n' "$1" >&2
	exit 1
}

[ -d "$REPO/ansible" ] ||
	die "no repository at $REPO. The installer should have cloned it (D-016)."

command -v ansible-playbook >/dev/null ||
	die "ansible-playbook is not installed. The installer should have pacstrapped it (D-016)."

cd "$REPO/ansible"

# -l limits the run to this machine. group_vars/all.yml sets the connection to
# local, and the installer set a host name that inventory/hosts.yml names, so
# nothing here needs an inventory generated for the test.
case "$MODE" in
check)
	exec ansible-playbook --check -l "$(hostname)" site.yml
	;;
run)
	exec ansible-playbook -l "$(hostname)" site.yml
	;;
*)
	printf 'error: unknown mode %s. Use check or run.\n' "$MODE" >&2
	exit 1
	;;
esac
