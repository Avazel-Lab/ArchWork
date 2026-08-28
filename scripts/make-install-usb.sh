#!/usr/bin/env bash
#
# Write an Arch Linux installation image to a USB stick.
#
# This destroys every byte on the target. It is a much smaller blast radius
# than scripts/archwork-install.sh, but the failure mode is the same one: the
# wrong device path. It therefore carries the same guards, plus one of its own,
# because the target here should always be removable.
#
# Usage:
#   make-install-usb.sh [options] --iso FILE /dev/sdX
#
# See --help.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source-path=SCRIPTDIR source=lib/guards.sh
source "$SCRIPT_DIR/lib/guards.sh"

TARGET_DEVICE=""
ISO_PATH=""
EXPECTED_SHA256=""
DRY_RUN=false
ACKNOWLEDGED=false
BLOCK_SIZE="4M"

usage() {
	cat <<'USAGE'
make-install-usb.sh [options] --iso FILE DEVICE

Writes an Arch installation image to DEVICE. DEVICE is destroyed. There is no
default, and the target must be removable unless you say otherwise.

Required:
  DEVICE                          whole disk to write to, e.g. /dev/sdc
  --iso FILE                      the Arch ISO to write

Options:
  --sha256 SUM                    verify the ISO against this checksum before
                                  writing anything. Take it from the sha256sums
                                  file on an Arch mirror.
  --dry-run                       print every command, write nothing
  --i-know-this-wipes-my-disk     permit a device that reports removable=0
  -h, --help                      this text

Needs root, because it writes to a block device.

The stick this produces is the stock Arch installation medium: it carries no
ArchWork code. Nothing is added to it, because appending a partition to an
isohybrid image means moving the backup GPT header, and a stick that boots is
worth more than a stick that saves one git clone.

So the procedure is:

  1. Boot the stick. Choose it from the firmware boot menu.
  2. Get networking up. The desktop has ethernet, so it is already up.
  3. pacman -Sy git, because the stock ISO does not ship it.
  4. git clone https://github.com/Avazel-Lab/ArchWork
  5. Run ArchWork/scripts/archwork-install.sh against the target disk.

The installer clones the checkout it runs from onto the target (D-016), so the
installed machine carries the commit that built it.
USAGE
}

die() {
	printf 'error: %s\n' "$1" >&2
	exit 1
}

log() {
	printf '\n==> %s\n' "$1"
}

run_cmd() {
	if [ "$DRY_RUN" = true ]; then
		printf '  would run:'
		printf ' %q' "$@"
		printf '\n'
		return 0
	fi
	"$@"
}

parse_args() {
	while [ $# -gt 0 ]; do
		case "$1" in
		--iso)
			ISO_PATH="${2:-}"
			shift 2
			;;
		--sha256)
			EXPECTED_SHA256="${2:-}"
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
	[ -n "$ISO_PATH" ] || die "--iso is required and has no default"
	[ -r "$ISO_PATH" ] || die "cannot read the ISO at '$ISO_PATH'"
	[ -f "$ISO_PATH" ] || die "'$ISO_PATH' is not a regular file"

	if [ "$DRY_RUN" = false ] && [ "$(id -u)" -ne 0 ]; then
		die "writing to a block device needs root. Re-run under sudo, or pass --dry-run."
	fi
}

iso_size() {
	stat --format '%s' "$ISO_PATH"
}

# Verify before writing, not after. A corrupt download that reaches the stick
# intact passes a read-back comparison and fails at boot, which is a much worse
# place to find out.
verify_iso() {
	if [ -z "$EXPECTED_SHA256" ]; then
		log "No --sha256 given, so the ISO itself is unverified"
		return 0
	fi

	log "Verifying the ISO against the given checksum"

	local actual
	actual="$(sha256sum "$ISO_PATH" | cut -d' ' -f1)"

	if [ "$actual" != "$EXPECTED_SHA256" ]; then
		die "ISO checksum mismatch.
  expected $EXPECTED_SHA256
  got      $actual"
	fi

	printf '  ISO matches\n'
}

write_image() {
	log "Writing $ISO_PATH to $TARGET_DEVICE"

	run_cmd dd if="$ISO_PATH" of="$TARGET_DEVICE" \
		bs="$BLOCK_SIZE" conv=fsync oflag=direct status=progress

	run_cmd sync
}

# Read the image back off the stick and compare it. dd reporting success means
# the kernel accepted the writes, which is not the same as the stick having
# stored them: a failing stick that silently drops writes is exactly the
# hardware this catches, and it is common enough to be worth the read.
verify_written() {
	log "Reading the image back off $TARGET_DEVICE"

	if [ "$DRY_RUN" = true ]; then
		printf '  would compare the first %s bytes of %s against the ISO\n' \
			"$(iso_size)" "$TARGET_DEVICE"
		return 0
	fi

	# Drop the page cache for this device, so the comparison reads flash
	# rather than the copy of the ISO still sitting in memory.
	blockdev --flushbufs "$TARGET_DEVICE"

	local bytes expected actual
	bytes="$(iso_size)"
	expected="$(sha256sum "$ISO_PATH" | cut -d' ' -f1)"
	actual="$(head -c "$bytes" "$TARGET_DEVICE" | sha256sum | cut -d' ' -f1)"

	if [ "$expected" != "$actual" ]; then
		die "the stick does not match the ISO.
  expected $expected
  got      $actual
The write was accepted and the data is not there. Suspect the stick."
	fi

	printf '  %s matches the ISO\n' "$TARGET_DEVICE"
}

finish() {
	log "Done"
	cat <<SUMMARY

  image     $ISO_PATH
  device    $TARGET_DEVICE

Boot it from the firmware boot menu, then follow the procedure in --help.

SUMMARY
}

main() {
	parse_args "$@"
	validate_args

	# The image is checked before the device, because nothing about the
	# target matters if the thing being written is wrong. Both checks are
	# read-only and both come before any confirmation prompt, so the order
	# between them costs nothing.
	verify_iso

	guard_is_whole_disk "$TARGET_DEVICE" || exit 1
	guard_not_mounted "$TARGET_DEVICE" || exit 1
	guard_not_boot_medium "$TARGET_DEVICE" || exit 1
	guard_is_removable_or_acknowledged "$TARGET_DEVICE" "$ACKNOWLEDGED" || exit 1

	if [ "$DRY_RUN" = true ]; then
		printf '\nDRY RUN. Nothing below is executed.\n'
	else
		guard_confirm_target "$TARGET_DEVICE" || exit 1
	fi

	write_image
	verify_written
	finish
}

if [ "${ARCHWORK_LIB_ONLY:-0}" != "1" ]; then
	main "$@"
fi
