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

# Host-side, and the only library this script sources. lib/checks.sh is the
# guest's and is copied there rather than read here.
# shellcheck source-path=SCRIPTDIR source=lib/workdir.sh
source "$SCRIPT_DIR/lib/workdir.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

ISO=""
PROFILE="desktop"
DISK_SIZE="24G"
MEMORY="4096"
CPUS="4"
REPEAT=1
KEEP=false
RECONCILE=false
POWER=false
ROLLBACK=false
WORK_DIR=""
# A kept work directory to boot again instead of installing into a new one.
# Set by --resume, and never a source of evidence: see run_phases.
RESUME_DIR=""
PHASES="greeter,session,desktop,portals"
HTTP_PORT="8000"
# Long enough for a slow mirror, short enough that a wedged install fails the
# run rather than holding it open indefinitely.
INSTALL_TIMEOUT="1800"
SSH_PORT="2222"
GUEST_DISK="/dev/vda"
PASSPHRASE="archwork-test-passphrase"
# What gets typed at the greeter (D-021). Separate from the LUKS passphrase so
# that a run cannot pass by conflating the two, and restricted to characters
# that sendkey.py can type under both the uk and us keymaps.
LOGIN_PASSWORD="archwork-test-login"
LOGIN_USER="gary"
# The background colour dotfiles/hypr/hyprlock.conf paints, which is how the
# harness tells the lock screen from the desktop it covers. Change it there and
# change it here.
LOCK_BACKGROUND="28,28,28"
CAPTURE_DIR=""

HTTP_PID=""
QEMU_PID=""
REPO_SHA=""

# ssh spells the port -p and scp spells it -P, where -p means preserve times.
# Sharing one array between them made scp read the port number as a filename.
SSH_OPTS=()
SCP_OPTS=()

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
  --keep                keep the work directory, disk image included, so that
                        --resume has something to boot
  --resume DIR          boot the disk in a kept work directory and run the
                        phases again, instead of installing from scratch.
                        Implies --keep and needs no --iso
  --phases LIST         comma separated, for --resume. Default
                        greeter,session,desktop,portals. Also accepts assert,
                        recovery and power. The power phase measures the M4
                        timings and takes just over an hour on its own
  --captures DIR        copy the screen captures here, since D-021 has a
                        person judge appearance by looking at them
  --reconcile           run the M2 Ansible reconciliation twice and require
                        the second run to change nothing
  --power               measure the M4 timings after the desktop phases.
                        Needs --reconcile, and adds about 65 minutes: the
                        criteria are two idle windows of half an hour
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
	save_captures
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
		--resume)
			RESUME_DIR="${2:-}"
			KEEP=true
			shift 2
			;;
		--phases)
			PHASES="${2:-}"
			shift 2
			;;
		--captures)
			CAPTURE_DIR="${2:-}"
			shift 2
			;;
		--reconcile)
			RECONCILE=true
			shift
			;;
		--power)
			POWER=true
			shift
			;;
		--rollback)
			ROLLBACK=true
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

# Take over a work directory a previous run kept, rather than building one.
#
# The machine in that image was installed by that earlier run, and nothing here
# changes it: a resumed run re-runs the harness against a machine that already
# exists. That makes it the right tool for a bug in the harness, which is what
# four of the runs on 2026-08-29 were, and the wrong tool for a change to this
# repository, which the machine's own clone knows nothing about.
#
# The credentials, the profile and the login come out of the kept directory
# rather than from this script's defaults, because they belong to that machine.
adopt_work_dir() {
	WORK_DIR="$RESUME_DIR"
	trap cleanup EXIT

	log "Resuming in $WORK_DIR"

	PROFILE="$(cat "$WORK_DIR/profile")"
	LOGIN_USER="$(cat "$WORK_DIR/login-user")"
	LOGIN_PASSWORD="$(cat "$WORK_DIR/login-password")"
	PASSPHRASE="$(cat "$WORK_DIR/passphrase")"

	local common_opts=(
		-i "$WORK_DIR/id_test"
		-o StrictHostKeyChecking=no
		-o UserKnownHostsFile=/dev/null
		-o LogLevel=ERROR
		-o ConnectTimeout=5
		# The power phase holds one connection open across a 30 minute
		# idle window, on a guest that is deliberately doing nothing.
		-o ServerAliveInterval=30
		-o ServerAliveCountMax=10
	)
	SSH_OPTS=(-p "$SSH_PORT" "${common_opts[@]}")
	SCP_OPTS=(-P "$SSH_PORT" "${common_opts[@]}")

	# Not REPO_SHA. Nothing here was built from the checkout that is present
	# now, and run_phases refuses to print an evidence line for that reason.
	REPO_SHA=""
}

# The phases a resumed run is allowed to repeat, named rather than dispatched
# by whatever string arrives.
#
# phase_install and phase_reconcile are deliberately absent. Installing is what
# resuming skips, and reconciling would run the machine's own clone, which is
# whatever the earlier run put there rather than what is checked out now.
# Check the phase list before anything is booted.
#
# Both of these were found the hard way. An unknown phase name used to fail
# after the machine had booted, and a desktop phase without a session failed
# with "check-session.sh: command not found", which pointed at nothing useful.
#
# A resumed run boots from cold, so it arrives at the greeter with nobody
# logged in and an empty /tmp. phase_session is what types the password and
# what puts the check scripts on the machine, so every phase that asks the
# session a question needs it in the list first.
validate_phases() {
	local phase
	for phase in ${PHASES//,/ }; do
		case "$phase" in
		assert | greeter | session | desktop | portals | power | rollback | recovery) ;;
		*) die "'$phase' is not a phase that can be resumed. Try assert, greeter, session, desktop, portals, power, rollback or recovery." ;;
		esac

		case "$phase" in
		desktop | portals | power)
			case ",$PHASES," in
			*,session,*) ;;
			*) die "'$phase' needs a logged in session, so 'session' has to come before it in --phases. A resumed run starts at the greeter." ;;
			esac
			;;
		esac
	done
}

run_phases() {
	local phase
	for phase in ${PHASES//,/ }; do
		case "$phase" in
		assert) phase_assert ;;
		greeter) phase_greeter ;;
		session) phase_session ;;
		desktop) phase_desktop ;;
		portals) phase_portals ;;
		power) phase_power ;;
		rollback) phase_rollback ;;
		recovery) phase_recovery ;;
		esac
	done
}

# One place that knows how to ask, so the readiness wait and the preflight
# check cannot disagree about what "in use" means.
port_in_use() {
	ss -ltn "sport = :$1" 2>/dev/null | grep -q LISTEN
}

check_prerequisites() {
	command -v qemu-system-x86_64 >/dev/null || die "qemu-system-x86_64 not found"
	command -v bsdtar >/dev/null || die "bsdtar not found, needed to read the ISO"
	command -v ssh >/dev/null || die "ssh not found"
	command -v ss >/dev/null || die "ss not found, needed to check the ports are free"

	# Both ports are fixed, so a run that died holding one makes the next run
	# fail somewhere much less obvious. Say so here instead.
	local port
	for port in "$HTTP_PORT" "$SSH_PORT"; do
		if port_in_use "$port"; then
			die "port $port is already in use, probably by a run that did not clean up. Find it with: ss -ltnp 'sport = :$port'"
		fi
	done

	if [ -n "$RESUME_DIR" ]; then
		validate_phases
		[ -d "$RESUME_DIR" ] || die "no such work directory '$RESUME_DIR'"
		local needed
		for needed in disk.qcow2 OVMF_VARS.fd passphrase id_test profile; do
			[ -e "$RESUME_DIR/$needed" ] ||
				die "'$RESUME_DIR' has no $needed, so it cannot be resumed. A run keeps its disk image only with --keep."
		done
	else
		[ -n "$ISO" ] || die "--iso is required and has no default"
		[ -r "$ISO" ] || die "cannot read ISO '$ISO'"
	fi

	# The power phase asks a logged in session about its idle behaviour, and
	# a machine that has only been installed has no session at all.
	if [ "$POWER" = true ] && [ "$RECONCILE" = false ] && [ -z "$RESUME_DIR" ]; then
		die "--power needs --reconcile: the timings are measured in a logged in session, and only a reconciled machine has a greeter to log in at"
	fi

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
	# Respect TMPDIR. The work directory holds the disk image, which reached
	# 9.8G on the M4 runs. On a machine where /tmp is a tmpfs that image lives
	# in RAM, so a disk-backed TMPDIR is the difference between a slow run and
	# one that stops when the filesystem fills.
	#
	# Checked rather than only described. That comment was here, in those
	# words, on the day a run went into a 16 GiB tmpfs and QEMU paused the
	# guest on ENOSPC for nine and a half hours.
	local root="${TMPDIR:-/tmp}" refusal
	if ! refusal="$(work_dir_refusal "$root")"; then
		die "$refusal. Set TMPDIR to somewhere with room: TMPDIR=~/.cache/archwork/vm-tmp make ..."
	fi

	WORK_DIR="$(mktemp -d "$root/archwork-vm.XXXXXX")"
	trap cleanup EXIT

	log "Work directory $WORK_DIR"

	# The provisioner fetches these over HTTP from the host.
	printf '%s' "$PASSPHRASE" >"$WORK_DIR/passphrase"
	printf '%s' "$LOGIN_USER" >"$WORK_DIR/login-user"
	printf '%s' "$LOGIN_PASSWORD" >"$WORK_DIR/login-password"
	printf '%s' "$PROFILE" >"$WORK_DIR/profile"
	printf '%s' "$GUEST_DISK" >"$WORK_DIR/disk"

	ssh-keygen -q -t ed25519 -N "" -f "$WORK_DIR/id_test" -C archwork-m1-test

	local common_opts=(
		-i "$WORK_DIR/id_test"
		-o StrictHostKeyChecking=no
		-o UserKnownHostsFile=/dev/null
		-o LogLevel=ERROR
		-o ConnectTimeout=5
	)
	SSH_OPTS=(-p "$SSH_PORT" "${common_opts[@]}")
	SCP_OPTS=(-P "$SSH_PORT" "${common_opts[@]}")
	cp "$WORK_DIR/id_test.pub" "$WORK_DIR/id_test.pub.served"
	mv "$WORK_DIR/id_test.pub.served" "$WORK_DIR/id_test.pub"

	# The repository as the guest will see it. Committed state only, so a
	# dirty tree cannot quietly change what the test installs.
	#
	# A bundle rather than a tar, because D-016 made the installer clone the
	# checkout it runs from. git archive produces no .git, so the installer
	# refuses it and the D-016 path could never have run. A bundle carries the
	# history, so the guest gets a real checkout and the machine it installs
	# ends up recording the commit that built it.
	local branch
	branch="$(git -C "$REPO_ROOT" symbolic-ref --quiet --short HEAD || true)"
	if [ -n "$branch" ]; then
		# Name HEAD as well as the branch. A bundle carrying only
		# refs/heads/<branch> has no HEAD, and git clone then falls back to
		# guessing the default branch name: it checks out nothing at all,
		# with a warning rather than an error, unless the branch happens to
		# be called main. Naming both lands the clone on the branch, which
		# is where a machine that will later git pull wants to be.
		git -C "$REPO_ROOT" bundle create "$WORK_DIR/repo.bundle" HEAD "$branch" >/dev/null
	else
		git -C "$REPO_ROOT" bundle create "$WORK_DIR/repo.bundle" HEAD >/dev/null
	fi

	# Where the installed machine should fetch from afterwards. Without this
	# the clone keeps the bundle path as origin, and assert-m1.sh rejects an
	# origin that points at the ISO.
	git -C "$REPO_ROOT" remote get-url origin >"$WORK_DIR/repo-url" 2>/dev/null ||
		die "this checkout has no origin remote, so the guest has nothing to point at"

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

	# No subshell. --directory does what the cd did, and $! is then python's
	# own pid rather than a subshell's. With the subshell, cleanup killed the
	# wrapper and left python holding the port, so the next run died with
	# nothing more useful than "the HTTP server did not start".
	python3 -m http.server "$HTTP_PORT" --bind 127.0.0.1 \
		--directory "$WORK_DIR" >"$WORK_DIR/http.log" 2>&1 &
	HTTP_PID=$!

	# Wait for the port to answer, not for the process to exist. A process
	# that is about to fail to bind is still alive a moment after starting.
	local waited=0
	until port_in_use "$HTTP_PORT"; do
		waited=$((waited + 1))
		if [ "$waited" -gt 20 ]; then
			die "the HTTP server did not come up, see $WORK_DIR/http.log"
		fi
		sleep 0.5
	done
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
		-vga none \
		-no-reboot
}

phase_install() {
	log "Phase 1: installing from the ISO"

	qemu-img create -f qcow2 "$WORK_DIR/disk.qcow2" "$DISK_SIZE" >/dev/null

	local args=()
	mapfile -t args < <(qemu_base_args)

	timeout "$INSTALL_TIMEOUT" qemu-system-x86_64 \
		"${args[@]}" \
		-netdev "user,id=net0" \
		-device virtio-net-pci,netdev=net0 \
		-nographic \
		-cdrom "$ISO" \
		-kernel "$WORK_DIR/arch/boot/x86_64/vmlinuz-linux" \
		-initrd "$WORK_DIR/arch/boot/x86_64/initramfs-linux.img" \
		-append "archisobasedir=arch archisolabel=$ISO_LABEL console=ttyS0 script=http://10.0.2.2:$HTTP_PORT/provision.sh" \
		2>&1 | tee "$WORK_DIR/install-console.log"

	if grep -q "Install FAILED" "$WORK_DIR/install-console.log"; then
		die "the installer reported failure, see $WORK_DIR/install-console.log"
	fi

	grep -q "Install finished" "$WORK_DIR/install-console.log" ||
		die "the installer did not finish within ${INSTALL_TIMEOUT}s, see $WORK_DIR/install-console.log"
}

# Boot the installed disk. Both the normal boot and the recovery boot need
# this, so it takes no view on which entry the firmware will pick.
start_installed_vm() {
	local args=()
	mapfile -t args < <(qemu_base_args)

	rm -f "$WORK_DIR/serial.sock" "$WORK_DIR/monitor.sock"

	qemu-system-x86_64 \
		"${args[@]}" \
		-netdev "user,id=net0,hostfwd=tcp::$SSH_PORT-:22" \
		-device virtio-net-pci,netdev=net0 \
		-display none \
		-device virtio-vga \
		-serial "unix:$WORK_DIR/serial.sock,server,nowait" \
		-monitor "unix:$WORK_DIR/monitor.sock,server,nowait" \
		-daemonize -pidfile "$WORK_DIR/qemu.pid" ||
		die "QEMU failed to start"

	QEMU_PID="$(cat "$WORK_DIR/qemu.pid")"
}

phase_boot() {
	log "Phase 2: booting the installed system"

	start_installed_vm

	log "Answering the LUKS passphrase prompt over serial"
	python3 "$SCRIPT_DIR/serial-unlock.py" \
		--socket "$WORK_DIR/serial.sock" \
		--passphrase-file "$WORK_DIR/passphrase" \
		--log "$WORK_DIR/boot-console.log" ||
		die "the system did not reach a login prompt, see $WORK_DIR/boot-console.log"
}

# The greeter is the first M3 criterion that nothing the guest says can prove.
# A machine can report greetd active over SSH while the screen shows a blank
# console or a stack trace, so this looks at the framebuffer from outside.
phase_greeter() {
	log "Phase 5: proving the greeter reaches the screen"

	python3 "$SCRIPT_DIR/screendump.py" \
		--monitor "$WORK_DIR/monitor.sock" \
		--output "$WORK_DIR/greeter.ppm" \
		--wait 90 ||
		die "no greeter appeared on the display. The last capture, if any, is at $WORK_DIR/greeter.ppm"
}

# D-021: log in by typing at the greeter, because a session started any other
# way skips the PAM stack that the keyring criterion is about. Nothing inside
# the guest takes part: the keys go onto the emulated keyboard from outside.
phase_session() {
	log "Phase 7: logging in at the greeter and asserting the session"

	# tuigreet takes the user name, then the password. The pause matters: the
	# password field does not exist until the name is submitted, and keys sent
	# before it does are dropped rather than queued.
	python3 "$SCRIPT_DIR/sendkey.py" \
		--monitor "$WORK_DIR/monitor.sock" \
		--text "$LOGIN_USER" --enter ||
		die "could not type the user name at the greeter"
	sleep 3
	python3 "$SCRIPT_DIR/sendkey.py" \
		--monitor "$WORK_DIR/monitor.sock" \
		--text "$LOGIN_PASSWORD" --enter ||
		die "could not type the password at the greeter"

	log "Waiting for the compositor to come up"

	# The socket directory Hyprland creates for its instance. Present only
	# once the compositor is running, and it belongs to the user, so it says
	# the login worked rather than that something started.
	local attempt
	for attempt in $(seq 1 45); do
		if ssh "${SSH_OPTS[@]}" gary@127.0.0.1 \
			'test -n "$(ls -A "/run/user/$(id -u)/hypr" 2>/dev/null)"' 2>/dev/null; then
			break
		fi
		if [ "$attempt" -eq 45 ]; then
			# Keep whatever is on screen: a rejected password and a crashed
			# compositor look identical from out here, and different on it.
			python3 "$SCRIPT_DIR/screendump.py" \
				--monitor "$WORK_DIR/monitor.sock" \
				--output "$WORK_DIR/session-failed.ppm" \
				--allow-blank --wait 5 || true
			die "no session appeared after the login. The screen at that point is at $WORK_DIR/session-failed.ppm"
		fi
		sleep 2
	done

	# What the session looks like, for the person who judges appearance (D-021).
	python3 "$SCRIPT_DIR/screendump.py" \
		--monitor "$WORK_DIR/monitor.sock" \
		--output "$WORK_DIR/session.ppm" \
		--wait 30 ||
		die "the session drew nothing on the screen, see $WORK_DIR/session.ppm"

	ssh "${SSH_OPTS[@]}" gary@127.0.0.1 "mkdir -p /tmp/checks/lib"
	scp "${SCP_OPTS[@]}" -q "$SCRIPT_DIR/assert-m3.sh" gary@127.0.0.1:/tmp/checks/
	scp "${SCP_OPTS[@]}" -q "$SCRIPT_DIR/check-session.sh" gary@127.0.0.1:/tmp/checks/
	scp "${SCP_OPTS[@]}" -q "$SCRIPT_DIR/lib/checks.sh" gary@127.0.0.1:/tmp/checks/lib/
	ssh "${SSH_OPTS[@]}" gary@127.0.0.1 "chmod +x /tmp/checks/check-session.sh"

	ssh "${SSH_OPTS[@]}" gary@127.0.0.1 \
		'chmod +x /tmp/checks/assert-m3.sh && sudo /tmp/checks/assert-m3.sh gary'
}

# Press a key on the guest's keyboard, from outside the guest.
press() {
	python3 "$SCRIPT_DIR/sendkey.py" --monitor "$WORK_DIR/monitor.sock" "$@"
}

# Ask the machine one question about its session.
#
# The arguments are quoted for the remote shell rather than pasted into it.
# ssh joins its arguments into one string and hands them to a shell on the
# other end, so anything meaningful to a shell is interpreted there, whatever
# quoting was used here. A check for kitty's window title, which is ~, went
# over as a bare tilde and came back as a check for /home/gary.
ask() {
	local quoted
	quoted="$(printf '%q ' "$@")"
	# shellcheck disable=SC2029 # quoted is deliberately expanded here: it is
	# the check and its arguments, already escaped for the shell that runs them.
	ssh "${SSH_OPTS[@]}" gary@127.0.0.1 "sudo /tmp/checks/check-session.sh $quoted"
}

# Keep whatever is on screen, whether or not anything is drawn on it. Used
# where a capture is evidence for a person rather than an assertion.
capture() {
	python3 "$SCRIPT_DIR/screendump.py" \
		--monitor "$WORK_DIR/monitor.sock" \
		--output "$WORK_DIR/$1.ppm" \
		--allow-blank --wait 5 >/dev/null 2>&1 || true
}

# The M3 criteria that describe using the machine: open a terminal, launch an
# application from the launcher, lock the session, unlock it. Every one of them
# is a real key press at the framebuffer followed by a question asked over SSH,
# because a keybinding that never fired and a compositor that ignored it look
# identical from inside the guest.
#
# Pressing the binding rather than running the command is the point. Half of
# what M3 delivers is the configuration that maps SUPER+Return to a terminal,
# and hyprctl dispatch exec would prove kitty runs while saying nothing about
# whether the desktop can start it.
phase_desktop() {
	log "Phase 8: using the desktop the way the M3 criteria describe"

	log "SUPER+Return opens a terminal"
	press --key meta_l-ret
	ask --wait 20 client_class_present "$LOGIN_USER" kitty || {
		capture terminal-failed
		die "SUPER+Return opened no terminal. The screen is at $WORK_DIR/terminal-failed.ppm"
	}

	# Wait for the shell to reach a prompt, not just for the window to exist.
	# kitty titles the window with the working directory once its shell
	# integration sees a prompt; before that it treats bash as a running
	# command and SUPER+Q raises a confirmation dialog rather than closing.
	ask --wait 20 client_title_present "$LOGIN_USER" kitty "~" || {
		capture terminal-not-ready
		printf 'the terminal never reached a shell prompt. What the compositor had:\n' >&2
		ask list_clients "$LOGIN_USER" >&2 || true
		die "kitty did not reach a prompt. The screen is at $WORK_DIR/terminal-not-ready.ppm"
	}

	log "SUPER+Q closes it"
	press --key meta_l-q
	ask --wait 20 client_class_absent "$LOGIN_USER" kitty || {
		capture close-failed
		die "SUPER+Q left the terminal open. The screen is at $WORK_DIR/close-failed.ppm"
	}

	log "SUPER+D opens the launcher"
	press --key meta_l-d
	ask --wait 20 user_process_running "$LOGIN_USER" fuzzel || {
		capture launcher-failed
		die "SUPER+D opened no launcher. The screen is at $WORK_DIR/launcher-failed.ppm"
	}

	log "The launcher starts an application"
	press --text kitty
	sleep 1
	press --key ret
	ask --wait 30 client_class_present "$LOGIN_USER" kitty || {
		capture launch-failed
		die "the launcher started nothing. The screen is at $WORK_DIR/launch-failed.ppm"
	}

	# The desktop in use, for the person who judges appearance (D-021).
	capture desktop

	log "SUPER+L locks the session"
	press --key meta_l-l
	ask --wait 20 user_process_running "$LOGIN_USER" hyprlock || {
		capture lock-failed
		die "SUPER+L did not lock the session. The screen is at $WORK_DIR/lock-failed.ppm"
	}

	# The process is not the lock screen. hyprlock appears in the process table
	# well before its surface takes the display, and on 2026-08-29 the harness
	# typed the password into that gap: the capture taken the moment the
	# process check passed shows the desktop, waybar and a terminal, all still
	# fully on screen. Every keystroke went to the terminal underneath.
	#
	# So wait for the screen itself. The background colour is the one
	# dotfiles/hypr/hyprlock.conf sets, which the desktop does not have, and
	# there must be something drawn on it as well, because hyprlock paints its
	# background before it paints the clock and the field.
	log "Waiting for the lock screen to take the display"
	python3 "$SCRIPT_DIR/screendump.py" \
		--monitor "$WORK_DIR/monitor.sock" \
		--output "$WORK_DIR/locked.ppm" \
		--expect-dominant "$LOCK_BACKGROUND" \
		--wait 30 ||
		die "the lock screen never reached the display. The screen is at $WORK_DIR/locked.ppm"

	log "The login password unlocks it"
	# Two attempts, never more. Arch enables pam_faillock, which locks the
	# account after three failures, so a harness that retried freely would turn
	# a slow lock screen into a locked-out account and a much more confusing
	# failure. A failed attempt clears hyprlock's buffer, so the second attempt
	# starts clean without needing to flush anything.
	local attempt
	for attempt in 1 2; do
		press --text "$LOGIN_PASSWORD" --enter
		if ask --wait 20 process_absent "$LOGIN_USER" hyprlock; then
			break
		fi
		if [ "$attempt" -eq 2 ]; then
			capture unlock-failed
			die "the session stayed locked after 2 password attempts. The screen is at $WORK_DIR/unlock-failed.ppm"
		fi
		log "No unlock on attempt $attempt, trying once more"
	done
	capture unlocked
}

# Open one application from the launcher and ask it for a file picker, then
# assert that the window which appears is not its own.
#
# Ctrl+O is the accelerator both toolkits conventionally use. Whether each of
# these two applications actually binds it is the part no document settles, so
# a failure here prints every window the compositor has rather than only
# saying no: one run then names what to press instead (D-023).
# Reports rather than dies, so that one run says something about both
# applications. Dying on the first would mean a failure in the GTK half hides
# whatever the Qt half would have shown, and each run costs a full install.
open_picker() {
	local label="$1" match="$2" app_class="$3" dismiss="${4:-no}"
	local short="${app_class##*.}"

	log "$label opens a file picker through the portal"

	press --key meta_l-d
	if ! ask --wait 20 user_process_running "$LOGIN_USER" fuzzel; then
		printf 'the launcher did not open for %s\n' "$label" >&2
		return 1
	fi

	press --text "$match"
	sleep 1
	press --key ret
	if ! ask --wait 60 client_class_present "$LOGIN_USER" "$app_class"; then
		capture "picker-$short-no-window"
		printf '%s never opened a window. What the compositor had:\n' "$label" >&2
		ask list_clients "$LOGIN_USER" >&2 || true
		press --key esc
		return 1
	fi

	# Some applications open on a modal that swallows the accelerator. PDF
	# Arranger greets a new profile with one about what cropping does not do,
	# and its OK is the default button.
	if [ "$dismiss" = dismiss ]; then
		sleep 1
		press --key ret
	fi

	press --key ctrl-o
	if ! ask --wait 30 file_picker_open "$LOGIN_USER" "$app_class"; then
		capture "picker-$short-failed"
		printf '%s opened no file picker on ctrl-o. What the compositor had:\n' "$label" >&2
		ask list_clients "$LOGIN_USER" >&2 || true
		press --key esc
		press --key meta_l-q
		return 1
	fi

	# For the person who judges appearance, and because a picker that opens
	# unthemed or unreadable still passes the assertion above (D-021).
	capture "picker-$short"

	press --key esc
	press --key meta_l-q
}

# "Portals work. A file picker opens from a GTK application and from a Qt
# application." assert-m3.sh only pings the portal, which says it is reachable
# and nothing about a picker, so the criterion is finished here where there is
# a keyboard and a screen.
#
# The two applications are chosen in D-023, both named in the application
# baseline rather than installed for the test alone. Okular replaced
# kvantummanager on 2026-08-29 once a run showed Kvantum Manager binds no
# accelerator at all: its only picker sits behind a button, and it chooses a
# directory rather than a file.
phase_portals() {
	log "Phase 9: the portal file picker, from GTK and from Qt"

	local failures=0
	open_picker "PDF Arranger (GTK)" pdf com.github.jeromerobert.pdfarranger dismiss ||
		failures=$((failures + 1))
	open_picker "Okular (Qt)" okular org.kde.okular || failures=$((failures + 1))

	[ "$failures" -eq 0 ] ||
		die "$failures of 2 file picker criteria failed. The captures are in $WORK_DIR"
}

# M4: dim at 5 minutes, display off at 15, sleep at 30, and a sleep inhibitor
# that suppresses the last of those and neither of the first two.
#
# Just over an hour, in two idle windows of half an hour each, because the
# criteria are wall clock times and nothing can fast-forward the compositor's
# idle counter. Both windows start with a keystroke from out here: real input
# is the only thing that resets that counter, and a guest cannot produce it
# for itself.
#
# The inhibited window comes first. If it ran second, a machine that had just
# suspended and woken would be answering questions about a session that had
# been through S3, and a failure would not say which of the two caused it.
phase_power() {
	log "Phase 10: the M4 power and sleep timings, about 65 minutes"

	ssh "${SSH_OPTS[@]}" gary@127.0.0.1 "mkdir -p /tmp/checks/lib"
	scp "${SCP_OPTS[@]}" -q "$SCRIPT_DIR/assert-m4.sh" gary@127.0.0.1:/tmp/checks/
	scp "${SCP_OPTS[@]}" -q "$SCRIPT_DIR/lib/checks.sh" gary@127.0.0.1:/tmp/checks/lib/
	ssh "${SSH_OPTS[@]}" gary@127.0.0.1 "chmod +x /tmp/checks/assert-m4.sh"

	# The user name and, later, T0 go over as files and expand on the guest,
	# the same way phase_assert hands over the profile. A remote command
	# built by expanding here is a remote command the local shell has
	# already had an opinion about.
	printf '%s\n' "$LOGIN_USER" | ssh "${SSH_OPTS[@]}" gary@127.0.0.1 "cat > /tmp/checks/user"

	ssh "${SSH_OPTS[@]}" gary@127.0.0.1 \
		'sudo /tmp/checks/assert-m4.sh config "$(cat /tmp/checks/user)"' ||
		die "the M4 configuration is wrong on the machine, so the timings below would measure something else"

	log "Holding a one hour sleep inhibitor, then going idle for 30 minutes"
	ssh "${SSH_OPTS[@]}" gary@127.0.0.1 "archwork-inhibit 1h" ||
		die "archwork-inhibit would not start"

	# The keystroke resets the idle clock, and the guest's own clock records
	# when. Reading T0 on the guest keeps the assertions free of any skew
	# between the two machines.
	press --key shift || die "could not send the keystroke that starts the idle window"
	ssh "${SSH_OPTS[@]}" gary@127.0.0.1 "date +%s > /tmp/checks/t0"

	ssh "${SSH_OPTS[@]}" gary@127.0.0.1 \
		'sudo /tmp/checks/assert-m4.sh inhibited "$(cat /tmp/checks/user)" "$(cat /tmp/checks/t0)"' ||
		die "the M4 criteria failed under a held inhibitor"

	log "Releasing the inhibitor and going idle again, this time to sleep"
	ssh "${SSH_OPTS[@]}" gary@127.0.0.1 "archwork-inhibit --cancel"

	press --key shift || die "could not send the keystroke that starts the idle window"
	ssh "${SSH_OPTS[@]}" gary@127.0.0.1 "date +%s > /tmp/checks/t0"

	# Measured out here: see suspend-watch.py. The window is the same one
	# assert-m4.sh applies to the other two timings.
	local slept
	slept="$(python3 "$SCRIPT_DIR/suspend-watch.py" \
		--monitor "$WORK_DIR/monitor.sock" --wait "$((1800 + 60))")" ||
		die "the machine never suspended, with nothing inhibiting it"

	if [ "$slept" -lt 1800 ]; then
		die "the machine suspended after ${slept}s, before the 1800s the configuration asks for"
	fi
	printf '  ok    the machine suspended\n        at %ss, wanted 1800 to 1860\n' "$slept"

	log "Waking it, the way a key on a sleeping machine would"
	python3 "$SCRIPT_DIR/suspend-watch.py" \
		--monitor "$WORK_DIR/monitor.sock" --wake ||
		die "the machine did not come back from suspend"

	# S3 takes the network with it, so the connection has to be remade rather
	# than reused.
	local attempt
	for attempt in $(seq 1 30); do
		ssh "${SSH_OPTS[@]}" gary@127.0.0.1 true 2>/dev/null && break
		[ "$attempt" -eq 30 ] && die "the machine woke but never answered SSH again"
		sleep 2
	done

	ssh "${SSH_OPTS[@]}" gary@127.0.0.1 \
		'sudo /tmp/checks/assert-m4.sh woke "$(cat /tmp/checks/user)" "$(cat /tmp/checks/t0)"' ||
		die "the machine slept and woke, but not the way M4 describes"

	capture after-wake
}

# D-021 judges appearance by looking at the captures, so a run that throws them
# away leaves that criterion unprovable.
save_captures() {
	[ -n "$CAPTURE_DIR" ] || return 0
	[ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ] || return 0

	mkdir -p "$CAPTURE_DIR"
	local capture
	for capture in "$WORK_DIR"/*.ppm; do
		[ -e "$capture" ] || continue
		cp "$capture" "$CAPTURE_DIR/"
	done
	printf '\nCaptures saved in %s. Look at them: nothing else judges appearance.\n' "$CAPTURE_DIR"
}

phase_assert() {
	log "Phase 3: asserting the M1 criteria"

	local attempt
	for attempt in $(seq 1 30); do
		if ssh "${SSH_OPTS[@]}" gary@127.0.0.1 true 2>/dev/null; then
			break
		fi
		[ "$attempt" -eq 30 ] && die "could not reach the VM over SSH"
		sleep 2
	done

	# Push the assertion library and script, then run them as root.
	ssh "${SSH_OPTS[@]}" gary@127.0.0.1 "mkdir -p /tmp/checks/lib"
	scp "${SCP_OPTS[@]}" -q "$SCRIPT_DIR/assert-m1.sh" gary@127.0.0.1:/tmp/checks/
	scp "${SCP_OPTS[@]}" -q "$SCRIPT_DIR/lib/checks.sh" gary@127.0.0.1:/tmp/checks/lib/

	# The profile goes over as a file so that it expands on the guest rather
	# than here, which keeps the remote command free of local expansion.
	scp "${SCP_OPTS[@]}" -q "$WORK_DIR/profile" gary@127.0.0.1:/tmp/checks/profile

	ssh "${SSH_OPTS[@]}" gary@127.0.0.1 \
		'chmod +x /tmp/checks/assert-m1.sh && sudo /tmp/checks/assert-m1.sh "$(cat /tmp/checks/profile)"' 
}

# M2 asks for a real run followed by a second run reporting zero changed tasks.
# Idempotence catches more real problems here than unit tests will, and the
# only honest way to show it is to run the thing twice against a fresh machine.
phase_reconcile() {
	log "Phase 4: reconciling with Ansible on the guest, twice"

	# D-016: the machine configures itself. SSH here is the terminal driving a
	# VM nobody can physically touch, not Ansible's transport. The playbook,
	# the inventory and the connection all live on the guest, which is exactly
	# what a real machine does.
	#
	# That also means this runs the committed inventory rather than one
	# generated for the test. group_vars/all.yml sets ansible_connection to
	# local, and the installer set the host name inventory/hosts.yml names.
	scp "${SCP_OPTS[@]}" -q "$SCRIPT_DIR/reconcile.sh" gary@127.0.0.1:/tmp/reconcile.sh
	ssh "${SSH_OPTS[@]}" gary@127.0.0.1 "chmod +x /tmp/reconcile.sh"

	# M2 asks that --check runs clean against a fresh machine. It runs first,
	# while there is genuinely something for it to report.
	log "Reconciliation check run"
	ssh "${SSH_OPTS[@]}" gary@127.0.0.1 \
		/tmp/reconcile.sh check \
		2>&1 | tee "$WORK_DIR/reconcile-check.log" ||
		die "the --check run failed, see $WORK_DIR/reconcile-check.log"

	local run_number
	for run_number in 1 2; do
		log "Reconciliation run $run_number of 2"
		ssh "${SSH_OPTS[@]}" gary@127.0.0.1 \
			/tmp/reconcile.sh run \
			2>&1 | tee "$WORK_DIR/reconcile-$run_number.log" ||
			die "reconciliation run $run_number failed, see $WORK_DIR/reconcile-$run_number.log"
	done

	# A second run that changes anything means a task is not idempotent.
	local changed
	changed="$(sed -n 's/.*changed=\([0-9]\+\).*/\1/p' "$WORK_DIR/reconcile-2.log" | tail -1)"
	[ -n "$changed" ] || die "could not read changed= from the second run recap"

	if [ "$changed" -ne 0 ]; then
		die "the second reconciliation changed $changed task(s), so it is not idempotent. See $WORK_DIR/reconcile-2.log"
	fi

	printf '\nSecond run reported changed=0, with Ansible running on the guest.\n'

	# Idempotence says the tasks settle, not what they settle on. D-025 turned
	# off a group that reaches root without a prompt, and a role that turned it
	# back on would be just as idempotent about it.
	log "Asserting the service state reconciliation settled on"
	ssh "${SSH_OPTS[@]}" gary@127.0.0.1 "mkdir -p /tmp/checks/lib"
	scp "${SCP_OPTS[@]}" -q "$SCRIPT_DIR/assert-m2.sh" gary@127.0.0.1:/tmp/checks/
	scp "${SCP_OPTS[@]}" -q "$SCRIPT_DIR/lib/checks.sh" gary@127.0.0.1:/tmp/checks/lib/
	ssh "${SSH_OPTS[@]}" gary@127.0.0.1 \
		'chmod +x /tmp/checks/assert-m2.sh && sudo /tmp/checks/assert-m2.sh gary'
}

# M5: break the machine on purpose, roll it back, and check it came back.
#
# Everything broken here is inside @, which is the only thing archwork-rollback
# touches. That is not incidental to the test, it is the test: a break on the
# ESP or in /home would survive the rollback by design, and choosing one of
# those would prove the rollback had failed when it had done exactly what
# storage-boot.md says.
#
# The package removal is the point of the last criterion. /usr and
# /var/lib/pacman both live in @ and roll back together, so pacman's idea of
# what is installed and what is actually on disk stay in step. If @var_lib were
# ever carved out, they would not, and this is the check that would notice.
phase_rollback() {
	log "Phase 11: break the machine, roll it back, check it came back"

	ssh "${SSH_OPTS[@]}" gary@127.0.0.1 'mkdir -p /tmp/checks'

	printf '\nBefore anything is broken\n'
	ssh "${SSH_OPTS[@]}" gary@127.0.0.1 'sudo /usr/local/bin/archwork-health' ||
		die "the machine was not healthy before the rollback test, so nothing after this would mean anything"

	log "Taking the snapshot to roll back to"
	ssh "${SSH_OPTS[@]}" gary@127.0.0.1 'sudo /usr/local/bin/archwork-snapshot' ||
		die "could not take a snapshot to roll back to"

	# The name goes into a file on the guest and expands there, the way
	# phase_power hands over T0. A snapshot name pasted into a remote command
	# is a remote command the local shell has already had an opinion about.
	ssh "${SSH_OPTS[@]}" gary@127.0.0.1 \
		'sudo /usr/local/bin/archwork-rollback list | tail -1 > /tmp/checks/snapshot'
	local snapshot
	snapshot="$(ssh "${SSH_OPTS[@]}" gary@127.0.0.1 'cat /tmp/checks/snapshot')"
	[ -n "$snapshot" ] || die "archwork-rollback lists no snapshots, so btrbk did not make one"
	log "Rolling back to $snapshot later"

	# Break it. tailscale is a package the health check asks about by name, it
	# is not needed to reach the machine over SSH, and removing it changes both
	# /usr and /var/lib/pacman, which is the pair the last criterion is about.
	log "Breaking the machine on purpose"
	ssh "${SSH_OPTS[@]}" gary@127.0.0.1 \
		'sudo systemctl stop tailscaled.service && sudo pacman -Rdd --noconfirm tailscale' ||
		die "could not break the machine, so the rollback would prove nothing"

	printf '\nWith the machine deliberately broken\n'
	if ssh "${SSH_OPTS[@]}" gary@127.0.0.1 'sudo /usr/local/bin/archwork-health'; then
		die "the health check passed on a machine with tailscale removed, so it is not checking what it claims"
	fi
	printf '  ok    the health check noticed\n'

	log "Rolling back"
	# The script asks for a typed confirmation, which is right at a keyboard
	# and wrong here, so the answer goes in on stdin.
	ssh "${SSH_OPTS[@]}" gary@127.0.0.1 \
		'printf "rollback\n" | sudo /usr/local/bin/archwork-rollback to "$(cat /tmp/checks/snapshot)"' ||
		die "archwork-rollback failed"

	log "Rebooting onto the rolled-back root"
	reboot_guest 420 || die "the guest did not come back after the rollback"

	printf '\nAfter the rollback\n'
	ssh "${SSH_OPTS[@]}" gary@127.0.0.1 'sudo /usr/local/bin/archwork-health' ||
		die "the health check still fails after the rollback"
	printf '  ok    the health check passes again\n'

	# The criterion in plan.md, and the reason /var/lib may never be carved
	# out of @. -Qk asks pacman whether the files it believes it installed are
	# on the disk; a database that rolled back separately from the files it
	# describes answers no.
	ssh "${SSH_OPTS[@]}" gary@127.0.0.1 'sudo pacman -Qk >/dev/null 2>&1' ||
		die "pacman -Qk disagrees with the disk after the rollback, which is a broken subvolume boundary"
	printf '  ok    pacman agrees with what is on disk\n'

	ssh "${SSH_OPTS[@]}" gary@127.0.0.1 'pacman -Q tailscale >/dev/null 2>&1' ||
		die "tailscale did not come back, so the rollback did not restore @"
	printf '  ok    the package that was removed is back\n'
}

# Reboot the guest and wait for it to answer again. Shared by the rollback
# phase and anything else that needs the machine to come back rather than to
# stop, unlike phase_recovery, which wants QEMU to exit.
reboot_guest() {
	local deadline="${1:-420}"

	local shutdown_log="$WORK_DIR/reboot-console.log"
	python3 "$SCRIPT_DIR/serial-log.py" \
		--socket "$WORK_DIR/serial.sock" --out "$shutdown_log" &
	local serial_logger=$!

	ssh "${SSH_OPTS[@]}" gary@127.0.0.1 'sudo systemctl reboot' || true

	local waited=0
	while kill -0 "$QEMU_PID" 2>/dev/null; do
		sleep 2
		waited=$((waited + 2))
		if [ "$waited" -ge "$deadline" ]; then
			kill "$serial_logger" 2>/dev/null || true
			printf '\nthe last thing the console said:\n' >&2
			tr -d '\033' <"$shutdown_log" 2>/dev/null | tail -n 25 >&2 || true
			return 1
		fi
	done
	kill "$serial_logger" 2>/dev/null || true
	wait "$serial_logger" 2>/dev/null || true
	QEMU_PID=""

	start_installed_vm

	python3 "$SCRIPT_DIR/serial-unlock.py" \
		--socket "$WORK_DIR/serial.sock" \
		--passphrase-file "$WORK_DIR/passphrase" \
		--log "$WORK_DIR/boot-console.log" || return 1

	# 150 attempts rather than 60. The machine this waits for has just been
	# through a full M4 run, a suspend, a wake and a rollback, and its first
	# boot on a fresh @ is not the quick one. Run 11 on 2026-09-02 reached a
	# login prompt on the serial console and then ran out of SSH attempts
	# while it was still starting services, so the phase reported a rollback
	# failure against a machine that was fine: booting the same disk by hand
	# afterwards answered SSH immediately, and re-running the phase alone
	# passed every check.
	local attempt
	for attempt in $(seq 1 150); do
		ssh "${SSH_OPTS[@]}" gary@127.0.0.1 true 2>/dev/null && return 0
		sleep 2
	done
	return 1
}

# plan.md M1 requires the recovery UKI to boot, not merely to exist. Assert it
# by booting it: anything less proves the file is present and nothing else.
phase_recovery() {
	log "Phase 6: booting the recovery UKI"

	# bootctl writes LoaderEntryOneShot into the UEFI variable store, which
	# lives in OVMF_VARS.fd and survives the restart below.
	ssh "${SSH_OPTS[@]}" gary@127.0.0.1 \
		'sudo bootctl set-oneshot archwork-recovery.efi' ||
		die "could not select the recovery entry, see bootctl list on the guest"

	# -no-reboot means the guest reboot stops QEMU rather than looping.
	ssh "${SSH_OPTS[@]}" gary@127.0.0.1 'sudo systemctl reboot' || true

	local waited=0
	while kill -0 "$QEMU_PID" 2>/dev/null; do
		sleep 2
		waited=$((waited + 2))
		[ "$waited" -ge 120 ] && die "the guest did not shut down for the recovery boot"
	done
	QEMU_PID=""

	start_installed_vm

	log "Waiting for the recovery UKI to reach a rescue shell"

	# Wait for a prompt someone could type into. Neither "Started Rescue Shell"
	# nor the "You are in rescue mode" banner qualifies: systemd prints both
	# before it hands over to sulogin, so both appear even when sulogin then
	# refuses to open a shell at all.
	#
	# sulogin refuses to open a shell when the root account is locked, which is
	# the state a fresh Arch install leaves it in. That would be a recovery path
	# that boots and then hands the operator nothing, so name it as a failure
	# rather than waiting out the timeout.
	python3 "$SCRIPT_DIR/serial-unlock.py" \
		--socket "$WORK_DIR/serial.sock" \
		--passphrase-file "$WORK_DIR/passphrase" \
		--expect "(Give root password|Press Enter for|Control-D to continue|root@|:~#)" \
		--fail-on "(account is locked|Cannot open access to console)" \
		--log "$WORK_DIR/recovery-console.log" ||
		die "the recovery UKI did not reach a rescue shell, see $WORK_DIR/recovery-console.log"
}

main() {
	parse_args "$@"
	check_prerequisites

	if [ -n "$RESUME_DIR" ]; then
		adopt_work_dir
		phase_boot
		run_phases

		log "Resumed phases passed: $PHASES"
		printf '\nThis was a resumed run against a machine an earlier run installed.\n'
		printf 'It is not evidence for docs/STATUS.yml. Only a clean rebuild is.\n\n'
		return 0
	fi

	prepare_work_dir
	extract_iso_boot_files
	start_http_server

	local run
	for run in $(seq 1 "$REPEAT"); do
		log "Run $run of $REPEAT"
		phase_install
		phase_boot
		phase_assert
		if [ "$RECONCILE" = true ]; then
			phase_reconcile
			# Only after reconciling: greetd is configured and started by the
			# session role, so a freshly installed machine has no greeter to
			# find. M1 deliberately stops at a text login.
			phase_greeter
			phase_session
			phase_desktop
			phase_portals
			if [ "$POWER" = true ]; then
				phase_power
			fi
			if [ "$ROLLBACK" = true ]; then
				phase_rollback
			fi
		fi
		phase_recovery

		kill_if_running "$QEMU_PID"
		QEMU_PID=""
		rm -f "$WORK_DIR/serial.sock" "$WORK_DIR/monitor.sock"

		# Tear down between runs, and only between runs.
		#
		# The UEFI variable store outlives the disk, so run 2 would otherwise
		# boot with run 1 boot entries pointing at a disk that no longer
		# exists. Each run gets a fresh firmware environment.
		#
		# After the last run both have to survive, or --keep keeps everything
		# except the two things --resume needs: the disk to boot and the boot
		# entry that finds it.
		if [ "$run" -lt "$REPEAT" ]; then
			rm -f "$WORK_DIR/disk.qcow2"
			cp "$OVMF_VARS" "$WORK_DIR/OVMF_VARS.fd"
			chmod u+w "$WORK_DIR/OVMF_VARS.fd"
		elif [ "$KEEP" = false ]; then
			rm -f "$WORK_DIR/disk.qcow2"
		fi
	done

	log "All $REPEAT run(s) passed"
	printf '\nRecord this in docs/STATUS.yml with the commit SHA:\n'
	printf '  %s\n\n' "$REPO_SHA"
}

main "$@"
