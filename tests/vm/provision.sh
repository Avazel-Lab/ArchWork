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
# archiso sends this script's stdout to the journal rather than the console, so
# a command that fails quietly leaves the console showing nothing between the
# last log line and the power off. Dump the journal tail before going down.
trap 'log "Install FAILED"; journalctl -b --no-pager -n 60 >/dev/console 2>&1 || true; sync; systemctl poweroff' ERR

# Pin the mirror rather than trusting whatever the ISO ranked. A run that
# fails because one mirror stalled says nothing about the installer, and this
# is the test harness, not a real installation.
#
# This comes first now, because the next step needs a working mirror.
# Two of them, both Arch-operated. One is a pin; a pin with no fallback means
# a single stalled download ends the run, which happened and cost ten minutes
# for a reason that says nothing about the installer.
log "Pinning the package mirrors"
# shellcheck disable=SC2016 # $repo and $arch are pacman placeholders, and pacman expands them, not the shell
printf 'Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch\nServer = https://mirror.pkgbuild.com/$repo/os/$arch\n' >/etc/pacman.d/mirrorlist

# The stock Arch ISO does not ship git. It has curl, tar, arch-install-scripts
# and everything else the installer needs, but not git, and D-016 made the
# installer clone the repository onto the target. So install it here, the same
# step a real installation takes.
log "Installing git on the live system"
pacman -Sy --needed --noconfirm git >/dev/console 2>&1

log "Fetching the repository from $BASE"
curl -fsS "$BASE/repo.bundle" -o /tmp/repo.bundle
git clone --quiet /tmp/repo.bundle /tmp/archwork

# A bundle with no HEAD clones to an empty working tree and warns rather than
# failing, so prove the installer is actually there before relying on it.
if [ ! -x /tmp/archwork/scripts/archwork-install.sh ]; then
	log "the clone produced no installer, so the bundle carried no HEAD"
	exit 1
fi

# The installer clones the checkout it runs from onto the target (D-016) and
# takes its origin from here, so point it upstream before it does. Left alone
# it would be /tmp/repo.bundle, which does not exist on the installed machine.
curl -fsS "$BASE/repo-url" -o /tmp/repo-url
git -C /tmp/archwork remote set-url origin "$(cat /tmp/repo-url)"

log "Fetching the test credentials"
curl -fsS "$BASE/passphrase" -o /tmp/passphrase
curl -fsS "$BASE/login-password" -o /tmp/login-password
curl -fsS "$BASE/id_test.pub" -o /tmp/id_test.pub
chmod 600 /tmp/passphrase /tmp/login-password
LOGIN_USER="$(curl -fsS "$BASE/login-user")"

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

# The greeter, though, has to have a password to accept (D-021). The installer
# deliberately sets none and tells the operator to, which is right for a real
# machine and impossible for an unattended run. So the harness sets the test
# password here, where every other test-only credential already lives, rather
# than teaching the installer a flag that could put a known password on a real
# installation.
log "Setting the test login password for $LOGIN_USER"
printf '%s:%s\n' "$LOGIN_USER" "$(cat /tmp/login-password)" | arch-chroot /mnt chpasswd

log "Install finished, powering off"
sync
systemctl poweroff
