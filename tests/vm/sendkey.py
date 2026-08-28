#!/usr/bin/env python3
"""Type at the guest's keyboard through the QEMU monitor.

D-021: the greetd password must go through the real PAM stack at the real
greeter, so something has to type it, and nothing inside the guest may be
involved. QEMU's sendkey puts scancodes on the emulated PS/2 keyboard, which
works before any session exists and needs nothing installed on the machine
under test.

sendkey names keys by position, not by the character they produce: the guest's
keymap decides that. The installer sets KEYMAP=uk, so a key whose meaning
differs between uk and us would type one character here and another on a
machine set up differently. Rather than encode one layout and silently type
the wrong password on the other, this refuses any character whose key does not
mean the same thing under both. Letters, digits, space and a handful of
punctuation are the safe set, which is enough to type a password and a user
name.
"""

from __future__ import annotations

import argparse
import sys
import time

from qemu_monitor import Monitor

# Characters that sit on the same key, with the same meaning, under both the
# uk and us layouts. `@`, `"`, `#` and `~` are deliberately absent: each moves
# between the two, so any of them would be typed as a different character
# depending on which keymap the guest ended up with.
UNSHIFTED = {
    " ": "spc",
    "-": "minus",
    "=": "equal",
    ",": "comma",
    ".": "dot",
    "/": "slash",
    ";": "semicolon",
    "'": "apostrophe",
    "[": "bracket_left",
    "]": "bracket_right",
}

SHIFTED = {
    "_": "minus",
    "+": "equal",
    "<": "comma",
    ">": "dot",
    "?": "slash",
    ":": "semicolon",
    "{": "bracket_left",
    "}": "bracket_right",
}

NAMED_KEYS = {"ret", "tab", "esc", "spc", "backspace", "delete", "up", "down", "left", "right"}


def key_for(char: str) -> str:
    """The QEMU sendkey argument that types one character."""
    if char.islower() and char.isalpha() and char.isascii():
        return char
    if char.isupper() and char.isalpha() and char.isascii():
        return f"shift-{char.lower()}"
    if char.isdigit() and char.isascii():
        return char
    if char in UNSHIFTED:
        return UNSHIFTED[char]
    if char in SHIFTED:
        return f"shift-{SHIFTED[char]}"
    raise ValueError(
        f"cannot type {char!r}: it is not on a key that means the same thing "
        "under both the uk and us layouts"
    )


def keys_for_text(text: str) -> list[str]:
    return [key_for(char) for char in text]


def commands(text: str, trailing: list[str]) -> list[str]:
    """The monitor commands that type text and then any named keys after it."""
    keys = keys_for_text(text) + list(trailing)
    return [f"sendkey {key}" for key in keys]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--monitor", help="QEMU HMP monitor socket")
    parser.add_argument("--text", default="", help="characters to type")
    parser.add_argument(
        "--key",
        action="append",
        default=[],
        metavar="NAME",
        help=f"a named key to press after the text, one of: {', '.join(sorted(NAMED_KEYS))}",
    )
    parser.add_argument("--enter", action="store_true", help="press return after the text")
    parser.add_argument(
        "--delay",
        type=float,
        default=0.05,
        help="seconds between keystrokes, default 0.05",
    )
    parser.add_argument(
        "--print",
        dest="print_only",
        action="store_true",
        help="print the monitor commands instead of sending them, so the "
        "key mapping is testable without QEMU",
    )
    args = parser.parse_args()

    trailing = list(args.key)
    if args.enter:
        trailing.append("ret")

    unknown = [key for key in trailing if key not in NAMED_KEYS]
    if unknown:
        print(f"unknown key name(s): {', '.join(unknown)}", file=sys.stderr)
        return 2

    if not args.text and not trailing:
        parser.error("nothing to type: give --text, --key or --enter")

    try:
        to_send = commands(args.text, trailing)
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 2

    if args.print_only:
        print("\n".join(to_send))
        return 0

    if not args.monitor:
        parser.error("--monitor is required unless --print is given")

    with Monitor(args.monitor) as monitor:
        for command in to_send:
            monitor.command(command)
            time.sleep(args.delay)

    # Say what was typed by shape rather than by content: this types passwords.
    print(f"typed {len(args.text)} character(s)" + (f" then {' '.join(trailing)}" if trailing else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
