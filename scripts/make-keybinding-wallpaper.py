#!/usr/bin/env python3
"""Render the keybinding wallpaper from the keybindings themselves.

The point of generating rather than drawing: a cheat sheet that is maintained
by hand is wrong the first time somebody edits a binding and forgets it, and a
wrong cheat sheet on the desktop is worse than none. So the bindings come out
of dotfiles/hypr/hyprland.lua, and this script refuses to render if a binding
there has no label here or a label here has no binding there. Adding a
keybinding without a caption is then a failure, not a silent omission.

The captions still have to be written by a person. Deriving "Close window"
from hl.dsp.window.close() would produce something readable by whoever wrote
the dispatcher and nobody else.

Usage: scripts/make-keybinding-wallpaper.py [--output PATH] [--size WxH]
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
BINDINGS = REPO / "dotfiles/hypr/hyprland.lua"

# Caption and group for every binding hyprland.lua defines. The key is the
# normalised binding, which is what read_bindings() produces.
LABELS: dict[str, tuple[str, str]] = {
    "SUPER + Return": ("Windows and apps", "Open a terminal"),
    "SUPER + D": ("Windows and apps", "Open the launcher"),
    "SUPER + Q": ("Windows and apps", "Close the focused window"),
    "SUPER + F": ("Windows and apps", "Fullscreen the focused window"),
    "SUPER + V": ("Windows and apps", "Float or tile the focused window"),
    "SUPER + C": ("Windows and apps", "Open the clipboard history picker"),
    "SUPER + left": ("Moving around", "Focus the window to the left"),
    "SUPER + right": ("Moving around", "Focus the window to the right"),
    "SUPER + up": ("Moving around", "Focus the window above"),
    "SUPER + down": ("Moving around", "Focus the window below"),
    "SUPER + 1…9": ("Moving around", "Go to workspace 1 to 9"),
    "SUPER + SHIFT + 1…9": ("Moving around", "Send the window to that workspace"),
    "SUPER + mouse:272": ("Mouse", "Hold and drag to move a window"),
    "SUPER + mouse:273": ("Mouse", "Hold and drag to resize a window"),
    "SUPER + L": ("Session", "Lock the screen"),
    "SUPER + SHIFT + E": ("Session", "Exit Hyprland and return to the greeter"),
    "Print": ("Session", "Screenshot to ~/Pictures/screenshots"),
}

# Order the groups appear in, rather than whatever dict iteration gives.
GROUPS = ["Windows and apps", "Moving around", "Mouse", "Session"]

# Not keybindings, so not in hyprland.lua and not checked against it. These are
# the commands that manage the power behaviour M4 configures, which is the part
# of the system with no UI at all until Quickshell arrives at M6.
COMMANDS = [
    ("archwork-inhibit 1h", "Stop the machine sleeping for an hour"),
    ("archwork-inhibit 2h | 4h", "The same, for longer"),
    ("archwork-inhibit indefinite", "Hold it off until you say otherwise"),
    ("archwork-inhibit --status", "Say whether anything is holding sleep off"),
    ("archwork-inhibit --cancel", "Let it sleep normally again"),
]

# What happens on its own, so that a dark screen is not mistaken for a fault.
TIMINGS = [
    ("5 minutes idle", "The display dims"),
    ("15 minutes idle", "The display switches off"),
    ("30 minutes idle", "The machine sleeps, unless inhibited"),
]

BG = (26, 30, 34)
PANEL = (35, 41, 46)
RULE = (58, 68, 75)
TEXT = (232, 237, 240)
MUTED = (138, 155, 165)
ACCENT = (128, 203, 196)
KEY_BG = (48, 56, 63)
KEY_TEXT = (222, 232, 236)


def read_bindings(path: Path) -> list[str]:
    """The bindings hyprland.lua actually defines, in file order.

    Only the first argument of each hl.bind matters here. Two of them are built
    inside a `for i = 1, 9` loop, so they are collapsed to a single row rather
    than printed nine times.
    """
    source = path.read_text()
    found: list[str] = []
    for raw in re.findall(r"hl\.bind\(\s*(.+?),\s*hl\.dsp", source, re.DOTALL):
        expression = " ".join(raw.split())
        if expression == 'mod .. " + " .. i':
            normalised = "SUPER + 1…9"
        elif expression == 'mod .. " + SHIFT + " .. i':
            normalised = "SUPER + SHIFT + 1…9"
        else:
            literal = re.fullmatch(r'mod \.\. "(.+)"', expression)
            if literal:
                normalised = "SUPER" + literal.group(1)
            elif re.fullmatch(r'"(.+)"', expression):
                normalised = expression.strip('"')
            else:
                sys.exit(f"cannot read the binding {expression!r} in {path}")
        if normalised not in found:
            found.append(normalised)
    return found


def font(names: list[str], size: int):
    """Resolve the first font fontconfig can actually give us.

    The workstation has JetBrains Mono and Inter; the machine this is generated
    on may have neither, so ask fontconfig rather than hardcoding a path.
    """
    from PIL import ImageFont  # noqa: PLC0415

    if shutil.which("fc-match"):
        for name in names:
            try:
                path = subprocess.run(
                    ["fc-match", "-f", "%{file}", name],
                    capture_output=True, text=True, check=True,
                ).stdout.strip()
            except subprocess.CalledProcessError:
                continue
            if path and Path(path).exists():
                return ImageFont.truetype(path, size)
    return ImageFont.load_default(size)


def cap_height(draw, key_font):
    """Height of a key cap, measured once so a row can centre against it.

    Measured from a string with an ascender and a descender rather than from
    the label, so that every cap in a row is the same height whatever letters
    it happens to contain.
    """
    _, top, _, bottom = draw.textbbox((0, 0), "Ayg", font=key_font)
    return bottom - top + 12


def draw_key(draw, x, y, text, key_font, height):
    """A key cap of the common height, returning the x it ends at."""
    left, top, right, bottom = draw.textbbox((0, 0), text, font=key_font)
    pad_x = 10
    w = right - left + pad_x * 2
    draw.rounded_rectangle([x, y, x + w, y + height], radius=6, fill=KEY_BG)
    draw.text((x + pad_x - left, y + (height - (bottom - top)) / 2 - top),
              text, font=key_font, fill=KEY_TEXT)
    return x + w


def draw_centred(draw, x, y, height, text, text_font, fill):
    """Text centred on the same vertical line as a key cap of that height."""
    _, top, _, bottom = draw.textbbox((0, 0), text, font=text_font)
    draw.text((x, y + (height - (bottom - top)) / 2 - top), text, font=text_font, fill=fill)


def draw_binding(draw, x, y, binding, caption, key_font, body_font, width):
    """One row: the chord as key caps, then what it does."""
    height = cap_height(draw, key_font)
    cursor = x
    for index, part in enumerate(p.strip() for p in binding.split("+")):
        if index:
            draw_centred(draw, cursor + 7, y, height, "+", body_font, MUTED)
            cursor += 24
        cursor = draw_key(draw, cursor, y, part, key_font, height)
    draw_centred(draw, x + width, y, height, caption, body_font, TEXT)


def render(bindings: list[str], size: tuple[int, int], output: Path) -> None:
    # Imported here rather than at the top so that --check, which is what CI
    # runs, needs nothing but the standard library.
    from PIL import Image, ImageDraw, ImageFont  # noqa: PLC0415

    width, height = size
    scale = width / 2560
    image = Image.new("RGB", size, BG)
    draw = ImageDraw.Draw(image)

    def px(value: float) -> int:
        return int(round(value * scale))

    title_font = font(["Inter:bold", "Noto Sans:bold", "DejaVu Sans:bold"], px(58))
    group_font = font(["Inter:bold", "Noto Sans:bold", "DejaVu Sans:bold"], px(26))
    body_font = font(["Inter", "Noto Sans", "DejaVu Sans"], px(23))
    key_font = font(["JetBrains Mono:bold", "JetBrainsMono Nerd Font:bold",
                     "DejaVu Sans Mono:bold"], px(20))
    small_font = font(["Inter", "Noto Sans", "DejaVu Sans"], px(19))

    margin = px(150)
    panel = [margin - px(50), px(150), width - margin + px(50), height - px(150)]
    draw.rounded_rectangle(panel, radius=px(18), fill=PANEL)

    x = margin
    y = px(215)
    draw.text((x, y), "ArchWork", font=title_font, fill=TEXT)
    y += px(78)
    draw.text((x, y), "The keys that drive this desktop", font=body_font, fill=ACCENT)
    y += px(60)

    column_width = (width - margin * 2 - px(80)) // 2
    caption_offset = px(330)
    left_x, right_x = x, x + column_width + px(80)
    left_y = right_y = y

    grouped: dict[str, list[str]] = {name: [] for name in GROUPS}
    for binding in bindings:
        grouped[LABELS[binding][0]].append(binding)

    # The two long groups on the left, the two short ones on the right, so the
    # columns finish at roughly the same depth.
    for group in ["Windows and apps", "Moving around"]:
        draw.text((left_x, left_y), group.upper(), font=group_font, fill=ACCENT)
        left_y += px(20)
        draw.line([left_x, left_y + px(20), left_x + column_width, left_y + px(20)], fill=RULE)
        left_y += px(42)
        for binding in grouped[group]:
            draw_binding(draw, left_x, left_y, binding, LABELS[binding][1],
                         key_font, body_font, caption_offset)
            left_y += px(52)
        left_y += px(34)

    for group in ["Mouse", "Session"]:
        draw.text((right_x, right_y), group.upper(), font=group_font, fill=ACCENT)
        right_y += px(20)
        draw.line([right_x, right_y + px(20), right_x + column_width, right_y + px(20)], fill=RULE)
        right_y += px(42)
        for binding in grouped[group]:
            draw_binding(draw, right_x, right_y, binding, LABELS[binding][1],
                         key_font, body_font, caption_offset)
            right_y += px(52)
        right_y += px(34)

    draw.text((right_x, right_y), "SLEEP AND POWER", font=group_font, fill=ACCENT)
    right_y += px(20)
    draw.line([right_x, right_y + px(20), right_x + column_width, right_y + px(20)], fill=RULE)
    right_y += px(42)
    command_height = cap_height(draw, key_font)
    for command, caption in COMMANDS:
        draw_centred(draw, right_x, right_y, command_height, command, key_font, KEY_TEXT)
        draw_centred(draw, right_x + caption_offset, right_y, command_height, caption,
                     body_font, TEXT)
        right_y += px(46)
    right_y += px(20)
    for when, what in TIMINGS:
        draw.text((right_x, right_y), when, font=small_font, fill=MUTED)
        draw.text((right_x + caption_offset, right_y), what, font=small_font, fill=MUTED)
        right_y += px(36)

    draw.text(
        (margin, height - px(210)),
        "Generated from dotfiles/hypr/hyprland.lua by "
        "scripts/make-keybinding-wallpaper.py. Edit the bindings, then run it again.",
        font=small_font, fill=MUTED,
    )

    output.parent.mkdir(parents=True, exist_ok=True)
    image.save(output, "PNG", optimize=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path,
                        default=REPO / "dotfiles/hypr/wallpaper-keybindings.png")
    parser.add_argument("--size", default="2560x1440")
    parser.add_argument("--check", action="store_true",
                        help="verify the captions match the bindings and stop, "
                             "without rendering. Needs no Pillow, so CI can run it")
    args = parser.parse_args()

    bindings = read_bindings(BINDINGS)

    missing = [b for b in bindings if b not in LABELS]
    extra = [b for b in LABELS if b not in bindings]
    if missing or extra:
        for binding in missing:
            print(f"{BINDINGS.name} binds {binding!r} and this script has no caption "
                  f"for it", file=sys.stderr)
        for binding in extra:
            print(f"this script captions {binding!r} and {BINDINGS.name} does not "
                  f"bind it", file=sys.stderr)
        sys.exit(1)

    if args.check:
        print(f"ok: {len(bindings)} bindings, every one captioned")
        return

    width, height = (int(n) for n in args.size.lower().split("x"))
    render(bindings, (width, height), args.output)
    print(f"wrote {args.output} ({width}x{height}), {len(bindings)} bindings")


if __name__ == "__main__":
    main()
