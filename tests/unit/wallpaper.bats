#!/usr/bin/env bats
#
# The keybinding wallpaper is a cheat sheet for the bindings in
# dotfiles/hypr/hyprland.lua, and a cheat sheet that disagrees with the machine
# is worse than no cheat sheet. The generator refuses to render when the two
# have drifted; this runs that check on every commit, so the drift is caught
# where it is cheap rather than on a desktop.
#
# --check renders nothing and needs only the standard library, which is why CI
# can run it without Pillow.

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	export REPO_ROOT
}

@test "every keybinding on the wallpaper matches one Hyprland actually binds" {
	run python3 "$REPO_ROOT/scripts/make-keybinding-wallpaper.py" --check
	[ "$status" -eq 0 ]
	[[ "$output" == *"every one captioned"* ]]
}

@test "a binding with no caption fails rather than being left off quietly" {
	# The failure that matters: somebody adds a keybinding and the wallpaper
	# silently does not mention it, so the sheet is quietly incomplete.
	local lua="$BATS_TEST_TMPDIR/hyprland.lua"
	cp "$REPO_ROOT/dotfiles/hypr/hyprland.lua" "$lua"
	printf 'hl.bind(mod .. " + Z", hl.dsp.window.close())\n' >>"$lua"

	local script="$BATS_TEST_TMPDIR/gen.py"
	sed "s|^BINDINGS = .*|BINDINGS = Path('$lua')|" \
		"$REPO_ROOT/scripts/make-keybinding-wallpaper.py" >"$script"

	run python3 "$script" --check
	[ "$status" -ne 0 ]
	[[ "$output" == *"SUPER + Z"* ]]
	[[ "$output" == *"no caption"* ]]
}

@test "the wallpaper the repository ships is a real PNG of the expected size" {
	local png="$REPO_ROOT/dotfiles/hypr/wallpaper-keybindings.png"
	[ -f "$png" ]
	# PNG signature, then the IHDR width and height as big-endian 32-bit.
	run python3 -c "
import struct, sys
data = open(sys.argv[1], 'rb').read(24)
assert data[:8] == b'\x89PNG\r\n\x1a\n', 'not a PNG'
print('%dx%d' % struct.unpack('>II', data[16:24]))
" "$png"
	[ "$status" -eq 0 ]
	[ "$output" = "2560x1440" ]
}
