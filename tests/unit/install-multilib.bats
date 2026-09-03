#!/usr/bin/env bats
#
# The installer enables multilib on the profile that games.
#
# Steam is a multilib package and the stock pacman.conf ships that repository
# commented out. The packages role enables it too, and cannot be the only
# thing that does: `ansible-playbook --check` changes nothing by definition,
# so on a fresh machine the dry run still would not know about steam and would
# fail against a machine that is fine. A run on 2026-09-02 failed exactly
# there, three minutes in.

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	export REPO_ROOT
	INSTALLER="$REPO_ROOT/scripts/archwork-install.sh"

	MOUNT_ROOT="$BATS_TEST_TMPDIR/target"
	mkdir -p "$MOUNT_ROOT/etc"
	cat >"$MOUNT_ROOT/etc/pacman.conf" <<-'CONF'
		[core]
		Include = /etc/pacman.d/mirrorlist

		#[multilib-testing]
		#Include = /etc/pacman.d/mirrorlist

		#[multilib]
		#Include = /etc/pacman.d/mirrorlist
	CONF
}

multilib_function() {
	PROFILE="${1:-desktop}"
	DRY_RUN="${2:-false}"
	MOUNT_ROOT="$3"
	log() { :; }
	die() {
		printf 'died: %s\n' "$1"
		exit 1
	}
	in_chroot() {
		printf 'chroot: %s\n' "$*"
	}
	eval "$(sed -n '/^configure_multilib()/,/^}/p' "$INSTALLER")"
}

@test "the desktop profile gets multilib uncommented" {
	run bash -c "
		$(declare -f multilib_function)
		INSTALLER='$INSTALLER'
		multilib_function desktop false '$MOUNT_ROOT'
		configure_multilib
	"
	[ "$status" -eq 0 ]
	grep -qx '\[multilib\]' "$MOUNT_ROOT/etc/pacman.conf"
	grep -A1 -x '\[multilib\]' "$MOUNT_ROOT/etc/pacman.conf" | grep -qx 'Include = /etc/pacman.d/mirrorlist'
}

@test "multilib-testing is left alone, which is not the same repository" {
	run bash -c "
		$(declare -f multilib_function)
		INSTALLER='$INSTALLER'
		multilib_function desktop false '$MOUNT_ROOT'
		configure_multilib
	"
	[ "$status" -eq 0 ]
	grep -qx '#\[multilib-testing\]' "$MOUNT_ROOT/etc/pacman.conf"
}

@test "the laptop profile does not get a 32-bit repository it never uses" {
	run bash -c "
		$(declare -f multilib_function)
		INSTALLER='$INSTALLER'
		multilib_function laptop false '$MOUNT_ROOT'
		configure_multilib
	"
	[ "$status" -eq 0 ]
	! grep -qx '\[multilib\]' "$MOUNT_ROOT/etc/pacman.conf"
}

@test "running it twice changes nothing the second time" {
	run bash -c "
		$(declare -f multilib_function)
		INSTALLER='$INSTALLER'
		multilib_function desktop false '$MOUNT_ROOT'
		configure_multilib
		configure_multilib
	"
	[ "$status" -eq 0 ]
	[ "$(grep -cx '\[multilib\]' "$MOUNT_ROOT/etc/pacman.conf")" -eq 1 ]
}

@test "a dry run says what it would do and writes nothing" {
	local before
	before="$(cat "$MOUNT_ROOT/etc/pacman.conf")"
	run bash -c "
		$(declare -f multilib_function)
		INSTALLER='$INSTALLER'
		multilib_function desktop true '$MOUNT_ROOT'
		configure_multilib
	"
	[ "$status" -eq 0 ]
	[[ "$output" == *"would uncomment"* ]]
	[ "$before" = "$(cat "$MOUNT_ROOT/etc/pacman.conf")" ]
}

@test "a pacman.conf whose multilib section is not the stock one is a failure" {
	# The dangerous shape: sed matching nothing and the install carrying on to
	# fail later, at pacman, with steam missing and no clue why.
	printf '[core]\nInclude = /etc/pacman.d/mirrorlist\n' >"$MOUNT_ROOT/etc/pacman.conf"
	run bash -c "
		$(declare -f multilib_function)
		INSTALLER='$INSTALLER'
		multilib_function desktop false '$MOUNT_ROOT'
		configure_multilib
	"
	[ "$status" -ne 0 ]
	[[ "$output" == *"died:"* ]]
}

@test "the new repository's database is synced, or the machine knows nothing in it" {
	# The second half of the same bug. Enabling the repository and leaving the
	# database alone gets a machine that knows multilib exists and nothing
	# that is in it, and `ansible-playbook --check` never refreshes it,
	# because a dry run changes nothing. Two runs on 2026-09-02 died on
	# "could not find or read package steam", the second one after the
	# repository was already being enabled.
	run bash -c "
		$(declare -f multilib_function)
		INSTALLER='$INSTALLER'
		multilib_function desktop false '$MOUNT_ROOT'
		configure_multilib
	"
	[ "$status" -eq 0 ]
	[[ "$output" == *"chroot: pacman -Sy"* ]]
}

@test "the laptop syncs nothing, having changed nothing" {
	run bash -c "
		$(declare -f multilib_function)
		INSTALLER='$INSTALLER'
		multilib_function laptop false '$MOUNT_ROOT'
		configure_multilib
	"
	[ "$status" -eq 0 ]
	[[ "$output" != *"chroot:"* ]]
}
