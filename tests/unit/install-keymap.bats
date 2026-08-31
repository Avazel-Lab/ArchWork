#!/usr/bin/env bats
#
# The installer puts the console on the layout the installed system boots
# with, before it asks for a LUKS passphrase.
#
# D-017 records why: the ISO is US, the installed system is UK, and a
# passphrase set on one and typed back on the other is an encrypted disk
# nobody can open. The failure is silent at the time and total at the first
# reboot, so these tests assert the call happens and that a missing or
# failing loadkeys stops the install rather than warning past it.

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	export REPO_ROOT
	INSTALLER="$REPO_ROOT/scripts/archwork-install.sh"
}

# The function reads KEYMAP and DRY_RUN from the script's scope and calls
# run_cmd, log and die, so it is pulled out and given stubs for those.
load_keymap_function() {
	KEYMAP="${1:-uk}"
	DRY_RUN="${2:-false}"
	log() { :; }
	# The real die exits. A stub that returned would let these tests pass
	# while the installer carried on past a failure it should stop at.
	die() {
		printf 'died: %s\n' "$1"
		exit 1
	}
	run_cmd() {
		printf 'ran: %s\n' "$*"
	}
	eval "$(sed -n '/^set_console_keymap()/,/^}/p' "$INSTALLER")"
}

@test "loads the keymap the installed system will use" {
	run bash -c "
		$(declare -f load_keymap_function)
		INSTALLER='$INSTALLER'
		load_keymap_function uk false
		set_console_keymap
	"
	[ "$status" -eq 0 ]
	[[ "$output" == *"ran: loadkeys uk"* ]]
}

@test "refuses to continue when loadkeys is not installed" {
	# PATH emptied so command -v finds nothing. The install must stop here,
	# before the passphrase, rather than carry on with the ISO layout.
	run bash -c "
		$(declare -f load_keymap_function)
		INSTALLER='$INSTALLER'
		load_keymap_function uk false
		PATH=''
		set_console_keymap
	"
	[ "$status" -ne 0 ]
	[[ "$output" == *"loadkeys is not present"* ]]
	[[ "$output" != *"ran: loadkeys"* ]]
}

@test "refuses to continue when loadkeys fails" {
	run bash -c "
		$(declare -f load_keymap_function)
		INSTALLER='$INSTALLER'
		load_keymap_function uk false
		run_cmd() { return 1; }
		set_console_keymap
	"
	[ "$status" -ne 0 ]
	[[ "$output" == *"loadkeys uk failed"* ]]
}

@test "a dry run rehearses it without needing loadkeys on the machine" {
	run bash -c "
		$(declare -f load_keymap_function)
		INSTALLER='$INSTALLER'
		load_keymap_function uk true
		PATH=''
		set_console_keymap
	"
	[ "$status" -eq 0 ]
	[[ "$output" == *"ran: loadkeys uk"* ]]
}

@test "it runs before the passphrase is set" {
	# Ordering is the whole point: after encrypt_root it would be useless.
	local order
	order="$(sed -n '/^main()/,/^}/p' "$INSTALLER" | grep -nE "^[[:space:]]*(set_console_keymap|encrypt_root)$")"
	[[ "$order" == *"set_console_keymap"* ]]
	[[ "$order" == *"encrypt_root"* ]]
	local keymap_line encrypt_line
	keymap_line="$(printf '%s\n' "$order" | grep set_console_keymap | cut -d: -f1)"
	encrypt_line="$(printf '%s\n' "$order" | grep encrypt_root | cut -d: -f1)"
	[ "$keymap_line" -lt "$encrypt_line" ]
}
