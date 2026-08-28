#!/usr/bin/env python3
"""Capture the guest's framebuffer through the QEMU monitor.

M3's criteria are about what a person sees, and nothing the guest reports over
SSH can prove that a greeter reached the screen. QEMU's screendump takes the
framebuffer from outside the guest, so a machine that is quietly broken cannot
report otherwise.

What this asserts is deliberately narrow: something is drawn. It counts the
most common colour and fails when that colour covers effectively the whole
screen. It does not read the screen, and it makes no claim about themes,
fonts or layout. Those are judged by looking at the image this saves, because
a check that claimed to verify them and did not would be worse than no check.

Writes a PPM, since that is what screendump produces everywhere rather than
only on newer QEMU. Exits 0 when the screen has content, non-zero on timeout.
"""

from __future__ import annotations

import argparse
import collections
import os
import socket
import sys
import time

# How many sampled pixels must differ from the background before the screen
# counts as having something on it.
#
# An absolute count rather than a ratio. The first version of this asked that
# the dominant colour cover less than 99.5% of the screen, and the real
# greeter measured 99.45%: it passed by five hundredths of a percentage point,
# and a slightly smaller login box would have failed it. A text greeter is
# almost all background, so any ratio threshold has to sit so close to 1 that
# it stops discriminating. The same capture has 1407 differing pixels out of
# 256000 sampled, against exactly 0 for a blank screen, which is a gap worth
# putting a threshold in the middle of.
MIN_DRAWN_PIXELS = 200


def monitor_command(path: str, command: str, timeout: float = 10.0) -> str:
    """Send one command to a QEMU HMP monitor socket and return what it said."""
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
        sock.settimeout(timeout)
        sock.connect(path)
        # The monitor greets first. Read whatever is waiting, then send.
        time.sleep(0.2)
        try:
            sock.recv(65536)
        except socket.timeout:
            pass
        sock.sendall(command.encode() + b"\n")
        time.sleep(0.5)
        out = b""
        try:
            while True:
                chunk = sock.recv(65536)
                if not chunk:
                    break
                out += chunk
                if b"(qemu)" in out:
                    break
        except socket.timeout:
            pass
        return out.decode(errors="replace")


def read_ppm(path: str) -> tuple[int, int, bytes]:
    """Parse a binary PPM into width, height and raw RGB."""
    with open(path, "rb") as handle:
        data = handle.read()

    if not data.startswith(b"P6"):
        raise ValueError(f"{path} is not a binary PPM")

    # Header fields are whitespace separated and may have # comments between.
    fields: list[bytes] = []
    index = 2
    while len(fields) < 3:
        while index < len(data) and data[index : index + 1].isspace():
            index += 1
        if data[index : index + 1] == b"#":
            while index < len(data) and data[index] != 0x0A:
                index += 1
            continue
        start = index
        while index < len(data) and not data[index : index + 1].isspace():
            index += 1
        fields.append(data[start:index])
    index += 1  # the single whitespace byte after the maximum value

    width, height, _maxval = (int(f) for f in fields)
    return width, height, data[index : index + width * height * 3]


def describe(pixels: bytes, sample: int = 4) -> tuple[int, float, list[tuple[tuple[int, int, int], int]]]:
    """How many sampled pixels are not the background, its share, and the top colours.

    Samples every nth pixel. A full count of a 1280x800 screen is a million
    tuples for no extra confidence.
    """
    counts: collections.Counter = collections.Counter()
    for offset in range(0, len(pixels) - 2, 3 * sample):
        counts[(pixels[offset], pixels[offset + 1], pixels[offset + 2])] += 1

    total = sum(counts.values()) or 1
    dominant = counts.most_common(1)[0][1]
    return total - dominant, dominant / total, counts.most_common(4)


def verdict(path: str) -> tuple[bool, str]:
    """Read a PPM and say whether anything is drawn on it."""
    width, height, pixels = read_ppm(path)
    drawn, ratio, top = describe(pixels)
    summary = (
        f"screen {width}x{height}, {drawn} sampled pixels differ from the "
        f"background, which covers {ratio:.3%}"
    )
    for colour, count in top:
        summary += f"\n  rgb{colour}: {count}"
    return drawn >= MIN_DRAWN_PIXELS, summary


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--monitor", help="QEMU HMP monitor socket")
    parser.add_argument("--output", help="where to write the PPM")
    parser.add_argument(
        "--analyse",
        help="judge an existing PPM instead of capturing one, so the verdict is testable",
    )
    parser.add_argument("--wait", type=float, default=60.0, help="seconds to wait for content")
    parser.add_argument(
        "--allow-blank",
        action="store_true",
        help="capture and report, but do not fail on a blank screen",
    )
    args = parser.parse_args()

    if args.analyse:
        drawn, summary = verdict(args.analyse)
        print(summary)
        if not drawn:
            print("nothing is drawn on this screen", file=sys.stderr)
            return 1
        return 0

    if not args.monitor or not args.output:
        parser.error("--monitor and --output are required unless --analyse is given")

    deadline = time.monotonic() + args.wait
    ratio = 1.0
    top: list[tuple[tuple[int, int, int], int]] = []

    while True:
        if os.path.exists(args.output):
            os.unlink(args.output)

        monitor_command(args.monitor, f"screendump {args.output}")

        # screendump returns before the file is necessarily complete.
        for _ in range(20):
            if os.path.exists(args.output) and os.path.getsize(args.output) > 0:
                break
            time.sleep(0.25)

        try:
            drawn, summary = verdict(args.output)
        except (OSError, ValueError) as exc:
            print(f"could not read a screenshot yet: {exc}", file=sys.stderr)
            if time.monotonic() > deadline:
                return 1
            time.sleep(2)
            continue

        print(summary)

        if drawn or args.allow_blank:
            break

        if time.monotonic() > deadline:
            print(
                f"the screen stayed blank for {args.wait:.0f}s",
                file=sys.stderr,
            )
            return 1

        time.sleep(2)

    print(f"saved {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
