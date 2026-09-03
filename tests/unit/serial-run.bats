#!/usr/bin/env bats
#
# Reading a command's exit status back off a serial console.
#
# The recovery UKI has no network and no sshd, so M5's "the rollback script on
# it works" can only be tested by typing into the rescue shell. Reading that
# output is the whole problem: a rescue console interleaves kernel messages
# with the command, echoes the command back before running it, and wraps lines
# wherever it likes.

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	export REPO_ROOT
	SCRIPT="$REPO_ROOT/tests/vm/serial-run.py"
	READER="$BATS_TEST_TMPDIR/read.py"
	cat >"$READER" <<-PY
		import importlib.util, sys
		spec = importlib.util.spec_from_file_location("sr", "$SCRIPT")
		m = importlib.util.module_from_spec(spec)
		spec.loader.exec_module(m)
		got = m.exit_status(open(sys.argv[1], "rb").read(), sys.argv[2])
		print("None" if got is None else got)
	PY
}

# Returns what the script makes of a transcript.
reads() {
	local transcript="$BATS_TEST_TMPDIR/transcript"
	printf '%s' "$1" >"$transcript"
	python3 "$READER" "$transcript" "${2:-ARCHWORK-END-abcd}"
}

@test "reads the status the guest reported" {
	run reads 'some output
ARCHWORK-END-abcd:0
'
	[ "$output" = "0" ]
}

@test "a non-zero status is not read as success" {
	run reads 'boom
ARCHWORK-END-abcd:1
'
	[ "$output" = "1" ]
}

@test "nothing yet reads as nothing, not as zero" {
	# The dangerous direction. A console that has not answered must not look
	# like a command that succeeded.
	run reads 'still booting
'
	[ "$output" = "None" ]
}

@test "the shell's echo of the command is not mistaken for the answer" {
	# The rescue shell prints the line containing the literal echo before it
	# prints the expansion. Taking the first match rather than the last would
	# read a previous command's status, or none at all.
	run reads '# echo ARCHWORK-BEGIN-11; archwork-rollback list; echo ARCHWORK-END-abcd:$?
ARCHWORK-BEGIN-11
no snapshots yet
ARCHWORK-END-abcd:3
'
	[ "$output" = "3" ]
}

@test "kernel messages interleaved with the output do not confuse it" {
	run reads '[   12.3] random: crng init done
ARCHWORK-BEGIN-22
root.20260903T0100
[   12.9] some other driver talking
ARCHWORK-END-abcd:0
'
	[ "$output" = "0" ]
}

@test "a marker from a different command is ignored" {
	run reads 'ARCHWORK-END-zzzz:0
'
	[ "$output" = "None" ]
}

@test "help exits clean and names the command flag" {
	run python3 "$SCRIPT" --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"--command"* ]]
}

@test "a socket that is not there is a failure, not a pass" {
	run python3 "$SCRIPT" --socket "$BATS_TEST_TMPDIR/nothing" --command true --timeout 2
	[ "$status" -eq 2 ]
}
