#!/usr/bin/env python3
"""Append a guest's serial console to a file until it goes quiet or the socket closes.

For the stretches where the harness is waiting on the guest rather than talking
to it. A shutdown that hangs looks exactly like a shutdown that is slow when
nothing is reading the console, and on 2026-09-01 and 2026-09-02 that cost two
runs: the recovery phase timed out twice with no record of what the guest was
doing, because the only console log stopped at the login prompt.

Runs in the background, is killed when the wait ends, and leaves a transcript
either way.
"""

from __future__ import annotations

import argparse
import socket
import sys


def drain(path: str, out: str, idle_timeout: float) -> int:
    try:
        connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        connection.connect(path)
    except OSError as error:
        print(f"cannot open {path}: {error}", file=sys.stderr)
        return 1

    connection.settimeout(idle_timeout)
    with connection, open(out, "ab", buffering=0) as log:
        while True:
            try:
                chunk = connection.recv(4096)
            except socket.timeout:
                # Nothing for a while. That is a finding rather than an error:
                # a guest that has stopped saying anything is the shape of a
                # hang, and the transcript so far is what shows where.
                return 0
            except OSError:
                return 0
            if not chunk:
                # QEMU exited, which for -no-reboot is the guest rebooting.
                return 0
            log.write(chunk)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--socket", required=True, help="QEMU serial unix socket")
    parser.add_argument("--out", required=True, help="file to append the transcript to")
    parser.add_argument(
        "--idle-timeout",
        type=float,
        default=600.0,
        help="give up after this many seconds with nothing on the console",
    )
    args = parser.parse_args()
    return drain(args.socket, args.out, args.idle_timeout)


if __name__ == "__main__":
    sys.exit(main())
