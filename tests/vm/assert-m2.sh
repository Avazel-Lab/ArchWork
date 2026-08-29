#!/usr/bin/env bash
#
# The M2 service state that idempotence cannot show.
#
# M2's criterion is that a second reconciliation changes nothing, and running
# the playbook twice proves the tasks settle. It says nothing about what they
# settle on. A role that enabled the wrong unit would be perfectly idempotent
# about it.
#
# That gap matters most where a decision was made for a security reason.
# D-025 took away the `docker` group and left `docker.socket` disabled, and
# wrote down why: the group reaches a root daemon with no password prompt, and
# it had been granted on the belief that Docker was this workstation's
# container engine, which it is not. Nothing would have noticed either coming
# back. These assertions notice.
#
# Runs inside the VM as root, after reconciliation.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source-path=SCRIPTDIR source=lib/checks.sh
source "$SCRIPT_DIR/lib/checks.sh"

USER_NAME="${1:-gary}"

printf '\nM2 service state, user %s\n\n' "$USER_NAME"

printf 'Containers (D-025)\n'
check "podman is installed" command_installed podman
check "podman-compose is installed" command_installed podman-compose
check "the docker client is installed for remote systems" command_installed docker
check_not "docker.socket is not enabled" unit_is_enabled docker.socket
check_not "docker.service is not enabled" unit_is_enabled docker.service
check_not "no local docker daemon is running" unit_is_active docker.service
check "the administrator is not in the docker group" user_not_in_group "$USER_NAME" docker

printf '\n'
if [ "$CHECK_FAILURES" -eq 0 ]; then
	printf 'All M2 service state assertions pass.\n'
	exit 0
fi

printf '%d M2 service state assertions failed.\n' "$CHECK_FAILURES"
exit 1
