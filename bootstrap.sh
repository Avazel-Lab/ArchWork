#!/usr/bin/env bash
#
# Entry point for a fresh installation.
#
# Runs on the machine being built, never from another machine (D-016). Nothing
# in the build path may require a second machine to be working: a rebuild that
# needs the other workstation alive fails on the day it matters, and has no
# answer at all for the first machine.
#
# M2 fills this in. The phase order below is fixed by D-016 rather than chosen,
# because a wireless-only laptop has no network at first boot and the WiFi PSK
# it needs sits inside the encrypted secrets in this repository:
#
#   1. Prompt for the age passphrase and unwrap the private key in memory.
#   2. Decrypt the secrets, including the WiFi PSK.
#   3. Bring up networking through NetworkManager.
#   4. Run ansible-playbook with a local connection, which can now fetch
#      packages.
#
# scripts/archwork-install.sh pacstraps ansible, python and age precisely so
# that step 4 does not depend on a network step 3 has not established yet.

set -euo pipefail

die() {
	printf 'error: %s\n' "$1" >&2
	exit 1
}

# Refuse to run anywhere but the machine being configured. Running this against
# a development checkout would reconfigure the wrong machine.
check_running_on_target() {
	[ -f /etc/arch-release ] ||
		die "this is not an Arch system. bootstrap.sh runs on the machine being built."

	[ -f /etc/kernel/cmdline ] ||
		die "no /etc/kernel/cmdline. This machine was not installed by scripts/archwork-install.sh."

	[ "$(id -u)" -ne 0 ] ||
		die "run bootstrap.sh as your own user, not root. It escalates where it needs to."
}

main() {
	check_running_on_target

	cat >&2 <<'PENDING'
bootstrap.sh is not implemented yet.

M1 leaves this machine able to configure itself: ansible, python and age are
installed and this repository is cloned into your home directory. M2 adds the
inventory, the package manifests and the playbook that this script runs.

See docs/plan.md for M2 and its exit criteria, and docs/decisions/log.md D-016
for why configuration happens here rather than over the network.
PENDING

	exit 1
}

main "$@"
