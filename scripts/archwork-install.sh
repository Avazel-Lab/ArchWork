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
# What the operator typed, before symlink resolution. Messages only.
TARGET_DEVICE_GIVEN=""
AUTHORIZED_KEY=""
PASSPHRASE_FILE=""
EXPECT_SERIAL=""
REPO_URL=""
REPO_PATH="src/ArchWork"
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
  --hostname NAME                 defaults to hmlxdesktop02 or hmlxlaptop01
  --user NAME                     administrator account, default 'gary'
  --dry-run                       print every command, write nothing
  --i-know-this-wipes-my-disk     permit running outside a virtual machine
  --expect-serial SERIAL          refuse unless the target reports this serial.
                                  Optional, and worth giving where the machine
                                  holds another disk you care about: a device
                                  path is not proof of which disk you meant
  --authorized-key FILE           install an SSH key and enable sshd.
                                  VM only. Used by the M1 test harness.
  --repo-url URL                  upstream remote for the cloned repository.
                                  Defaults to this checkout's origin.
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
		--expect-serial)
			EXPECT_SERIAL="${2:-}"
			shift 2
			;;
		--repo-url)
			REPO_URL="${2:-}"
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

# Resolve the target to its kernel name, keeping what the operator typed.
#
# D-017 says to address the disk as /dev/disk/by-id/nvme-...-SERIAL, because
# the two NVMe drives in the desktop are the same model and size and the
# nvme0n1 names can swap between boots. That instruction was right and this
# script could not follow it.
#
# Two things were wrong with a by-id path, and the guards caught the second
# before it mattered. partition_path appends 1 to a path ending in a letter,
# so a by-id path produced ...SERIAL1 where udev makes ...SERIAL-part1. And
# guard_is_whole_disk looks the device up in /sys/block under its own name,
# which for a by-id path is a mangled string that is not there, so the install
# refused to start rather than starting and failing halfway through.
#
# Refusing was the right failure and a confusing one: the message says the
# path might be a partition, which it is not. Resolving the symlink first
# makes the documented path work. Operations use the resolved name, messages
# keep the given one, because a serial is what a person can check against the
# label on a drive and nvme0n1 is not.
resolve_target_device() {
	[ -n "$TARGET_DEVICE" ] || return 0

	TARGET_DEVICE_GIVEN="$TARGET_DEVICE"

	# readlink -f resolves a path whose final component does not exist, so
	# existence is checked rather than inferred from its exit status.
	[ -e "$TARGET_DEVICE" ] || die "no such device '$TARGET_DEVICE'"

	local resolved
	resolved="$(readlink -f "$TARGET_DEVICE" 2>/dev/null || true)"
	[ -n "$resolved" ] || die "cannot resolve '$TARGET_DEVICE' to a device"

	TARGET_DEVICE="$resolved"
}

# Let the operator name the disk, not just point at it.
#
# The desktop holds two Samsung 970 EVO Plus 2 TB drives. One is the ArchWork
# target and one is the Kubuntu root, they are the same model and size, and
# their nvme0n1 names can swap between boots. A device path is therefore not
# proof of which disk was meant, and the only other thing separating them is a
# serial read off a confirmation prompt by a person who has been awake too
# long.
#
# Offered rather than required, deliberately. Requiring it would mean looking
# up a serial before every install on every machine, and the target is not
# always a disk with a neighbour worth protecting. Where it is, this turns
# reading carefully into a check the machine makes.
guard_expected_serial() {
	local actual

	[ -n "$EXPECT_SERIAL" ] || return 0

	actual="$(lsblk --nodeps --noheadings --output SERIAL "$TARGET_DEVICE" 2>/dev/null | tr -d '[:space:]')"

	if [ -z "$actual" ]; then
		die "'$TARGET_DEVICE' reports no serial, so --expect-serial cannot be checked against it"
	fi

	if [ "$actual" != "$EXPECT_SERIAL" ]; then
		die "'$TARGET_DEVICE' has serial $actual, not $EXPECT_SERIAL. Nothing was written."
	fi

	printf 'target serial %s matches\n' "$actual"
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
		# Not hmlx${PROFILE}01. The desktop hardware already carries
		# hmlxdesktop01 on its Kubuntu development install, and the two dual
		# boot on the same box, so the Arch side takes the next number in the
		# estate convention (D-010).
		case "$PROFILE" in
		desktop) HOSTNAME_VALUE="hmlxdesktop02" ;;
		laptop) HOSTNAME_VALUE="hmlxlaptop01" ;;
		esac
	fi

	# The stock Arch ISO does not ship git, and rev-parse below would report
	# that as "not a git checkout", which sends you looking in the wrong place.
	command -v git >/dev/null ||
		die "git is not installed. The Arch ISO does not ship it, and D-016 needs it to clone this repository onto the target. Run: pacman -Sy git"

	git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1 ||
		die "$REPO_ROOT is not a git checkout, so there is nothing to clone onto the target"

	if [ -z "$REPO_URL" ]; then
		REPO_URL="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true)"
		[ -n "$REPO_URL" ] || die "this checkout has no origin remote. Pass --repo-url."
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

# The ISO boots a US console layout. configure_system writes KEYMAP=uk and
# configure_initramfs puts sd-vconsole in the image, so the LUKS prompt at
# every boot from now on is UK. A passphrase set here and typed back there
# would disagree on @ " # \ | ~, which is an encrypted disk that cannot be
# opened by the person who just encrypted it (D-017). Loading the installed
# system's keymap before the passphrase is set removes the trap instead of
# documenting it.
#
# It fails the install rather than warning. Continuing past it is how the
# passphrase gets set on the wrong layout, and that is discovered at the
# first reboot, after the disk has been written.
set_console_keymap() {
	log "Loading the $KEYMAP console keymap, the layout the installed system will use"

	if [ "$DRY_RUN" != true ] && ! command -v loadkeys >/dev/null 2>&1; then
		die "loadkeys is not present, so the console cannot be put on the $KEYMAP layout the installed system boots with. It ships with the Arch ISO in the kbd package. Install kbd and run this again."
	fi

	if ! run_cmd loadkeys "$KEYMAP"; then
		die "loadkeys $KEYMAP failed, so the console layout does not match the $KEYMAP layout the installed system boots with. Fix that before setting a passphrase: a passphrase typed on the wrong layout cannot open the disk afterwards."
	fi
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
		# The target configures itself (D-016), so these cannot wait for the
		# playbook that needs them, nor for a network bootstrap has not yet
		# brought up. age in particular decrypts the WiFi PSK that a
		# wireless-only laptop needs before it has any network at all.
		# applications-tooling.md lists all three as platform tooling.
		python
		ansible
		age
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

# Multilib, on the profile that games (D-029).
#
# Steam is a multilib package and the stock pacman.conf ships that repository
# commented out. Ansible enables it too, and cannot be the only thing that
# does: `ansible-playbook --check` changes nothing by definition, so on a fresh
# machine the dry run would still not know about steam and would fail against a
# machine that is perfectly fine. M2 requires that check to pass.
#
# The packages role reconciling the same file is deliberate rather than
# duplication. D-027 noted that files written only by this installer are a real
# gap in what reconciliation can reach afterwards; enabling it in both places
# means a machine installed before this existed still converges.
configure_multilib() {
	[ "$PROFILE" = "desktop" ] || return 0

	log "Enabling the multilib repository"

	if [ "$DRY_RUN" = true ]; then
		printf '  would uncomment [multilib] in %s/etc/pacman.conf\n' "$MOUNT_ROOT"
		return 0
	fi

	local conf="$MOUNT_ROOT/etc/pacman.conf"
	[ -f "$conf" ] || die "no pacman.conf at $conf"

	# Anchored on the commented pair the stock file ships, so this is a no-op
	# on a file that already has it and never touches [multilib-testing].
	# sed rather than perl: this runs on the Arch ISO, which carries sed in
	# base and does not promise perl.
	sed -i '/^#\[multilib\]$/{N;s/^#\[multilib\]\n#Include = \(.*\)$/[multilib]\nInclude = \1/}' "$conf"

	grep -q '^\[multilib\]' "$conf" ||
		die "could not enable multilib in $conf. Its [multilib] section is not the stock one."

	# Sync the new repository's database, or the machine arrives knowing the
	# repository exists and nothing that is in it. That is not a cosmetic
	# difference: `ansible-playbook --check` does not refresh the database,
	# because a dry run changes nothing, so the first thing it does on a fresh
	# machine is fail to find steam. A run on 2026-09-02 got exactly that far
	# twice, once before this function existed and once after, because the
	# first version enabled the repository and left the database alone.
	in_chroot pacman -Sy --noconfirm
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

# The target configures itself (D-016), so the repository has to be on it
# before first boot. A wireless-only laptop has no network then, and the WiFi
# PSK it needs to get one lives in the encrypted secrets inside this
# repository.
clone_repository() {
	local destination="/home/$USERNAME/$REPO_PATH"

	log "Cloning the repository to $destination"

	if [ "$DRY_RUN" = true ]; then
		printf '  would clone %s to %s%s\n' "$REPO_ROOT" "$MOUNT_ROOT" "$destination"
		printf '  would set origin to %s\n' "$REPO_URL"
		printf '  would chown the clone to %s\n' "$USERNAME"
		return 0
	fi

	mkdir -p "$MOUNT_ROOT$(dirname "$destination")"

	# Clone the checkout this installer runs from rather than fetching fresh,
	# so the installed system carries exactly the commit that built it.
	git clone "$REPO_ROOT" "$MOUNT_ROOT$destination"

	# A clone keeps its source as origin, which here is a path on the ISO.
	# That works perfectly until the first git pull.
	git -C "$MOUNT_ROOT$destination" remote set-url origin "$REPO_URL"

	arch-chroot "$MOUNT_ROOT" chown -R "$USERNAME:$USERNAME" \
		"/home/$USERNAME/$(dirname "$REPO_PATH")"
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

Then reboot and run bootstrap.sh from the cloned repository at
/home/$USERNAME/$REPO_PATH. It configures this machine on the machine itself:
no second machine is involved (D-016).

SUMMARY
}

main() {
	parse_args "$@"
	resolve_target_device
	validate_args

	guard_check_all "$TARGET_DEVICE" "$ACKNOWLEDGED" || exit 1
	guard_expected_serial

	if [ "$DRY_RUN" = true ]; then
		printf '\nDRY RUN. Nothing below is executed.\n'
	else
		guard_confirm_target "$TARGET_DEVICE" "$TARGET_DEVICE_GIVEN" || exit 1
	fi

	set_console_keymap
	partition_disk
	encrypt_root
	create_filesystems
	mount_filesystems
	install_base
	configure_multilib
	create_swapfile
	configure_system
	clone_repository
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
