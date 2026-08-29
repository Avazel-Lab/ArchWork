#!/usr/bin/env bats
#
# The blank-screen verdict, proven by making it refuse.
#
# The M3 greeter check is the only assertion in this repository that looks at
# pixels, and its first threshold passed the real greeter by five hundredths
# of a percentage point. So the verdict gets tested against images with known
# content rather than trusted because it happened to pass once.
#
# No QEMU and no CAP_MKNOD: --analyse judges a file, so this runs anywhere.

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	export REPO_ROOT
	SCREENDUMP="$REPO_ROOT/tests/vm/screendump.py"
}

# Write a PPM of $3 by $4 where $2 pixels are white and the rest black.
#
# The heredoc is not indented: <<- strips leading tabs, which would flatten
# the Python block structure below along with the indentation.
make_ppm() {
	python3 - "$1" "$2" "${3:-320}" "${4:-200}" <<'PY'
import sys

path, drawn, width, height = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
pixels = bytearray(b"\x00" * (width * height * 3))

# Spread the drawn pixels out, because the verdict samples every fourth one
# and a solid run could fall entirely between samples.
for n in range(drawn):
    offset = (n * 4) * 3
    pixels[offset:offset + 3] = b"\xff\xff\xff"

with open(path, "wb") as handle:
    handle.write(b"P6\n%d %d\n255\n" % (width, height))
    handle.write(bytes(pixels))
PY
}

# Write a PPM whose background is $2,$3,$4 with $5 white pixels drawn on it.
# For the checks that have to tell one screen from another by its background.
make_ppm_on() {
	python3 - "$1" "$2" "$3" "$4" "$5" <<'PY'
import sys

path = sys.argv[1]
red, green, blue, drawn = (int(value) for value in sys.argv[2:6])
width, height = 320, 200
pixels = bytearray(bytes((red, green, blue)) * (width * height))

for n in range(drawn):
    offset = (n * 4) * 3
    pixels[offset:offset + 3] = b"\xff\xff\xff"

with open(path, "wb") as handle:
    handle.write(b"P6\n%d %d\n255\n" % (width, height))
    handle.write(bytes(pixels))
PY
}

@test "refuses a screen with nothing on it" {
	make_ppm "$BATS_TEST_TMPDIR/blank.ppm" 0
	run python3 "$SCREENDUMP" --analyse "$BATS_TEST_TMPDIR/blank.ppm"
	[ "$status" -ne 0 ]
	[[ "$output" == *"nothing is drawn"* ]]
}

@test "refuses a screen with almost nothing on it" {
	# Just under the threshold. A handful of stray pixels is not a greeter.
	make_ppm "$BATS_TEST_TMPDIR/sparse.ppm" 100
	run python3 "$SCREENDUMP" --analyse "$BATS_TEST_TMPDIR/sparse.ppm"
	[ "$status" -ne 0 ]
}

@test "accepts a screen with content on it" {
	make_ppm "$BATS_TEST_TMPDIR/drawn.ppm" 1400
	run python3 "$SCREENDUMP" --analyse "$BATS_TEST_TMPDIR/drawn.ppm"
	[ "$status" -eq 0 ]
	[[ "$output" == *"differ from the background"* ]]
}

@test "accepts the real greeter capture measured on 2026-08-28" {
	# 1407 differing pixels out of 256000 sampled, from a tuigreet screen.
	# The number this threshold was chosen against, kept so a later change to
	# either has to face it.
	make_ppm "$BATS_TEST_TMPDIR/greeter.ppm" 1407 1280 800
	run python3 "$SCREENDUMP" --analyse "$BATS_TEST_TMPDIR/greeter.ppm"
	[ "$status" -eq 0 ]
}

@test "refuses a file that is not a PPM" {
	printf 'not an image' >"$BATS_TEST_TMPDIR/nope.ppm"
	run python3 "$SCREENDUMP" --analyse "$BATS_TEST_TMPDIR/nope.ppm"
	[ "$status" -ne 0 ]
}

@test "refuses to capture without somewhere to capture from" {
	run python3 "$SCREENDUMP"
	[ "$status" -ne 0 ]
	[[ "$output" == *"--monitor and --output are required"* ]]
}

@test "waits for the lock screen rather than accepting the desktop" {
	# The failure this exists for: hyprlock's process appears well before its
	# lock surface does, and the desktop underneath is full of content, so
	# "something is drawn" said yes to the wrong screen and the password was
	# typed into a terminal.
	make_ppm_on "$BATS_TEST_TMPDIR/desktop.ppm" 0 0 0 1400
	run python3 "$SCREENDUMP" --analyse "$BATS_TEST_TMPDIR/desktop.ppm" --expect-dominant 28,28,28
	[ "$status" -ne 0 ]
	[[ "$output" == *"waiting for rgb(28, 28, 28)"* ]]
}

@test "accepts the screen whose background is the one asked for" {
	make_ppm_on "$BATS_TEST_TMPDIR/lock.ppm" 28 28 28 1400
	run python3 "$SCREENDUMP" --analyse "$BATS_TEST_TMPDIR/lock.ppm" --expect-dominant 28,28,28
	[ "$status" -eq 0 ]
}

@test "a screen of the right colour with nothing drawn on it is not the lock screen" {
	# hyprlock paints its background before it paints the clock and the input
	# field. Waiting for the colour alone would type into that gap.
	make_ppm_on "$BATS_TEST_TMPDIR/painting.ppm" 28 28 28 0
	run python3 "$SCREENDUMP" --analyse "$BATS_TEST_TMPDIR/painting.ppm" --expect-dominant 28,28,28
	[ "$status" -ne 0 ]
}

@test "refuses a colour it cannot parse" {
	make_ppm_on "$BATS_TEST_TMPDIR/lock.ppm" 28 28 28 1400
	run python3 "$SCREENDUMP" --analyse "$BATS_TEST_TMPDIR/lock.ppm" --expect-dominant "28,28"
	[ "$status" -ne 0 ]
}

@test "refuses a colour channel outside the range" {
	make_ppm_on "$BATS_TEST_TMPDIR/lock.ppm" 28 28 28 1400
	run python3 "$SCREENDUMP" --analyse "$BATS_TEST_TMPDIR/lock.ppm" --expect-dominant "28,28,300"
	[ "$status" -ne 0 ]
}
