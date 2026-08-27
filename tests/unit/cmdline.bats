#!/usr/bin/env bats
#
# The kernel command line is the difference between a machine that boots and
# one that does not, and it is assembled by string substitution. That deserves
# tests.

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	export REPO_ROOT ARCHWORK_LIB_ONLY=1
	# shellcheck source=/dev/null
	source "$REPO_ROOT/scripts/archwork-install.sh"
}

UUID="deadbeef-0000-1111-2222-333344445555"

@test "desktop command line carries the LUKS UUID" {
	run render_cmdline "$REPO_ROOT/ansible/files/kernel-cmdline/desktop" "$UUID"
	[ "$status" -eq 0 ]
	[[ "$output" == *"rd.luks.name=$UUID=cryptroot"* ]]
}

@test "desktop command line never carries resume" {
	run render_cmdline "$REPO_ROOT/ansible/files/kernel-cmdline/desktop" "$UUID"
	[[ "$output" != *"resume"* ]]
}

@test "laptop command line carries resume and the offset" {
	run render_cmdline "$REPO_ROOT/ansible/files/kernel-cmdline/laptop" "$UUID" "271360"
	[ "$status" -eq 0 ]
	[[ "$output" == *"resume=/dev/mapper/cryptroot"* ]]
	[[ "$output" == *"resume_offset=271360"* ]]
}

@test "rootflags=subvol=@ survives token substitution" {
	# subvol=@ contains the same character the tokens are delimited with.
	# If the substitution is sloppy this is where it breaks.
	run render_cmdline "$REPO_ROOT/ansible/files/kernel-cmdline/desktop" "$UUID"
	[[ "$output" == *"rootflags=subvol=@"* ]]
}

@test "comments and blank lines are stripped" {
	run render_cmdline "$REPO_ROOT/ansible/files/kernel-cmdline/desktop" "$UUID"
	[[ "$output" != *"#"* ]]
	[[ "$output" != *$'\n'* ]]
}

@test "the result is a single line with no double spaces" {
	run render_cmdline "$REPO_ROOT/ansible/files/kernel-cmdline/laptop" "$UUID" "0"
	[ "${#lines[@]}" -eq 1 ]
	[[ "$output" != *"  "* ]]
	[[ "$output" != *" " ]]
}

@test "an unsubstituted token is fatal" {
	# The laptop template needs an offset. Omitting it must not produce a
	# command line with @RESUME_OFFSET@ still in it.
	run render_cmdline "$REPO_ROOT/ansible/files/kernel-cmdline/laptop" "$UUID"
	[ "$status" -ne 0 ]
	[[ "$output" == *"unsubstituted token"* ]]
}

@test "a template with an unknown token is fatal" {
	local template="$BATS_TEST_TMPDIR/bad"
	printf 'root=@SOMETHING_ELSE@\n' >"$template"
	run render_cmdline "$template" "$UUID" "0"
	[ "$status" -ne 0 ]
	[[ "$output" == *"unsubstituted token"* ]]
}

@test "profile templates exist for both profiles" {
	[ -r "$REPO_ROOT/ansible/files/kernel-cmdline/desktop" ]
	[ -r "$REPO_ROOT/ansible/files/kernel-cmdline/laptop" ]
}
