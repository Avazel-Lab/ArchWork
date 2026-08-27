#!/usr/bin/env bash
#
# Runs on the Arch ISO, fetched by archiso's script= boot parameter.
#
# Its only job is to get the repository onto the live system and hand over to
# the installer. Keep it small: anything clever here is untested code running
# in the one place that is hard to debug.

set -euo pipefail

HOST="${ARCHWORK_HOST:-10.0.2.2}"
PORT="${ARCHWORK_PORT:-8000}"
BASE="http://$HOST:$PORT"

log() {
	printf '\n[provision] %s\n' "$1" | tee /dev/console
}

log "Fetching the repository from $BASE"
curl -fsS "$BASE/repo.tar" -o /tmp/repo.tar
mkdir -p /tmp/archwork
tar -xf /tmp/repo.tar -C /tmp/archwork

log "Fetching the test credentials"
curl -fsS "$BASE/passphrase" -o /tmp/passphrase
curl -fsS "$BASE/id_test.pub" -o /tmp/id_test.pub
chmod 600 /tmp/passphrase

PROFILE="$(curl -fsS "$BASE/profile")"
DISK="$(curl -fsS "$BASE/disk")"

log "Installing profile '$PROFILE' onto $DISK"

# The installer prints the target device and makes the operator type it back
# before it writes anything (guard_confirm_target in scripts/lib/guards.sh).
# An unattended install has to answer that prompt. Feed the answer in rather
# than adding a bypass flag to the installer: the guard still runs, and it
# still refuses anything that is not an exact match for the target device.
printf '%s\n' "$DISK" | /tmp/archwork/scripts/archwork-install.sh \
	--profile "$PROFILE" \
	--luks-passphrase-file /tmp/passphrase \
	--authorized-key /tmp/id_test.pub \
	"$DISK"

# The installer leaves the account without a password. The test harness reaches
# the machine over SSH with a key, so lock the password rather than setting one.
arch-chroot /mnt passwd --lock root

log "Install finished, powering off"
sync
systemctl poweroff
