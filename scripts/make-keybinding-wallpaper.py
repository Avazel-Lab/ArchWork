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

# Desktop apps, by category, rendered only where `pacman -Q` says the package
# is actually here. This is deliberately not applications.md: that document
# is the aspirational baseline, most of which is not installed on any one
# machine yet, and a wallpaper showing packages that are not there would be
# exactly the kind of drift this generator otherwise refuses to have. The
# package name is what gets checked; the second string is what gets shown.
APPS: dict[str, list[tuple[str, str]]] = {
    "Browsers": [
        ("zen-browser-bin", "Zen Browser"),
        ("ungoogled-chromium-bin", "Ungoogled Chromium"),
    ],
    "Development": [
        ("visual-studio-code-bin", "VS Code"),
        ("bruno-bin", "Bruno"),
    ],
    "Documents": [
        ("libreoffice-fresh", "LibreOffice"),
        ("okular", "Okular"),
        ("pdfarranger", "PDF Arranger"),
    ],
    "Notes and passwords": [
        ("joplin-bin", "Joplin"),
        ("nordpass-bin", "NordPass"),
        ("bitwarden", "Bitwarden"),
    ],
    "Media": [
        ("vlc", "VLC"),
        ("handbrake", "HandBrake"),
        ("tinymediamanager-bin", "tinyMediaManager"),
    ],
    "Images and archives": [
        ("gwenview", "Gwenview"),
        ("pinta", "Pinta"),
        ("peazip", "PeaZip"),
    ],
    "Communication": [
        ("discord", "Discord"),
    ],
    "Files": [
        ("fsearch", "FSearch"),
        ("krusader", "Krusader"),
        ("yazi", "Yazi"),
    ],
    "Torrenting": [
        ("qbittorrent", "qBittorrent"),
    ],
    "Remote and virtual machines": [
        ("remmina", "Remmina"),
        ("virt-manager", "virt-manager"),
    ],
    "Gaming": [
        ("steam", "Steam"),
        ("lutris", "Lutris"),
        ("heroic-games-launcher-bin", "Heroic"),
        ("protonup-qt", "ProtonUp-Qt"),
    ],
    "System": [
        ("mission-center", "Mission Center"),
        ("gparted", "GParted"),
        ("gnome-disk-utility", "GNOME Disks"),
        ("baobab", "Baobab"),
    ],
    "Peripherals": [
        ("opendeck-bin", "OpenDeck"),
        ("solaar", "Solaar"),
        ("kdeconnect", "KDE Connect"),
    ],
    "AI": [
        ("lmstudio-bin", "LM Studio"),
    ],
}

# Order categories are packed in. Packing itself is by shortest-column-first
# (pack_columns below), not this order, but a fixed order keeps a rebuild
# from shuffling categories between two runs with the same packages installed.
APP_CATEGORY_ORDER = list(APPS)

# Commands worth keeping in reach: checking something, not changing it.
# Curated, not dumped from ~/.bash_history: the history that prompted this
# is mostly cd, ls and a night of NVIDIA debugging, which is not a cheat
# sheet anybody wants on their wall. Kept to what actually works on this
# machine today, checked against it rather than assumed: no archwork-health,
# archwork-update or archwork-inhibit here, because M5's snapshots role has
# not reconciled onto hmlxdesktop02 yet and none of the three exist here.
GENERAL_COMMANDS: list[tuple[str, str]] = [
    ("hyprctl reload", "Apply a Hyprland config edit without restarting"),
    ("pacman -Q <pkg>", "Check what version of something is installed"),
    ("pacman -Syu", "Update the whole system"),
    ("systemctl --user status <unit>", "Check a session service, e.g. hypridle"),
    ("journalctl --user -u <unit>", "That service's own log"),
    ("journalctl -b", "Everything logged since this boot"),
    ("cliphist list", "See clipboard history (Super+C picks from it)"),
    ("make check", "Run this repository's own lint and tests"),
    ("uname -r", "The kernel actually running, not just installed"),
]

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
KEY_TEXT = (222, 232, 236)


def installed_packages() -> set[str]:
    """Everything `pacman -Q` says is on this machine, or an empty set.

    Absent rather than fatal when pacman is not there: rendering on a
    non-Arch machine, or CI, should not need it, and an empty result just
    means every app category comes out empty rather than the run failing.
    """
    if not shutil.which("pacman"):
        return set()
    result = subprocess.run(["pacman", "-Qq"], capture_output=True, text=True, check=False)
    if result.returncode != 0:
        return set()
    return set(result.stdout.split())


def pack_columns(items: list[tuple[str, int]], n: int) -> list[list[str]]:
    """Greedy shortest-column-first packing.

    Each item is (label, estimated_height). Not optimal bin-packing, which
    this does not need: it only has to keep n columns roughly level, not
    solve it exactly.
    """
    columns: list[list[str]] = [[] for _ in range(n)]
    heights = [0] * n
    for label, height in items:
        shortest = heights.index(min(heights))
        columns[shortest].append(label)
        heights[shortest] += height
    return columns


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


def render(bindings: list[str], size: tuple[int, int], output: Path) -> None:
    # Imported here rather than at the top so that --check, which is what CI
    # runs, needs nothing but the standard library.
    from PIL import Image, ImageDraw  # noqa: PLC0415

    width, height = size
    scale = width / 2560
    image = Image.new("RGB", size, BG)
    draw = ImageDraw.Draw(image)

    def px(value: float) -> int:
        return int(round(value * scale))

    title_font = font(["Inter:bold", "Noto Sans:bold", "DejaVu Sans:bold"], px(58))
    group_font = font(["Inter:bold", "Noto Sans:bold", "DejaVu Sans:bold"], px(24))
    body_font = font(["Inter", "Noto Sans", "DejaVu Sans"], px(22))
    small_font = font(["Inter", "Noto Sans", "DejaVu Sans"], px(18))
    tiny_font = font(["Inter", "Noto Sans", "DejaVu Sans"], px(15))
    key_font = font(["JetBrains Mono:bold", "JetBrainsMono Nerd Font:bold",
                     "DejaVu Sans Mono:bold"], px(18))
    tiny_key_font = font(["JetBrains Mono:bold", "JetBrainsMono Nerd Font:bold",
                          "DejaVu Sans Mono:bold"], px(14))

    margin = px(150)
    panel = [margin - px(50), px(150), width - margin + px(50), height - px(150)]
    draw.rounded_rectangle(panel, radius=px(18), fill=PANEL)

    x = margin
    y = px(215)
    draw.text((x, y), "ArchWork", font=title_font, fill=TEXT)
    y += px(78)
    draw.text((x, y), "The apps, the commands, and the keys underneath",
              font=body_font, fill=ACCENT)
    y += px(60)
    top = y
    bottom = height - px(210)

    content_width = width - margin * 2
    gap = px(50)
    apps_width = int(content_width * 0.55)
    commands_width = int(content_width * 0.26)
    shortcuts_x = margin + apps_width + gap + commands_width + gap
    commands_x = margin + apps_width + gap

    def category_height(n_apps: int) -> int:
        return px(46) + n_apps * px(30) + px(16)

    def draw_category(cx: int, cy: int, name: str, apps: list[str], cwidth: int) -> int:
        draw.text((cx, cy), name.upper(), font=small_font, fill=ACCENT)
        cy += px(16)
        draw.line([cx, cy + px(14), cx + cwidth, cy + px(14)], fill=RULE)
        cy += px(30)
        for app in apps:
            draw.text((cx, cy), app, font=body_font, fill=TEXT)
            cy += px(30)
        return cy + px(16)

    # DESKTOP APPS: only what pacman actually says is here (installed_packages
    # below), packed into three columns by shortest-column-first so a category
    # with one app does not leave as much white space as one with five. Three,
    # not two: fourteen categories at this row height do not fit two columns
    # in the space available, measured by actually rendering it and looking,
    # not by trusting the arithmetic in advance.
    present = installed_packages()
    apps_by_category = {
        name: [label for pkg, label in pkgs if pkg in present]
        for name, pkgs in ((n, APPS[n]) for n in APP_CATEGORY_ORDER)
    }
    apps_by_category = {name: apps for name, apps in apps_by_category.items() if apps}

    draw.text((margin, top), "DESKTOP APPS", font=group_font, fill=ACCENT)
    apps_top = top + px(46)
    sub_gap = px(34)
    n_sub = 3
    sub_width = (apps_width - sub_gap * (n_sub - 1)) // n_sub
    sub_x = [margin + i * (sub_width + sub_gap) for i in range(n_sub)]

    packed = pack_columns(
        [(name, category_height(len(apps))) for name, apps in apps_by_category.items()],
        n_sub,
    )
    sub_y = [apps_top] * n_sub
    for col, names in enumerate(packed):
        for name in names:
            sub_y[col] = draw_category(sub_x[col], sub_y[col], name,
                                        apps_by_category[name], sub_width)

    # USEFUL COMMANDS: a narrower column, so command and caption stack rather
    # than sit side by side, which is what broke first when this was tried at
    # the commands column's actual width rather than the wide layout the
    # keybindings used.
    draw.text((commands_x, top), "USEFUL COMMANDS", font=group_font, fill=ACCENT)
    cy = top + px(40)
    for command, caption in GENERAL_COMMANDS:
        draw.text((commands_x, cy), command, font=key_font, fill=KEY_TEXT)
        cy += px(22)
        draw.text((commands_x, cy), caption, font=small_font, fill=MUTED)
        cy += px(26)

    cy += px(14)
    draw.text((commands_x, cy), "SLEEP AND POWER", font=group_font, fill=ACCENT)
    cy += px(40)
    for command, caption in COMMANDS:
        draw.text((commands_x, cy), command, font=key_font, fill=KEY_TEXT)
        cy += px(22)
        draw.text((commands_x, cy), caption, font=small_font, fill=MUTED)
        cy += px(26)
    cy += px(10)
    for when, what in TIMINGS:
        draw.text((commands_x, cy), f"{when}: {what}", font=tiny_font, fill=MUTED)
        cy += px(22)

    # SHORTCUTS: tucked into the narrowest column, no key-cap graphics, no
    # group headings. Still every binding hyprland.lua actually defines, in
    # its own order, still refusing to render if one goes uncaptioned; only
    # how much room it is given on the page has changed.
    draw.text((shortcuts_x, top), "SHORTCUTS", font=group_font, fill=ACCENT)
    sy = top + px(40)
    for binding in bindings:
        draw.text((shortcuts_x, sy), binding, font=tiny_key_font, fill=KEY_TEXT)
        sy += px(20)
        draw.text((shortcuts_x, sy), LABELS[binding][1], font=tiny_font, fill=MUTED)
        sy += px(26)

    draw.text(
        (margin, bottom),
        "Generated by scripts/make-keybinding-wallpaper.py from hyprland.lua's bindings "
        "and this machine's actual packages. Edit either, then run it again.",
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
