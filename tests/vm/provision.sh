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

# A failed install must not look like a slow one. Without this the VM sits at
# a login prompt forever and the harness waits for a marker that never
# arrives, which is how a stalled mirror cost an hour of wall clock time.
trap 'log "Install FAILED, see the output above"; sync; systemctl poweroff' ERR

log "Fetching the repository from $BASE"
curl -fsS "$BASE/repo.bundle" -o /tmp/repo.bundle
git clone --quiet /tmp/repo.bundle /tmp/archwork

# The installer clones the checkout it runs from onto the target (D-016) and
# takes its origin from here, so point it upstream before it does. Left alone
# it would be /tmp/repo.bundle, which does not exist on the installed machine.
curl -fsS "$BASE/repo-url" -o /tmp/repo-url
git -C /tmp/archwork remote set-url origin "$(cat /tmp/repo-url)"

log "Fetching the test credentials"
curl -fsS "$BASE/passphrase" -o /tmp/passphrase
curl -fsS "$BASE/id_test.pub" -o /tmp/id_test.pub
chmod 600 /tmp/passphrase

# Pin the mirror rather than trusting whatever the ISO ranked. A run that
# fails because one mirror stalled says nothing about the installer, and this
# is the test harness, not a real installation.
log "Pinning the package mirror"
# shellcheck disable=SC2016 # $repo and $arch are pacman placeholders, and pacman expands them, not the shell
printf 'Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch\n' >/etc/pacman.d/mirrorlist

PROFILE="$(curl -fsS "$BASE/profile")"
DISK="$(curl -fsS "$BASE/disk")"

log "Installing profile '$PROFILE' onto $DISK"

# The installer prints the target device and makes the operator type it back
# before it writes anything (guard_confirm_target in scripts/lib/guards.sh).
# An unattended install has to answer that prompt. Feed the answer in rather
# than adding a bypass flag to the installer: the guard still runs, and it
# still refuses anything that is not an exact match for the target device.
#
# Send the installer output to /dev/console as well. archiso runs this script
# with its stdout going to the journal, not the console, so without the tee an
# installer that stops and waits looks identical to one that is working, and
# the harness has no way to tell which.
printf '%s\n' "$DISK" | /tmp/archwork/scripts/archwork-install.sh \
	--profile "$PROFILE" \
	--luks-passphrase-file /tmp/passphrase \
	--authorized-key /tmp/id_test.pub \
	"$DISK" 2>&1 | tee /dev/console

# The installer leaves the account without a password. The test harness reaches
# the machine over SSH with a key, so lock the password rather than setting one.
arch-chroot /mnt passwd --lock root

log "Install finished, powering off"
sync
systemctl poweroff
