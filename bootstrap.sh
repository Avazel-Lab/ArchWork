#!/usr/bin/env bash
#
# Entry point for a fresh installation.
#
# Runs on the machine being built, never from another machine (D-016). Nothing
# in the build path may require a second machine to be working: a rebuild that
# needs the other workstation alive fails on the day it matters, and has no
# answer at all for the first machine.
#
# The phase order is fixed by D-016 rather than chosen, because a wireless-only
# laptop has no network at first boot and the WiFi PSK it needs sits inside the
# encrypted secrets in this repository:
#
#   1. Prompt for the age passphrase and unwrap the private key in memory.
#   2. Decrypt the secrets, including the WiFi PSK.
#   3. Bring up networking through NetworkManager.
#   4. Run ansible-playbook with a local connection, which can now fetch
#      packages.
#
# scripts/archwork-install.sh pacstraps ansible, python and age precisely so
# that step 4 does not depend on a network step 3 has not established yet.
#
# Phases 1 and 2 have nothing to do yet: no secrets are committed, and D-006
# describes how they will arrive rather than what is here now. The phase is in
# place, and says what it found, rather than being absent and quietly skipped.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DRY_RUN=false

usage() {
	cat <<'USAGE'
bootstrap.sh [--dry-run]

Configures this machine from the repository it is run from (D-016).

Options:
  --dry-run   run the playbook with --check, changing nothing
  -h, --help  this text
USAGE
}

die() {
	printf 'error: %s\n' "$1" >&2
	exit 1
}

log() {
	printf '\n\033[1m==> %s\033[0m\n' "$1"
}

parse_args() {
	while [ $# -gt 0 ]; do
		case "$1" in
		--dry-run)
			DRY_RUN=true
			shift
			;;
		-h | --help)
			usage
			exit 0
			;;
		*)
			usage >&2
			die "unknown option '$1'"
			;;
		esac
	done
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

	[ -d "$SCRIPT_DIR/ansible" ] ||
		die "no ansible directory beside this script. Run it from the clone in your home directory."

	command -v ansible-playbook >/dev/null ||
		die "ansible-playbook is not installed. The installer pacstraps it (D-016), so this machine was built some other way."
}

# D-006: the age private key is committed wrapped with a passphrase, unwrapped
# in memory here, and never written to disk outside its final destination.
# Nothing is committed yet, so this reports and moves on. When the secrets
# arrive, they arrive here, before networking, because the WiFi PSK is one of
# them.
phase_secrets() {
	log "Phase 1: secrets"

	if [ ! -d "$SCRIPT_DIR/secrets" ]; then
		printf 'No secrets in this repository yet (D-006). Nothing to decrypt.\n'
		return 0
	fi

	die "this repository has a secrets directory, and bootstrap.sh does not know how to unwrap it yet. See D-006."
}

# A wired machine is online before this runs. A wireless one is not, and until
# the secrets phase above can hand over a PSK, connecting it is a manual step.
# Say so plainly rather than failing in the middle of the playbook, where the
# error would be about a package mirror.
phase_network() {
	log "Phase 2: networking"

	if ! systemctl is-active --quiet NetworkManager; then
		sudo systemctl start NetworkManager ||
			die "NetworkManager would not start, so this machine has no way to reach a mirror"
	fi

	if nm-online --quiet --timeout 30; then
		printf 'This machine is online.\n'
		return 0
	fi

	die "no network after 30 seconds. Connect this machine with nmtui, then run bootstrap.sh again."
}

# The playbook, run against this machine alone.
#
# -l limits the run to this host. Getting that wrong is worse than it sounds:
# group_vars/all.yml sets the connection to local (D-016), so every host in the
# inventory resolves to this machine. An unlimited run reconciles it once per
# host, concurrently, and two pacman processes then fight over one database
# lock.
phase_reconcile() {
	log "Phase 3: reconciling this machine with the playbook"

	# uname -n rather than hostname: a base Arch install has coreutils and does
	# not have inetutils, so hostname is not there. It failed silently once,
	# the limit below became empty, and an empty -l means every host.
	local host
	host="$(uname -n)"
	[ -n "$host" ] ||
		die "cannot determine this machine's host name, and an empty -l reconciles every host in the inventory"

	cd "$SCRIPT_DIR/ansible"

	# An -l pattern that matches nothing is a warning to ansible rather than an
	# error, so prove the inventory names this machine before trusting it.
	ansible-inventory --host "$host" >/dev/null 2>&1 ||
		die "inventory/hosts.yml does not name '$host'. Fix the host name or the inventory."

	local args=(-l "$host")

	# Ansible escalates for most of what it does. Where sudo wants a password,
	# it has to be asked for at the start rather than at the task that first
	# needs it, where the prompt would sit unanswered behind the output.
	if ! sudo -n true 2>/dev/null; then
		args+=(--ask-become-pass)
	fi

	if [ "$DRY_RUN" = true ]; then
		args+=(--check)
	fi

	ansible-playbook "${args[@]}" site.yml
}

main() {
	parse_args "$@"
	check_running_on_target

	phase_secrets
	phase_network
	phase_reconcile

	if [ "$DRY_RUN" = true ]; then
		log "Dry run finished. Nothing was changed."
		return 0
	fi

	log "This machine is configured"
	printf '\nLog out and back in if group membership changed, or reboot to reach the greeter.\n\n'
}

main "$@"
