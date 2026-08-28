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
