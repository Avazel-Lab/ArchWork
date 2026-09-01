#!/usr/bin/env bats
#
# The health check's predicates, against machines this one is not.
#
# Every external command it consults is injectable, so these tests can present
# a machine with the wrong subvolume layout, an unencrypted root or a missing
# UKI without needing one. The pattern this file cares about most is the one
# that has bitten this repository three times: a predicate that cannot succeed
# makes anything built on its negation pass while testing nothing. So every
# check here is exercised in both directions.

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	export REPO_ROOT
	# shellcheck source=../../scripts/archwork-health
	source "$REPO_ROOT/scripts/archwork-health"
	QUIET=true
}

# A findmnt that answers with the options of whatever layout a test describes.
# FSTAB_FIXTURE maps a target to its mount options, one per line, "target|opts".
fake_findmnt() {
	local fake="$BATS_TEST_TMPDIR/findmnt"
	cat >"$fake" <<-'SH'
		#!/usr/bin/env bash
		target=""
		while [ $# -gt 0 ]; do
			case "$1" in
			--target) target="$2"; shift 2 ;;
			*) shift ;;
			esac
		done
		while IFS='|' read -r where opts; do
			[ "$where" = "$target" ] || continue
			printf '%s\n' "$opts"
			exit 0
		done < "$FSTAB_FIXTURE"
		exit 1
	SH
	chmod +x "$fake"
	FINDMNT="$fake"
}

healthy_layout() {
	FSTAB_FIXTURE="$BATS_TEST_TMPDIR/mounts"
	cat >"$FSTAB_FIXTURE" <<-'MOUNTS'
		/|rw,noatime,compress=zstd:3,ssd,space_cache=v2,subvol=/@
		/home|rw,noatime,compress=zstd:3,subvol=/@home
		/var/log|rw,noatime,compress=zstd:3,subvol=/@var_log
		/var/cache|rw,noatime,compress=zstd:3,subvol=/@var_cache
		/.snapshots|rw,noatime,compress=zstd:3,subvol=/@snapshots
		/var/lib|rw,noatime,compress=zstd:3,ssd,space_cache=v2,subvol=/@
	MOUNTS
	export FSTAB_FIXTURE
	fake_findmnt
}

@test "the shipped layout passes every subvolume check" {
	healthy_layout
	subvol_mounted_at @ /
	subvol_mounted_at @home /home
	subvol_mounted_at @var_log /var/log
	subvol_mounted_at @var_cache /var/cache
	subvol_mounted_at @snapshots /.snapshots
	mount_has_option / compress=zstd:3
	var_lib_inside_root
}

@test "a subvolume mounted somewhere else is caught" {
	healthy_layout
	! subvol_mounted_at @home /var/log
	! subvol_mounted_at @nonexistent /
}

@test "a carved out /var/lib is caught, which is the whole point of the check" {
	# CLAUDE.md: /var/lib holds the pacman database and must roll back with @.
	# On its own subvolume it survives a rollback, and pacman then describes
	# packages that are not on disk. This is the check that notices.
	healthy_layout
	sed -i 's|^/var/lib.*|/var/lib\|rw,noatime,subvol=/@var_lib|' "$FSTAB_FIXTURE"
	! var_lib_inside_root
}

@test "a root without compression is caught" {
	healthy_layout
	sed -i 's|^/|rw,noatime,subvol=/@|; 1s|.*|/\|rw,noatime,subvol=/@|' "$FSTAB_FIXTURE"
	! mount_has_option / compress=zstd:3
}

@test "an unmountable target is a failure rather than a pass" {
	healthy_layout
	! subvol_mounted_at @ /nowhere
	! mount_has_option /nowhere compress=zstd:3
}

# --- encryption ---------------------------------------------------------------

fake_cryptsetup() {
	local fake="$BATS_TEST_TMPDIR/cryptsetup"
	cat >"$fake" <<-'SH'
		#!/usr/bin/env bash
		cat "$CRYPT_FIXTURE"
	SH
	chmod +x "$fake"
	CRYPTSETUP="$fake"
}

@test "a LUKS2 root passes and a LUKS1 one does not" {
	fake_cryptsetup
	CRYPT_FIXTURE="$BATS_TEST_TMPDIR/crypt"
	export CRYPT_FIXTURE
	cat >"$CRYPT_FIXTURE" <<-'OUT'
		/dev/mapper/cryptroot is active and is in use.
		  type:    LUKS2
		  cipher:  aes-xts-plain64
	OUT
	root_is_luks2
	root_cipher_present

	printf '  type:    LUKS1\n  cipher:  aes-xts-plain64\n' >"$CRYPT_FIXTURE"
	! root_is_luks2
}

@test "a root that is not encrypted at all is caught" {
	# The dangerous direction. cryptsetup says nothing useful about a plain
	# device, and "says nothing" must not read as "is encrypted".
	fake_cryptsetup
	CRYPT_FIXTURE="$BATS_TEST_TMPDIR/crypt"
	export CRYPT_FIXTURE
	: >"$CRYPT_FIXTURE"
	! root_is_luks2
	! root_cipher_present
}

# --- boot ---------------------------------------------------------------------

@test "both UKIs have to exist and have to have something in them" {
	EFI_ROOT="$BATS_TEST_TMPDIR/efi"
	mkdir -p "$EFI_ROOT/EFI/Linux"
	! uki_present archwork.efi

	printf 'not empty\n' >"$EFI_ROOT/EFI/Linux/archwork.efi"
	uki_present archwork.efi
	! uki_present archwork-recovery.efi

	# A zero byte UKI is the shape a failed build leaves behind, and it is
	# not a bootable image.
	: >"$EFI_ROOT/EFI/Linux/archwork-recovery.efi"
	! uki_present archwork-recovery.efi
}

# --- the M4 timings -----------------------------------------------------------

@test "the shipped hypridle config satisfies all three timings" {
	HYPRIDLE_CONF="$REPO_ROOT/dotfiles/hypr/hypridle.conf"
	m4_timing 300 brightnessctl
	m4_timing 900 'action = "off"'
	m4_timing 1800 'systemctl suspend'
}

@test "a timing paired with the wrong command does not count" {
	HYPRIDLE_CONF="$BATS_TEST_TMPDIR/hypridle.conf"
	cat >"$HYPRIDLE_CONF" <<-'CONF'
		listener {
		    timeout = 300
		    on-timeout = systemctl suspend
		}
	CONF
	# The failure that matters: a machine that suspends after five minutes has
	# all three numbers somewhere and is badly wrong.
	! m4_timing 300 brightnessctl
	! m4_timing 1800 'systemctl suspend'
	m4_timing 300 'systemctl suspend'
}

@test "no hypridle config anywhere is a failure, not a pass" {
	HYPRIDLE_CONF="$BATS_TEST_TMPDIR/does-not-exist.conf"
	! m4_timing 300 brightnessctl
}

# --- the runner itself ---------------------------------------------------------

@test "a check naming a predicate nothing defines fails and says so" {
	# Paid for twice already in this repository, once by a 65 minute VM run.
	FAILED=0
	FAILURES=()
	run check "something nobody defined" no_such_predicate_at_all
	[ "$status" -eq 0 ]
	[[ "$output" == *"no such check: no_such_predicate_at_all"* ]]
	[[ "$output" == *"FAIL"* ]]
}
