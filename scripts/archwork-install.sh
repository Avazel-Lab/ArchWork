#!/usr/bin/env bash
#
# Install the ArchWork base system from the stock Arch ISO.
#
# This partitions and formats a disk. Everything on the target is destroyed.
# Read docs/decisions/storage-boot.md before changing anything here.
#
# It produces a system that boots to a text login prompt: LUKS2, the Btrfs
# layout, systemd-boot, a primary UKI and a recovery UKI. No desktop. M2
# installs the rest through Ansible.
#
# Usage:
#   archwork-install.sh [options] /dev/sdX
#
# See --help.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source-path=SCRIPTDIR source=lib/guards.sh
source "$SCRIPT_DIR/lib/guards.sh"

TARGET_DEVICE=""
PROFILE=""
HOSTNAME_VALUE=""
USERNAME="gary"
DRY_RUN=false
ACKNOWLEDGED=false
AUTHORIZED_KEY=""
PASSPHRASE_FILE=""
TIMEZONE="Europe/London"
LOCALE="en_GB.UTF-8"
KEYMAP="uk"
ESP_SIZE_MIB=1024
MOUNT_ROOT="/mnt"

MOUNT_OPTS="compress=zstd:3,noatime,ssd,space_cache=v2"

usage() {
	cat <<'USAGE'
archwork-install.sh [options] DEVICE

Installs the ArchWork base system. DEVICE is destroyed. There is no default.

Required:
  DEVICE                          whole disk to install onto, e.g. /dev/vda
  --profile desktop|laptop        machine profile (D-010 inventory groups)

Options:
  --hostname NAME                 defaults to hmlxdesktop01 or hmlxlaptop01
  --user NAME                     administrator account, default 'gary'
  --dry-run                       print every command, write nothing
  --i-know-this-wipes-my-disk     permit running outside a virtual machine
  --authorized-key FILE           install an SSH key and enable sshd.
                                  VM only. Used by the M1 test harness.
  --luks-passphrase-file FILE     read the LUKS passphrase from FILE rather
                                  than prompting. VM only.
  -h, --help                      this text

The laptop profile additionally creates @swap with a RAM-sized swapfile and
enables hibernation (D-013).
USAGE
}

die() {
	printf 'error: %s\n' "$1" >&2
	exit 1
}

log() {
	printf '\n==> %s\n' "$1"
}

# Every command that changes state goes through this. Dry runs print and
# return, so --dry-run is a real rehearsal rather than a partial one.
run_cmd() {
	if [ "$DRY_RUN" = true ]; then
		printf '  would run:'
		printf ' %q' "$@"
		printf '\n'
		return 0
	fi
	"$@"
}

# Writing a file is a state change too, so it gets the same treatment.
write_file() {
	local path="$1"
	local content="$2"
	local mode="${3:-0644}"

	if [ "$DRY_RUN" = true ]; then
		printf '  would write %s (mode %s, %d bytes)\n' "$path" "$mode" "${#content}"
		return 0
	fi

	mkdir -p "$(dirname "$path")"
	printf '%s\n' "$content" >"$path"
	chmod "$mode" "$path"
}

in_chroot() {
	run_cmd arch-chroot "$MOUNT_ROOT" "$@"
}

parse_args() {
	while [ $# -gt 0 ]; do
		case "$1" in
		--profile)
			PROFILE="${2:-}"
			shift 2
			;;
		--hostname)
			HOSTNAME_VALUE="${2:-}"
			shift 2
			;;
		--user)
			USERNAME="${2:-}"
			shift 2
			;;
		--authorized-key)
			AUTHORIZED_KEY="${2:-}"
			shift 2
			;;
		--luks-passphrase-file)
			PASSPHRASE_FILE="${2:-}"
			shift 2
			;;
		--dry-run)
			DRY_RUN=true
			shift
			;;
		--i-know-this-wipes-my-disk)
			ACKNOWLEDGED=true
			shift
			;;
		-h | --help)
			usage
			exit 0
			;;
		-*)
			die "unknown option '$1'. Run --help."
			;;
		*)
			if [ -n "$TARGET_DEVICE" ]; then
				die "more than one device given: '$TARGET_DEVICE' and '$1'"
			fi
			TARGET_DEVICE="$1"
			shift
			;;
		esac
	done
}

validate_args() {
	case "$PROFILE" in
	desktop | laptop) ;;
	"")
		die "--profile is required and has no default. Choose desktop or laptop."
		;;
	*)
		die "unknown profile '$PROFILE'. Choose desktop or laptop."
		;;
	esac

	if [ -z "$HOSTNAME_VALUE" ]; then
		HOSTNAME_VALUE="hmlx${PROFILE}01"
	fi

	local cmdline_template="$REPO_ROOT/ansible/files/kernel-cmdline/$PROFILE"
	[ -r "$cmdline_template" ] || die "missing kernel command line profile at $cmdline_template"

	if [ -n "$AUTHORIZED_KEY" ]; then
		[ -r "$AUTHORIZED_KEY" ] || die "cannot read authorized key file '$AUTHORIZED_KEY'"
		# A test affordance must never be reachable on real hardware.
		if [ "$(systemd-detect-virt 2>/dev/null || echo none)" = "none" ]; then
			die "--authorized-key is a test affordance and only works in a virtual machine"
		fi
	fi

	if [ -n "$PASSPHRASE_FILE" ]; then
		[ -r "$PASSPHRASE_FILE" ] || die "cannot read passphrase file '$PASSPHRASE_FILE'"
		if [ "$(systemd-detect-virt 2>/dev/null || echo none)" = "none" ]; then
			die "--luks-passphrase-file is a test affordance and only works in a virtual machine"
		fi
	fi
}

# Partition names differ between /dev/sda1 and /dev/nvme0n1p1.
partition_path() {
	local number="$1"
	case "$TARGET_DEVICE" in
	*[0-9]) printf '%sp%s' "$TARGET_DEVICE" "$number" ;;
	*) printf '%s%s' "$TARGET_DEVICE" "$number" ;;
	esac
}

partition_disk() {
	log "Partitioning $TARGET_DEVICE"

	if [ "$DRY_RUN" = true ]; then
		printf '  would write a GPT with a %s MiB ESP and a LUKS partition filling the rest\n' "$ESP_SIZE_MIB"
		return 0
	fi

	sfdisk --wipe always --wipe-partitions always "$TARGET_DEVICE" <<SFDISK
label: gpt
size=${ESP_SIZE_MIB}MiB, type=uefi, name=ESP
type=linux, name=cryptroot
SFDISK

	udevadm settle
	partprobe "$TARGET_DEVICE" || true
	udevadm settle
}

encrypt_root() {
	local part
	part="$(partition_path 2)"

	log "Creating the LUKS2 container on $part"

	if [ -n "$PASSPHRASE_FILE" ]; then
		run_cmd cryptsetup luksFormat --type luks2 --pbkdf argon2id \
			--batch-mode --key-file "$PASSPHRASE_FILE" "$part"
		run_cmd cryptsetup open --key-file "$PASSPHRASE_FILE" "$part" cryptroot
	else
		printf 'You will be asked for the LUKS passphrase three times: twice to set it, once to open.\n'
		run_cmd cryptsetup luksFormat --type luks2 --pbkdf argon2id "$part"
		run_cmd cryptsetup open "$part" cryptroot
	fi
}

luks_uuid() {
	if [ "$DRY_RUN" = true ]; then
		printf '00000000-0000-0000-0000-000000000000'
		return 0
	fi
	cryptsetup luksUUID "$(partition_path 2)"
}

create_filesystems() {
	log "Creating filesystems"

	run_cmd mkfs.fat -F32 -n ESP "$(partition_path 1)"
	run_cmd mkfs.btrfs --force --label archwork /dev/mapper/cryptroot

	# Create every subvolume at the top level, then mount them individually.
	run_cmd mount /dev/mapper/cryptroot "$MOUNT_ROOT"

	local subvol
	for subvol in @ @home @var_log @var_cache @ai_models @snapshots; do
		run_cmd btrfs subvolume create "$MOUNT_ROOT/$subvol"
	done

	# @swap is laptop only, and carries the swapfile for hibernation (D-013).
	if [ "$PROFILE" = "laptop" ]; then
		run_cmd btrfs subvolume create "$MOUNT_ROOT/@swap"
		# Btrfs will not host a swapfile on a compressed copy-on-write
		# subvolume, so both are turned off here rather than at mount time.
		run_cmd chattr +C "$MOUNT_ROOT/@swap"
	fi

	run_cmd umount "$MOUNT_ROOT"
}

mount_filesystems() {
	log "Mounting"

	run_cmd mount -o "$MOUNT_OPTS,subvol=@" /dev/mapper/cryptroot "$MOUNT_ROOT"

	# /var/lib is deliberately absent from this list. It stays inside @ and
	# rolls back with it, because /var/lib/pacman must never survive a
	# rollback of @. See docs/decisions/storage-boot.md.
	local pair
	for pair in \
		"@home:/home" \
		"@var_log:/var/log" \
		"@var_cache:/var/cache" \
		"@ai_models:/var/lib/archwork/ai-models" \
		"@snapshots:/.snapshots"; do
		local subvol="${pair%%:*}"
		local target="${pair##*:}"
		run_cmd mkdir -p "$MOUNT_ROOT$target"
		run_cmd mount -o "$MOUNT_OPTS,subvol=$subvol" /dev/mapper/cryptroot "$MOUNT_ROOT$target"
	done

	if [ "$PROFILE" = "laptop" ]; then
		run_cmd mkdir -p "$MOUNT_ROOT/swap"
		# No compression on the swap subvolume.
		run_cmd mount -o "noatime,subvol=@swap" /dev/mapper/cryptroot "$MOUNT_ROOT/swap"
	fi

	run_cmd mkdir -p "$MOUNT_ROOT/efi"
	run_cmd mount "$(partition_path 1)" "$MOUNT_ROOT/efi"
}

base_packages() {
	local packages=(
		base linux linux-firmware
		btrfs-progs cryptsetup
		mkinitcpio
		networkmanager
		zram-generator
		sudo
		git
		vim
		# Ansible needs an interpreter on the target before it can do anything,
		# and every ArchWork machine runs the M2 reconciliation.
		# applications-tooling.md lists Python as platform tooling.
		python
	)

	case "$PROFILE" in
	desktop) packages+=(amd-ucode) ;;
	laptop) packages+=(intel-ucode) ;;
	esac

	if [ -n "$AUTHORIZED_KEY" ]; then
		packages+=(openssh)
	fi

	printf '%s\n' "${packages[@]}"
}

install_base() {
	log "Installing the base system"

	local packages=()
	mapfile -t packages < <(base_packages)

	run_cmd pacstrap -K "$MOUNT_ROOT" "${packages[@]}"

	if [ "$DRY_RUN" = true ]; then
		printf '  would write %s/etc/fstab from genfstab\n' "$MOUNT_ROOT"
	else
		genfstab -U "$MOUNT_ROOT" >>"$MOUNT_ROOT/etc/fstab"
	fi
}

create_swapfile() {
	[ "$PROFILE" = "laptop" ] || return 0

	log "Creating the hibernation swapfile"

	local ram_mib
	if [ "$DRY_RUN" = true ]; then
		ram_mib=8192
	else
		ram_mib="$(awk '/MemTotal/ {printf "%d", $2 / 1024}' /proc/meminfo)"
	fi

	run_cmd btrfs filesystem mkswapfile --size "${ram_mib}m" "$MOUNT_ROOT/swap/swapfile"

	if [ "$DRY_RUN" = true ]; then
		printf '  would append the swapfile to fstab\n'
	else
		printf '/swap/swapfile none swap defaults 0 0\n' >>"$MOUNT_ROOT/etc/fstab"
	fi
}

# The physical offset of the swapfile, needed for resume_offset. It cannot be
# written by hand, which is why the profile file carries a token.
resume_offset() {
	if [ "$DRY_RUN" = true ]; then
		printf '0'
		return 0
	fi
	btrfs inspect-internal map-swapfile -r "$MOUNT_ROOT/swap/swapfile"
}

# Strip comments and blank lines, substitute the tokens, collapse to one line.
render_cmdline() {
	local template="$1"
	local uuid="$2"
	local offset="${3:-}"

	# Substitute only non-empty values. An empty one must leave its token in
	# place so that the check below catches it: resume_offset= with nothing
	# after it is silently broken hibernation, not an error the kernel
	# reports.
	local -a substitutions=()
	[ -n "$uuid" ] && substitutions+=(-e "s|@LUKS_UUID@|$uuid|g")
	[ -n "$offset" ] && substitutions+=(-e "s|@RESUME_OFFSET@|$offset|g")

	local rendered
	rendered="$(grep -v -e '^\s*#' -e '^\s*$' "$template" |
		sed "${substitutions[@]}" |
		tr '\n' ' ' |
		sed -e 's/  */ /g' -e 's/ $//')"

	# Catch a token the installer forgot to substitute, without tripping over
	# rootflags=subvol=@.
	if printf '%s' "$rendered" | grep -q '@[A-Z_]\+@'; then
		die "unsubstituted token left in the kernel command line: $rendered"
	fi

	printf '%s' "$rendered"
}

configure_system() {
	log "Configuring the system"

	in_chroot ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
	in_chroot hwclock --systohc

	write_file "$MOUNT_ROOT/etc/locale.gen" "$LOCALE UTF-8"
	write_file "$MOUNT_ROOT/etc/locale.conf" "LANG=$LOCALE"
	write_file "$MOUNT_ROOT/etc/vconsole.conf" "KEYMAP=$KEYMAP"
	in_chroot locale-gen

	write_file "$MOUNT_ROOT/etc/hostname" "$HOSTNAME_VALUE"
	write_file "$MOUNT_ROOT/etc/hosts" "127.0.0.1 localhost
::1       localhost
127.0.1.1 $HOSTNAME_VALUE.localdomain $HOSTNAME_VALUE"

	# zram on both profiles (D-013).
	write_file "$MOUNT_ROOT/etc/systemd/zram-generator.conf" "[zram0]
zram-size = min(ram / 2, 8192)
compression-algorithm = zstd"

	if [ "$PROFILE" = "laptop" ]; then
		# Sleep first, hibernate later, so an overnight sleep does not
		# flatten the battery (D-013).
		write_file "$MOUNT_ROOT/etc/systemd/sleep.conf.d/archwork.conf" "[Sleep]
HibernateDelaySec=30min"
	fi

	in_chroot systemctl enable NetworkManager

	log "Creating the administrator account"
	in_chroot useradd --create-home --groups wheel --shell /bin/bash "$USERNAME"
	write_file "$MOUNT_ROOT/etc/sudoers.d/10-wheel" "%wheel ALL=(ALL:ALL) ALL" 0440

	if [ -n "$AUTHORIZED_KEY" ]; then
		log "Installing the test SSH key"
		local key
		key="$(cat "$AUTHORIZED_KEY")"
		write_file "$MOUNT_ROOT/home/$USERNAME/.ssh/authorized_keys" "$key" 0600
		in_chroot chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.ssh"
		in_chroot systemctl enable sshd
		# Passwordless sudo for the test account only, so assertions can run
		# unattended. Guarded to VM by validate_args.
		write_file "$MOUNT_ROOT/etc/sudoers.d/99-archwork-test" "$USERNAME ALL=(ALL:ALL) NOPASSWD: ALL" 0440
	fi
}

configure_initramfs() {
	log "Configuring mkinitcpio and the kernel command line"

	# systemd hooks, not busybox. TPM2 enrolment at M10 needs them, and
	# hibernating from LUKS needs the resume device in the initramfs.
	local hooks="base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck"

	write_file "$MOUNT_ROOT/etc/mkinitcpio.conf" "MODULES=()
BINARIES=()
FILES=()
HOOKS=($hooks)
COMPRESSION=\"zstd\""

	# The recovery image carries every module rather than an autodetected
	# set, so it can reach the disk when the tuned image cannot (D-014).
	local recovery_hooks="${hooks/ autodetect/}"
	write_file "$MOUNT_ROOT/etc/mkinitcpio-recovery.conf" "MODULES=()
BINARIES=()
FILES=()
HOOKS=($recovery_hooks)
COMPRESSION=\"zstd\""

	local uuid offset cmdline recovery_cmdline
	uuid="$(luks_uuid)"
	offset=""
	if [ "$PROFILE" = "laptop" ]; then
		offset="$(resume_offset)"
	fi

	cmdline="$(render_cmdline "$REPO_ROOT/ansible/files/kernel-cmdline/$PROFILE" "$uuid" "$offset")"
	write_file "$MOUNT_ROOT/etc/kernel/cmdline" "$cmdline"

	# Recovery drops to a rescue shell and says nothing quietly.
	recovery_cmdline="$(printf '%s' "$cmdline" | sed -e 's/ quiet loglevel=3//')"
	write_file "$MOUNT_ROOT/etc/kernel/cmdline-recovery" "$recovery_cmdline systemd.unit=rescue.target"

	write_file "$MOUNT_ROOT/etc/mkinitcpio.d/linux.preset" 'ALL_kver="/boot/vmlinuz-linux"

PRESETS=("default")

default_uki="/efi/EFI/Linux/archwork.efi"
default_options="--splash /usr/share/systemd/bootctl/splash-arch.bmp"'

	run_cmd mkdir -p "$MOUNT_ROOT/efi/EFI/Linux"
	in_chroot mkinitcpio -P
}

build_recovery_uki() {
	log "Building the recovery UKI"

	local kver
	if [ "$DRY_RUN" = true ]; then
		kver="0.0.0-arch1-1"
	else
		kver="$(arch-chroot "$MOUNT_ROOT" pacman -Q linux | awk '{print $2}')-arch1-1"
		kver="$(arch-chroot "$MOUNT_ROOT" sh -c 'ls /usr/lib/modules | head -1')"
	fi

	in_chroot mkinitcpio \
		--config /etc/mkinitcpio-recovery.conf \
		--kernel "$kver" \
		--cmdline /etc/kernel/cmdline-recovery \
		--uki /efi/EFI/Linux/archwork-recovery.efi
}

install_bootloader() {
	log "Installing systemd-boot"

	in_chroot bootctl install

	write_file "$MOUNT_ROOT/efi/loader/loader.conf" "default archwork.efi
timeout 3
console-mode keep
editor no"
}

# D-015: sulogin refuses to open a shell when the root account is locked, and a
# fresh Arch installation leaves it locked. Without this the recovery UKI boots
# to rescue mode and hands the operator a dead console, which makes the whole
# recovery path from D-011 and D-014 useless.
#
# Forcing sulogin is safe here because root already sits behind LUKS2. Anyone
# who can reach this prompt has typed the passphrase, and D-008 keeps that a
# real prompt until TPM2 enrolment at M10.
configure_rescue_shell() {
	log "Allowing the rescue shell to open without a root password"

	write_file "$MOUNT_ROOT/etc/systemd/system/rescue.service.d/10-archwork-sulogin.conf" \
		"# D-015. sulogin refuses a locked root account, and a fresh Arch
# install leaves root locked. LUKS2 already gates access to this shell.
[Service]
Environment=SYSTEMD_SULOGIN_FORCE=1"
}

install_rollback_script() {
	log "Installing the rollback script"

	if [ "$DRY_RUN" = true ]; then
		printf '  would install %s to /usr/local/bin/archwork-rollback\n' "$SCRIPT_DIR/archwork-rollback"
		return 0
	fi

	install -Dm755 "$SCRIPT_DIR/archwork-rollback" \
		"$MOUNT_ROOT/usr/local/bin/archwork-rollback"
}

finish() {
	log "Done"
	cat <<SUMMARY

  device    $TARGET_DEVICE
  profile   $PROFILE
  hostname  $HOSTNAME_VALUE
  user      $USERNAME

Set a password for $USERNAME before rebooting:

  arch-chroot $MOUNT_ROOT passwd $USERNAME

SUMMARY
}

main() {
	parse_args "$@"
	validate_args

	guard_check_all "$TARGET_DEVICE" "$ACKNOWLEDGED" || exit 1

	if [ "$DRY_RUN" = true ]; then
		printf '\nDRY RUN. Nothing below is executed.\n'
	else
		guard_confirm_target "$TARGET_DEVICE" || exit 1
	fi

	partition_disk
	encrypt_root
	create_filesystems
	mount_filesystems
	install_base
	create_swapfile
	configure_system
	configure_initramfs
	build_recovery_uki
	install_bootloader
	configure_rescue_shell
	install_rollback_script
	finish
}

# Sourcing with ARCHWORK_LIB_ONLY set gives the tests access to the functions
# without running an installation. Nothing else should set it.
if [ "${ARCHWORK_LIB_ONLY:-0}" != "1" ]; then
	main "$@"
fi
