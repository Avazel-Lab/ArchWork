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

# A screen is "blank" when one colour covers at least this much of it. A text
# greeter is mostly background, so the threshold has to be close to 1.
BLANK_RATIO = 0.995


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


def describe(pixels: bytes, sample: int = 4) -> tuple[float, list[tuple[tuple[int, int, int], int]]]:
    """Most common colour's share of the screen, and the top few colours.

    Samples every nth pixel. A full count of a 1024x768 screen is 786k tuples
    for no extra confidence.
    """
    counts: collections.Counter = collections.Counter()
    for offset in range(0, len(pixels) - 2, 3 * sample):
        counts[(pixels[offset], pixels[offset + 1], pixels[offset + 2])] += 1

    total = sum(counts.values()) or 1
    return counts.most_common(1)[0][1] / total, counts.most_common(4)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--monitor", required=True, help="QEMU HMP monitor socket")
    parser.add_argument("--output", required=True, help="where to write the PPM")
    parser.add_argument("--wait", type=float, default=60.0, help="seconds to wait for content")
    parser.add_argument(
        "--allow-blank",
        action="store_true",
        help="capture and report, but do not fail on a blank screen",
    )
    args = parser.parse_args()

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
            width, height, pixels = read_ppm(args.output)
        except (OSError, ValueError) as exc:
            print(f"could not read a screenshot yet: {exc}", file=sys.stderr)
            if time.monotonic() > deadline:
                return 1
            time.sleep(2)
            continue

        ratio, top = describe(pixels)
        print(f"screen {width}x{height}, dominant colour covers {ratio:.3%}")

        if ratio < BLANK_RATIO or args.allow_blank:
            break

        if time.monotonic() > deadline:
            print(
                f"the screen stayed blank for {args.wait:.0f}s: "
                f"one colour covers {ratio:.3%} of it",
                file=sys.stderr,
            )
            return 1

        time.sleep(2)

    for colour, count in top:
        print(f"  rgb{colour}: {count}")
    print(f"saved {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
