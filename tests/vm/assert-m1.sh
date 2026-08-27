#!/usr/bin/env bash
#
# M1 exit criteria, asserted on the installed system.
#
# Runs inside the VM. Every check maps to a line in docs/plan.md. Prints one
# line per check and exits non-zero if any fail.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source-path=SCRIPTDIR source=lib/checks.sh
source "$SCRIPT_DIR/lib/checks.sh"

PROFILE="${1:-desktop}"

printf '\nM1 exit criteria, profile %s\n\n' "$PROFILE"

printf 'Encryption and filesystem\n'
check "root sits on a LUKS2 volume" root_is_luks2
check "root filesystem is btrfs" root_fstype_is btrfs
check "subvolume @ exists" has_subvolume "@"
check "subvolume @home exists" has_subvolume "@home"
check "subvolume @var_log exists" has_subvolume "@var_log"
check "subvolume @var_cache exists" has_subvolume "@var_cache"
check "subvolume @ai_models exists" has_subvolume "@ai_models"
check "subvolume @snapshots exists" has_subvolume "@snapshots"
check "root is mounted with zstd compression" mount_has_option / "compress=zstd"
check "/home is mounted with zstd compression" mount_has_option /home "compress=zstd"
check "/var/lib rolls back with @" var_lib_rolls_back_with_root

printf '\nBoot\n'
check "primary UKI is present" test -f /efi/EFI/Linux/archwork.efi
check "recovery UKI is present" test -f /efi/EFI/Linux/archwork-recovery.efi
check "systemd-boot is installed" test -f /efi/EFI/systemd/systemd-bootx64.efi
check "kernel command line came from a profile file" file_contains /etc/kernel/cmdline "rootflags=subvol=@"
check "no unsubstituted token in the command line" check_no_token /etc/kernel/cmdline
check "mkinitcpio uses the systemd hooks" file_contains /etc/mkinitcpio.conf "sd-encrypt"
check "recovery initramfs carries every module" check_recovery_no_autodetect

printf '\nSwap and hibernation\n'
check "zram is configured" test -f /etc/systemd/zram-generator.conf
check "a zram swap device is active" swap_active_on zram

if [ "$PROFILE" = "laptop" ]; then
	check "subvolume @swap exists" has_subvolume "@swap"
	check "the swapfile is active" swap_active_on /swap/swapfile
	check "resume is on the kernel command line" file_contains /etc/kernel/cmdline "resume="
	check "resume_offset is set and non-empty" file_matches /etc/kernel/cmdline "resume_offset=[0-9]+"
	check "hibernate delay is configured" test -f /etc/systemd/sleep.conf.d/archwork.conf
else
	check_not "subvolume @swap is absent" has_subvolume "@swap"
	check_not "the command line carries no resume" file_contains /etc/kernel/cmdline "resume="
fi

printf '\nRecovery\n'
check "rollback script is installed and executable" test -x /usr/local/bin/archwork-rollback
check "rollback script runs" /usr/local/bin/archwork-rollback --help
check "recovery command line reaches a rescue shell" file_contains /etc/kernel/cmdline-recovery "rescue.target"

printf '\nSystem\n'
check "NetworkManager is enabled" systemctl is-enabled NetworkManager
check "hostname is set" test -s /etc/hostname
check "administrator account exists" id gary

printf '\n'
if [ "$CHECK_FAILURES" -eq 0 ]; then
	printf 'All M1 criteria pass.\n'
	exit 0
fi

printf '%d M1 criteria failed.\n' "$CHECK_FAILURES"
exit 1
