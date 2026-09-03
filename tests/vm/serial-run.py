#!/usr/bin/env python3
"""Run one command on a guest's serial console and report what it did.

For the places the harness has no SSH. The recovery UKI boots to a rescue
shell with no network and no sshd, and M5 asks that the rollback script on it
works, not merely that the shell appears. Something has to type into it.

The command is wrapped in markers rather than parsed out of the surrounding
console noise:

    echo <BEGIN>; <command>; echo <END>:$?

A rescue console interleaves kernel messages with whatever is typed, echoes
the command back, and wraps lines wherever it feels like it. Looking for the
exit status after a marker this script chose is the only reading of that
output that is not a guess. The status is the answer: a command that printed
something reassuring and exited 1 has not worked.

Exits 0 when the command exits 0, 1 otherwise, 2 if the marker never appears.
"""

from __future__ import annotations

import argparse
import re
import secrets
import socket
import sys
import time


def connect(path: str, deadline: float) -> socket.socket:
    """Open the socket, waiting for QEMU to create it."""
    while True:
        try:
            connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            connection.connect(path)
            return connection
        except OSError:
            if time.monotonic() > deadline:
                raise
            time.sleep(0.5)


def exit_status(transcript: bytes, token: str) -> int | None:
    """The status the guest reported, or None if it has not reported yet.

    Anchored on the end marker rather than on the last number in the output,
    and it skips the echo of the command itself: the shell prints the line
    containing the literal `echo <END>:$?` before it prints the expansion, so
    the first match is always the echo and never the answer.
    """
    matches = re.findall(rb"%s:(\d+)" % re.escape(token.encode()), transcript)
    if not matches:
        return None
    return int(matches[-1])


def run(path: str, command: str, timeout: float, log: str | None) -> int:
    token_begin = "ARCHWORK-BEGIN-" + secrets.token_hex(4)
    token_end = "ARCHWORK-END-" + secrets.token_hex(4)
    line = f"echo {token_begin}; {command}; echo {token_end}:$?\n"

    deadline = time.monotonic() + timeout
    transcript = bytearray()
    try:
        connection = connect(path, deadline)
    except OSError as error:
        print(f"cannot open {path}: {error}", file=sys.stderr)
        return 2

    with connection:
        # A bare newline first. The rescue shell may still be printing, and a
        # command typed into a prompt that has not arrived is lost.
        connection.sendall(b"\n")
        time.sleep(0.5)
        connection.sendall(line.encode())

        connection.settimeout(1.0)
        while time.monotonic() < deadline:
            try:
                chunk = connection.recv(4096)
            except socket.timeout:
                continue
            except OSError:
                break
            if not chunk:
                break
            transcript.extend(chunk)
            status = exit_status(bytes(transcript), token_end)
            if status is not None:
                write_log(log, transcript)
                if status != 0:
                    print(f"the guest reported exit status {status}", file=sys.stderr)
                return 0 if status == 0 else 1

    write_log(log, transcript)
    print(
        f"the guest never reported an exit status within {timeout:.0f}s. "
        f"Console transcript: {log or '(not saved)'}",
        file=sys.stderr,
    )
    return 2


def write_log(path: str | None, transcript: bytearray) -> None:
    if not path:
        return
    with open(path, "ab") as handle:
        handle.write(bytes(transcript))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--socket", required=True, help="QEMU serial unix socket")
    parser.add_argument("--command", required=True, help="the command to run on the guest")
    parser.add_argument("--timeout", type=float, default=120.0)
    parser.add_argument("--log", help="append the console transcript here")
    args = parser.parse_args()
    return run(args.socket, args.command, args.timeout, args.log)


if __name__ == "__main__":
    sys.exit(main())
