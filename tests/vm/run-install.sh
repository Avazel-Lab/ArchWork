#!/usr/bin/env bash
#
# L3: install ArchWork into a throwaway VM and assert the M1 criteria.
#
# Needs QEMU and nested virtualisation. CI cannot run this and does not
# pretend to: see docs/plan.md.
#
# Three phases per run:
#   1. Boot the stock Arch ISO, hand it a provision script, install, power off.
#   2. Boot the installed disk, answer the LUKS prompt over the serial console.
#   3. Run the M1 assertions over SSH.
#
# Record the result in docs/STATUS.yml with a commit SHA. A rebuild claim
# without one did not happen.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

ISO=""
PROFILE="desktop"
DISK_SIZE="24G"
MEMORY="4096"
CPUS="4"
REPEAT=1
KEEP=false
WORK_DIR=""
HTTP_PORT="8000"
SSH_PORT="2222"
GUEST_DISK="/dev/vda"
PASSPHRASE="archwork-test-passphrase"

HTTP_PID=""
QEMU_PID=""
REPO_SHA=""

usage() {
	cat <<'USAGE'
run-install.sh --iso PATH [options]

Installs ArchWork into a throwaway VM and asserts the M1 exit criteria.

Required:
  --iso PATH            stock Arch Linux ISO

Options:
  --profile NAME        desktop or laptop, default desktop
  --repeat N            consecutive runs, default 1. M1 needs 2.
  --disk-size SIZE      default 24G
  --memory MB           default 4096
  --cpus N              default 4
  --keep                keep the work directory for inspection
  -h, --help            this text

Needs qemu-system-x86_64, an OVMF firmware image and nested virtualisation.
USAGE
}

die() {
	printf 'error: %s\n' "$1" >&2
	exit 1
}

log() {
	printf '\n\033[1m==> %s\033[0m\n' "$1"
}

kill_if_running() {
	local pid="${1:-}"
	if [ -n "$pid" ]; then
		kill "$pid" 2>/dev/null || true
	fi
}

cleanup() {
	kill_if_running "$QEMU_PID"
	kill_if_running "$HTTP_PID"
	if [ "$KEEP" = false ] && [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ]; then
		rm -rf "$WORK_DIR"
	elif [ -n "$WORK_DIR" ]; then
		printf '\nwork directory kept at %s\n' "$WORK_DIR"
	fi
}

parse_args() {
	while [ $# -gt 0 ]; do
		case "$1" in
		--iso)
			ISO="${2:-}"
			shift 2
			;;
		--profile)
			PROFILE="${2:-}"
			shift 2
			;;
		--repeat)
			REPEAT="${2:-}"
			shift 2
			;;
		--disk-size)
			DISK_SIZE="${2:-}"
			shift 2
			;;
		--memory)
			MEMORY="${2:-}"
			shift 2
			;;
		--cpus)
			CPUS="${2:-}"
			shift 2
			;;
		--keep)
			KEEP=true
			shift
			;;
		-h | --help)
			usage
			exit 0
			;;
		*)
			die "unknown argument '$1'. Run --help."
			;;
		esac
	done
}

check_prerequisites() {
	command -v qemu-system-x86_64 >/dev/null || die "qemu-system-x86_64 not found"
	command -v bsdtar >/dev/null || die "bsdtar not found, needed to read the ISO"
	command -v ssh >/dev/null || die "ssh not found"

	[ -n "$ISO" ] || die "--iso is required and has no default"
	[ -r "$ISO" ] || die "cannot read ISO '$ISO'"

	case "$PROFILE" in
	desktop | laptop) ;;
	*) die "unknown profile '$PROFILE'" ;;
	esac

	[ -e /dev/kvm ] || die "/dev/kvm is missing. This needs nested virtualisation."

	OVMF_CODE=""
	local candidate
	for candidate in \
		/usr/share/edk2/x64/OVMF_CODE.4m.fd \
		/usr/share/edk2-ovmf/x64/OVMF_CODE.fd \
		/usr/share/OVMF/OVMF_CODE_4M.fd \
		/usr/share/OVMF/OVMF_CODE.fd; do
		if [ -r "$candidate" ]; then
			OVMF_CODE="$candidate"
			break
		fi
	done
	[ -n "$OVMF_CODE" ] || die "no OVMF firmware found. Install edk2-ovmf."

	OVMF_VARS="${OVMF_CODE/CODE/VARS}"
	[ -r "$OVMF_VARS" ] || die "no OVMF variable template beside $OVMF_CODE"
}

prepare_work_dir() {
	WORK_DIR="$(mktemp -d /tmp/archwork-vm.XXXXXX)"
	trap cleanup EXIT

	log "Work directory $WORK_DIR"

	# The provisioner fetches these over HTTP from the host.
	printf '%s' "$PASSPHRASE" >"$WORK_DIR/passphrase"
	printf '%s' "$PROFILE" >"$WORK_DIR/profile"
	printf '%s' "$GUEST_DISK" >"$WORK_DIR/disk"

	ssh-keygen -q -t ed25519 -N "" -f "$WORK_DIR/id_test" -C archwork-m1-test
	cp "$WORK_DIR/id_test.pub" "$WORK_DIR/id_test.pub.served"
	mv "$WORK_DIR/id_test.pub.served" "$WORK_DIR/id_test.pub"

	# The repository as the guest will see it. Committed state only, so a
	# dirty tree cannot quietly change what the test installs.
	git -C "$REPO_ROOT" archive --format=tar --prefix="" HEAD >"$WORK_DIR/repo.tar"

	# Record the commit that went into that archive, not whatever HEAD points at
	# when the run ends. A commit landing mid-run would otherwise be reported as
	# the tested SHA, and docs/STATUS.yml treats that SHA as proof.
	REPO_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD)"

	cp "$SCRIPT_DIR/provision.sh" "$WORK_DIR/provision.sh"

	cp "$OVMF_VARS" "$WORK_DIR/OVMF_VARS.fd"
	chmod u+w "$WORK_DIR/OVMF_VARS.fd"
}

extract_iso_boot_files() {
	log "Extracting the kernel and initramfs from the ISO"

	# archiso's script= parameter needs the kernel booted directly, because
	# QEMU cannot edit the ISO boot menu unattended.
	bsdtar -xf "$ISO" -C "$WORK_DIR" \
		arch/boot/x86_64/vmlinuz-linux \
		arch/boot/x86_64/initramfs-linux.img ||
		die "could not extract boot files from '$ISO'"

	ISO_LABEL="$(blkid -o value -s LABEL "$ISO" 2>/dev/null || true)"
	[ -n "$ISO_LABEL" ] || die "could not read the ISO label from '$ISO'"
	printf 'ISO label: %s\n' "$ISO_LABEL"
}

start_http_server() {
	log "Serving $WORK_DIR on port $HTTP_PORT"
	(cd "$WORK_DIR" && python3 -m http.server "$HTTP_PORT" --bind 127.0.0.1 >"$WORK_DIR/http.log" 2>&1) &
	HTTP_PID=$!
	sleep 1
	kill -0 "$HTTP_PID" 2>/dev/null || die "the HTTP server did not start, see $WORK_DIR/http.log"
}

qemu_base_args() {
	printf '%s\n' \
		-machine q35,accel=kvm \
		-cpu host \
		-smp "$CPUS" \
		-m "$MEMORY" \
		-drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE" \
		-drive "if=pflash,format=raw,file=$WORK_DIR/OVMF_VARS.fd" \
		-drive "if=virtio,format=qcow2,file=$WORK_DIR/disk.qcow2" \
		-no-reboot
}

phase_install() {
	log "Phase 1: installing from the ISO"

	qemu-img create -f qcow2 "$WORK_DIR/disk.qcow2" "$DISK_SIZE" >/dev/null

	local args=()
	mapfile -t args < <(qemu_base_args)

	qemu-system-x86_64 \
		"${args[@]}" \
		-netdev "user,id=net0" \
		-device virtio-net-pci,netdev=net0 \
		-nographic \
		-cdrom "$ISO" \
		-kernel "$WORK_DIR/arch/boot/x86_64/vmlinuz-linux" \
		-initrd "$WORK_DIR/arch/boot/x86_64/initramfs-linux.img" \
		-append "archisobasedir=arch archisolabel=$ISO_LABEL console=ttyS0 script=http://10.0.2.2:$HTTP_PORT/provision.sh" \
		2>&1 | tee "$WORK_DIR/install-console.log"

	grep -q "Install finished" "$WORK_DIR/install-console.log" ||
		die "the installer did not finish, see $WORK_DIR/install-console.log"
}

phase_boot() {
	log "Phase 2: booting the installed system"

	local args=()
	mapfile -t args < <(qemu_base_args)

	qemu-system-x86_64 \
		"${args[@]}" \
		-netdev "user,id=net0,hostfwd=tcp::$SSH_PORT-:22" \
		-device virtio-net-pci,netdev=net0 \
		-display none \
		-serial "unix:$WORK_DIR/serial.sock,server,nowait" \
		-daemonize -pidfile "$WORK_DIR/qemu.pid" ||
		die "QEMU failed to start for the boot phase"

	QEMU_PID="$(cat "$WORK_DIR/qemu.pid")"

	log "Answering the LUKS passphrase prompt over serial"
	python3 "$SCRIPT_DIR/serial-unlock.py" \
		--socket "$WORK_DIR/serial.sock" \
		--passphrase-file "$WORK_DIR/passphrase" \
		--log "$WORK_DIR/boot-console.log" ||
		die "the system did not reach a login prompt, see $WORK_DIR/boot-console.log"
}

phase_assert() {
	log "Phase 3: asserting the M1 criteria"

	# ssh takes the port as -p, scp takes it as -P. Sharing one array between
	# them made scp read the port number as a local filename.
	local common_opts=(
		-i "$WORK_DIR/id_test"
		-o StrictHostKeyChecking=no
		-o UserKnownHostsFile=/dev/null
		-o LogLevel=ERROR
		-o ConnectTimeout=5
	)
	local ssh_opts=(-p "$SSH_PORT" "${common_opts[@]}")
	local scp_opts=(-P "$SSH_PORT" "${common_opts[@]}")

	local attempt
	for attempt in $(seq 1 30); do
		if ssh "${ssh_opts[@]}" gary@127.0.0.1 true 2>/dev/null; then
			break
		fi
		[ "$attempt" -eq 30 ] && die "could not reach the VM over SSH"
		sleep 2
	done

	# Push the assertion library and script, then run them as root.
	ssh "${ssh_opts[@]}" gary@127.0.0.1 "mkdir -p /tmp/checks/lib"
	scp "${scp_opts[@]}" -q "$SCRIPT_DIR/assert-m1.sh" gary@127.0.0.1:/tmp/checks/
	scp "${scp_opts[@]}" -q "$SCRIPT_DIR/lib/checks.sh" gary@127.0.0.1:/tmp/checks/lib/

	# The profile goes over as a file so that it expands on the guest rather
	# than here, which keeps the remote command free of local expansion.
	scp "${scp_opts[@]}" -q "$WORK_DIR/profile" gary@127.0.0.1:/tmp/checks/profile

	ssh "${ssh_opts[@]}" gary@127.0.0.1 \
		'chmod +x /tmp/checks/assert-m1.sh && sudo /tmp/checks/assert-m1.sh "$(cat /tmp/checks/profile)"' 
}

main() {
	parse_args "$@"
	check_prerequisites
	prepare_work_dir
	extract_iso_boot_files
	start_http_server

	local run
	for run in $(seq 1 "$REPEAT"); do
		log "Run $run of $REPEAT"
		phase_install
		phase_boot
		phase_assert

		kill_if_running "$QEMU_PID"
		QEMU_PID=""
		rm -f "$WORK_DIR/disk.qcow2" "$WORK_DIR/serial.sock"

		# The UEFI variable store outlives the disk, so run 2 would otherwise
		# boot with run 1 boot entries pointing at a disk that no longer
		# exists. Each run gets a fresh firmware environment.
		cp "$OVMF_VARS" "$WORK_DIR/OVMF_VARS.fd"
		chmod u+w "$WORK_DIR/OVMF_VARS.fd"
	done

	log "All $REPEAT run(s) passed"
	printf '\nRecord this in docs/STATUS.yml with the commit SHA:\n'
	printf '  %s\n\n' "$REPO_SHA"
}

main "$@"
