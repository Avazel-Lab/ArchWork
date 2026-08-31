#!/usr/bin/env bash
#
# Assertion helpers for the VM checks. A library: nothing here runs on its own.
#
# These live apart from assert-m1.sh so that each is a named predicate rather
# than an inline shell expression, which keeps the assertion list readable and
# keeps quoting out of it.

CHECK_FAILURES=0

check() {
	local description="$1"
	shift

	if "$@" >/dev/null 2>&1; then
		printf '  ok    %s\n' "$description"
	else
		printf '  FAIL  %s\n' "$description"
		CHECK_FAILURES=$((CHECK_FAILURES + 1))
	fi
}

# For criteria stated as an absence, such as no @swap on the desktop.
check_not() {
	local description="$1"
	shift

	if "$@" >/dev/null 2>&1; then
		printf '  FAIL  %s\n' "$description"
		CHECK_FAILURES=$((CHECK_FAILURES + 1))
	else
		printf '  ok    %s\n' "$description"
	fi
}

has_subvolume() {
	btrfs subvolume list / | awk '{print $NF}' | grep -qx "$1"
}

mount_has_option() {
	findmnt --noheadings --output OPTIONS --target "$1" | grep -q "$2"
}

file_contains() {
	grep -q "$2" "$1"
}

file_matches() {
	grep -qE "$2" "$1"
}

swap_active_on() {
	swapon --show=NAME --noheadings | grep -q "$1"
}

root_is_luks2() {
	local slave
	for slave in /sys/class/block/*/slaves/*; do
		[ -e "$slave" ] || continue
		if cryptsetup luksDump "/dev/${slave##*/}" 2>/dev/null | grep -q 'Version:.*2'; then
			return 0
		fi
	done
	return 1
}

root_fstype_is() {
	findmnt --noheadings --output FSTYPE / | grep -qx "$1"
}

# The subvolume a path actually resolves to, so that /var/lib can be compared
# against /. findmnt reports it in brackets after the device.
subvolume_of() {
	findmnt --noheadings --output SOURCE --target "$1" | sed -n 's/.*\[\(.*\)\]/\1/p'
}

# /var/lib must roll back with @. If it sits on its own subvolume then a
# rollback of @ leaves /var/lib/pacman describing packages that are not on
# disk, and every later update fights the filesystem.
var_lib_rolls_back_with_root() {
	[ "$(subvolume_of /)" = "$(subvolume_of /var/lib)" ]
}

# A leftover @TOKEN@ in the command line means the installer substituted
# nothing there, which is an unbootable or silently broken system.
check_no_token() {
	! grep -qE '@[A-Z_]+@' "$1"
}

check_recovery_no_autodetect() {
	! grep -q autodetect /etc/mkinitcpio-recovery.conf
}

# D-016: the machine configures itself, so it must arrive able to do so.
repo_present() {
	test -d "/home/$1/src/ArchWork/.git"
}

repo_owned_by_user() {
	[ "$(stat -c '%U' "/home/$1/src/ArchWork")" = "$1" ]
}

# A clone keeps its source as origin, which on the target is a path on the ISO
# that no longer exists. It works perfectly until the first git pull.
repo_origin_is_upstream() {
	local origin
	origin="$(git -C "/home/$1/src/ArchWork" remote get-url origin 2>/dev/null)"
	case "$origin" in
	"" | /* | file:*) return 1 ;;
	*) return 0 ;;
	esac
}

command_installed() {
	command -v "$1" >/dev/null 2>&1
}

# --- The graphical session (M3, D-021) --------------------------------------
#
# These assertions arrive over SSH, which is outside the graphical session and
# inherits nothing from it: no runtime directory, no bus address, no Hyprland
# instance. Each has to be handed in, so the helpers below build that
# environment rather than every check repeating it.

session_runtime_dir() {
	printf '/run/user/%s' "$(id -u "$1")"
}

# Hyprland names its socket directory after the instance signature. Newest
# first, so a directory left by an earlier crashed instance does not win.
hypr_signature() {
	local dir
	dir="$(session_runtime_dir "$1")/hypr"
	[ -d "$dir" ] || return 1

	find "$dir" -mindepth 1 -maxdepth 1 -printf '%T@ %f\n' 2>/dev/null |
		sort -rn | head -1 | cut -d' ' -f2- | grep .
}

wayland_display() {
	local runtime socket
	runtime="$(session_runtime_dir "$1")"
	for socket in "$runtime"/wayland-*; do
		case "$socket" in
		*.lock) continue ;;
		esac
		[ -S "$socket" ] || continue
		basename "$socket"
		return 0
	done
	return 1
}

as_user() {
	local user="$1" runtime
	shift
	runtime="$(session_runtime_dir "$user")"

	runuser -u "$user" -- env \
		XDG_RUNTIME_DIR="$runtime" \
		DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime/bus" \
		"$@"
}

# For anything that has to talk to the compositor: hyprctl finds its instance
# through the signature, and Wayland clients through the display name.
as_user_in_session() {
	local user="$1" signature display
	shift
	signature="$(hypr_signature "$user")" || return 1
	display="$(wayland_display "$user")" || return 1

	as_user "$user" env \
		HYPRLAND_INSTANCE_SIGNATURE="$signature" \
		WAYLAND_DISPLAY="$display" \
		"$@"
}

user_process_running() {
	pgrep -u "$1" -x "$2" >/dev/null 2>&1
}

# A session logind opened, rather than a process that happens to be running.
# Only the former means a password went through PAM.
graphical_session_open() {
	local user="$1" id
	while read -r id; do
		[ -n "$id" ] || continue
		[ "$(loginctl show-session "$id" --property=Name --value)" = "$user" ] || continue
		[ "$(loginctl show-session "$id" --property=Type --value)" = "wayland" ] || continue
		[ "$(loginctl show-session "$id" --property=Active --value)" = "yes" ] || continue
		return 0
	done < <(loginctl list-sessions --no-legend | awk '{print $1}')
	return 1
}

session_on_seat() {
	local user="$1" seat="$2" id
	while read -r id; do
		[ -n "$id" ] || continue
		[ "$(loginctl show-session "$id" --property=Name --value)" = "$user" ] || continue
		[ "$(loginctl show-session "$id" --property=Seat --value)" = "$seat" ] || continue
		return 0
	done < <(loginctl list-sessions --no-legend | awk '{print $1}')
	return 1
}

compositor_answers() {
	as_user_in_session "$1" hyprctl version >/dev/null
}

wayland_socket_present() {
	wayland_display "$1" >/dev/null
}

# Reach the service the way an application does, which means activating it.
#
# This asked GetNameOwner until 2026-08-29 and failed a run that was working:
# org.freedesktop.secrets is D-Bus activatable, GetNameOwner does not activate
# anything, and nothing had yet asked for the Secret Service at that point in
# the run. The name had no owner and the machine was fine. A method call on
# the name starts it, which is what every real client does and what the check
# next to this one was accidentally relying on.
secret_service_present() {
	as_user "$1" timeout 20 gdbus call --session \
		--dest org.freedesktop.secrets \
		--object-path /org/freedesktop/secrets \
		--method org.freedesktop.DBus.Peer.Ping >/dev/null 2>&1
}

# D-012: the password typed at greetd unlocked the keyring through PAM. A
# keyring that exists but is locked would prompt at first use, which is the
# second prompt D-004 accepted a login password in order to avoid, so Locked
# being false is the entire criterion.
keyring_unlocked() {
	local reply
	reply="$(as_user "$1" timeout 15 gdbus call --session \
		--dest org.freedesktop.secrets \
		--object-path /org/freedesktop/secrets/collection/login \
		--method org.freedesktop.DBus.Properties.Get \
		org.freedesktop.Secret.Collection Locked 2>/dev/null)" || return 1

	case "$reply" in
	*false*) return 0 ;;
	*) return 1 ;;
	esac
}

# Weaker than the M3 criterion, which asks for a file picker from a GTK and a
# Qt application. This says the portal is reachable and activates, which is
# what has to be true before any picker can open.
portal_answers() {
	as_user "$1" timeout 20 gdbus call --session \
		--dest org.freedesktop.portal.Desktop \
		--object-path /org/freedesktop/portal/desktop \
		--method org.freedesktop.DBus.Peer.Ping >/dev/null 2>&1
}

# The M3 criterion is a file picker, and a picker is a window rather than a
# bus reply, so this asks the compositor what is on screen. Two things make it
# a real answer: the window must not belong to the application that asked for
# it, which is what separates a portal dialog from the application's own, and
# the match is deliberately loose.
#
# Loose because which class and title xdg-desktop-portal-gtk gives its chooser
# is not something this repository can establish by reading its own code, and
# a run that fails against a guessed string teaches nothing. list_clients
# prints what was actually there when this says no, so one run settles it.
file_picker_open() {
	as_user_in_session "$1" hyprctl -j clients 2>/dev/null |
		jq -e --arg app "$2" 'any(.[];
			.class != $app and
			((.class + " " + .title) | ascii_downcase
				| test("portal|open|choose|select|import|file")))' >/dev/null 2>&1
}

# Diagnostic rather than assertion. Prints every window the compositor has, so
# a failed picker check names what was on screen instead of leaving the next
# run to guess.
list_clients() {
	as_user_in_session "$1" hyprctl -j clients 2>/dev/null |
		jq -r '.[] | "class=\(.class) title=\(.title)"'
}

screenshot_works() {
	local target="/tmp/archwork-m3-screenshot.png"
	rm -f "$target"
	as_user_in_session "$1" grim "$target" >/dev/null 2>&1 || return 1
	[ -s "$target" ]
}

# --- Service state (D-025) --------------------------------------------------
#
# Stated as positives so that assert-m2.sh can wrap them in check_not and read
# as the absence it is asserting. A negative predicate inside check_not reads
# as a double negative and gets misread the first time someone edits it.

unit_is_enabled() {
	[ "$(systemctl is-enabled "$1" 2>/dev/null)" = enabled ]
}

unit_is_active() {
	systemctl is-active --quiet "$1"
}

user_not_in_group() {
	! id -nG "$1" 2>/dev/null | tr ' ' '\n' | grep -qx "$2"
}

# --- Tailscale, and living alongside NetworkManager (D-002, D-019, D-022) ---
#
# The machine arrives with tailscaled running and logged out, because the auth
# key that would sign it in is one of the secrets D-006 has yet to bring. So
# what can honestly be asserted here is that the daemon is up and that it has
# taken nothing over from NetworkManager. Split DNS and MagicDNS against a real
# tailnet cannot be tested until that key exists, and nothing below pretends
# otherwise.

# Answers whether or not the machine is signed in, which is the point: a
# daemon that is running but not reachable would pass a systemctl check and
# fail the person trying to use it.
tailscale_daemon_answers() {
	tailscale status --json 2>/dev/null | grep -q '"BackendState"'
}

tailscale_interface_present() {
	ip link show tailscale0 >/dev/null 2>&1
}

# The coexistence criterion, in the form it can take while logged out:
# Tailscale has not taken the default route from the interface NetworkManager
# manages. A logged-out daemon that had would have broken the machine's
# network to prove a point.
default_route_not_via() {
	! ip route show default | grep -q "$1"
}

name_resolution_works() {
	getent hosts "$1" >/dev/null 2>&1
}

# D-002 masks systemd-resolved, and D-019 flagged that Tailscale's split DNS
# works best through it. That is a real tension rather than a theoretical one,
# so this asserts the mask is still in place and that names still resolve
# without it. If signing in later breaks resolution, this is the pair of
# checks that will say so.
unit_is_masked() {
	[ "$(systemctl is-enabled "$1" 2>/dev/null)" = masked ]
}

# A window the compositor has, rather than a process that started. A terminal
# that launched and then died leaves the process check happy and the screen
# empty, which is the failure worth catching.
client_class_present() {
	as_user_in_session "$1" hyprctl -j clients 2>/dev/null |
		jq -e --arg class "$2" 'any(.[]; .class == $class)' >/dev/null 2>&1
}

# A window with a particular title, which is how the harness waits for an
# application to be ready rather than merely mapped.
#
# The case it exists for: kitty's shell integration sets the window title to
# the working directory once bash reaches a prompt. Press the close binding
# before that and kitty counts bash as a running command and puts up "Are you
# sure you want to close this OS Window?" instead of closing, which is correct
# behaviour on kitty's part and a race on the harness's. Seen on 2026-08-29,
# having passed on the run before by timing alone.
client_title_present() {
	as_user_in_session "$1" hyprctl -j clients 2>/dev/null |
		jq -e --arg class "$2" --arg title "$3" \
			'any(.[]; .class == $class and .title == $title)' >/dev/null 2>&1
}

client_class_absent() {
	! client_class_present "$1" "$2"
}

process_absent() {
	! user_process_running "$1" "$2"
}

user_unit_active() {
	as_user "$1" systemctl --user is-active --quiet "$2"
}

# --- Power and sleep (M4, D-028) --------------------------------------------
#
# M4's criteria are timings, so most of what follows measures when something
# happened rather than whether it did. A check that only waited long enough
# and then looked would pass on a machine whose display switched off after
# four minutes or forty, which is why each observation records its elapsed
# time and the caller asserts a window around the number the configuration
# claims.

CHECK_SKIPS=0

# For a criterion this machine cannot observe, as opposed to one that passed.
# Counted separately and reported separately: a skip folded into a pass is how
# a run comes to look like proof of something nobody measured.
skip() {
	printf '  skip  %s\n        %s\n' "$1" "$2"
	CHECK_SKIPS=$((CHECK_SKIPS + 1))
}

# One listener block in hypridle.conf, by its timeout and the command it runs.
#
# The behavioural checks below cannot tell 900 seconds configured from 900
# seconds by luck of the polling interval, and this cannot tell a listener
# that is present from one that fires. Neither is worth much alone.
hypridle_listener_has() {
	local conf="$1" want="$2" needle="$3"
	awk -v want="$want" -v needle="$needle" '
		/^listener[[:space:]]*\{/ { timeout=""; hascmd=0; next }
		/^\}/ {
			if (timeout == want && hascmd) { ok = 1 }
			timeout=""; hascmd=0; next
		}
		/^[[:space:]]*timeout[[:space:]]*=/ {
			value=$0
			gsub(/[^0-9]/, "", value)
			timeout=value
			next
		}
		index($0, needle) { hascmd=1 }
		END { exit ok ? 0 : 1 }
	' "$conf"
}

# The daemon reads the file in the repository clone, not a copy that has
# drifted from it. The dotfiles role links the whole hypr directory, so the
# file itself is not a symlink and `test -L` on it is false: where it resolves
# to is the question. Getting that wrong is how a machine ends up running
# timings nobody can see in `git status`.
# Like BACKLIGHT_ROOT: a variable so the tests can call this function itself
# rather than a copy of its logic. On a machine it is always /home.
HOME_ROOT="${HOME_ROOT:-/home}"

config_is_repo_dotfile() {
	local path="$1" user="$2"
	[ "$(readlink -f "$path")" = "$HOME_ROOT/$user/src/ArchWork/dotfiles/hypr/$(basename "$path")" ]
}

# The lock the M4 criterion names, read the way the criterion states it.
sleep_inhibitor_held() {
	systemd-inhibit --list 2>/dev/null |
		awk '$0 ~ /sleep/ && $0 ~ /block/ { found=1 } END { exit found ? 0 : 1 }'
}

sleep_inhibitor_absent() {
	! sleep_inhibitor_held
}

# The inhibitor is the one archwork-inhibit holds, not some other process's.
sleep_inhibitor_is_ours() {
	systemd-inhibit --list 2>/dev/null | grep -q archwork-inhibit
}

# Every monitor, not any monitor: a second display still lit is the criterion
# failing on the machine profile that has two of them.
all_monitors_dpms() {
	local user="$1" want="$2" monitors
	monitors="$(as_user_in_session "$user" hyprctl -j monitors 2>/dev/null)" || return 1
	printf '%s' "$monitors" |
		jq -e --argjson want "$want" 'length > 0 and all(.[]; .dpmsStatus == $want)' >/dev/null 2>&1
}

# Poll a predicate and print how many seconds it took to become true, counted
# from the epoch second the caller passes rather than from when polling
# started. The caller owns the clock: idle time runs from the keystroke the
# harness sent, which happened before this script was even copied over.
#
# Prints the elapsed seconds on success. Fails after the deadline.
seconds_until() {
	local since="$1" deadline="$2"
	shift 2

	local now
	while :; do
		now="$(date +%s)"
		if "$@" >/dev/null 2>&1; then
			printf '%d' "$((now - since))"
			return 0
		fi
		if [ "$((now - since))" -ge "$deadline" ]; then
			return 1
		fi
		sleep 5
	done
}

# Assert an observed time against the timing the configuration claims. The
# lower bound is the point of it: firing early is as wrong as never firing,
# and only the lower bound catches a listener that fires on the wrong clock.
within_window() {
	local observed="$1" lower="$2" upper="$3"
	[ "$observed" -ge "$lower" ] && [ "$observed" -le "$upper" ]
}

# logind's own record of a sleep, whatever wording the running version uses.
suspend_logged_since() {
	journalctl --since "@$1" -u systemd-logind --no-pager 2>/dev/null |
		grep -qE 'Suspending system|Entering sleep state|Performing sleep operation'
}

no_suspend_logged_since() {
	! suspend_logged_since "$1"
}

# A backlight to dim. The desktop's external monitors have none and the VM has
# none, so the dim criterion is observable on the laptop panel and nowhere
# else. D-028 accepted that brightnessctl no-ops there.
# The path is a variable so the tests can point it at a directory they made.
# On a machine it is always the real one.
BACKLIGHT_ROOT="${BACKLIGHT_ROOT:-/sys/class/backlight}"

backlight_present() {
	compgen -G "$BACKLIGHT_ROOT/*" >/dev/null
}

backlight_at_or_below() {
	local percent="$1" device current max
	for device in "$BACKLIGHT_ROOT"/*; do
		[ -d "$device" ] || continue
		current="$(cat "$device/brightness")"
		max="$(cat "$device/max_brightness")"
		[ "$max" -gt 0 ] || return 1
		[ "$((current * 100 / max))" -le "$percent" ] || return 1
		return 0
	done
	return 1
}
