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

# uname -n rather than hostname: a base Arch install has coreutils and does
# not have inetutils, so hostname is not there. It failed silently, the limit
# below became empty, and an empty -l means every host in the inventory.
HOST="$(uname -n)"

[ -n "$HOST" ] ||
	die "cannot determine this machine's host name, and an empty -l reconciles every host in the inventory"

# An -l pattern that matches nothing is a warning to ansible rather than an
# error, so prove the inventory names this machine before trusting the limit.
#
# Getting this wrong is worse than it sounds. group_vars/all.yml sets the
# connection to local (D-016), so every host in the inventory resolves to this
# machine: an unlimited run reconciles it once per host, concurrently, and two
# pacman processes then fight over one database lock.
ansible-inventory --host "$HOST" >/dev/null 2>&1 ||
	die "inventory/hosts.yml does not name '$HOST'. Fix the host name or the inventory."

# -l limits the run to this machine. Nothing here needs an inventory generated
# for the test.
case "$MODE" in
check)
	exec ansible-playbook --check -l "$HOST" site.yml
	;;
run)
	exec ansible-playbook -l "$HOST" site.yml
	;;
*)
	printf 'error: unknown mode %s. Use check or run.\n' "$MODE" >&2
	exit 1
	;;
esac
