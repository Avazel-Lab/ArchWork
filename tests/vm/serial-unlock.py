#!/usr/bin/env python3
"""Answer the LUKS passphrase prompt on a QEMU serial console.

M1's exit criterion is an unattended boot, and a machine with LUKS2 and no TPM
enrolment asks for a passphrase every time. TPM2 enrolment waits for M10
(D-008), so the passphrase is real and something has to type it.

The alternative was a keyfile in the initramfs for tests only. That would make
the test pass while exercising a boot path neither real machine uses, so this
drives the real prompt instead.

Reads and writes a QEMU serial unix socket. Exits 0 once the login prompt
appears, non-zero on timeout.
"""

from __future__ import annotations

import argparse
import re
import socket
import sys
import time

# systemd's password agent prompt, and the plymouth-free console variant.
PASSPHRASE_PROMPT = re.compile(rb"(passphrase|password) for", re.IGNORECASE)
LOGIN_PROMPT = re.compile(rb"\blogin:", re.IGNORECASE)
PANIC = re.compile(rb"(Kernel panic|Failed to start|emergency mode|You are in emergency)", re.IGNORECASE)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--socket", required=True, help="QEMU serial unix socket")
    parser.add_argument("--passphrase-file", required=True)
    parser.add_argument("--timeout", type=int, default=300, help="seconds to wait for a login prompt")
    parser.add_argument("--log", help="write the console transcript here")
    parser.add_argument("--max-attempts", type=int, default=3)
    args = parser.parse_args()

    with open(args.passphrase_file, "rb") as handle:
        passphrase = handle.read().strip()

    connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    deadline = time.monotonic() + args.timeout

    # QEMU may not have created the socket yet.
    while True:
        try:
            connection.connect(args.socket)
            break
        except (FileNotFoundError, ConnectionRefusedError):
            if time.monotonic() > deadline:
                print(f"serial socket {args.socket} never appeared", file=sys.stderr)
                return 1
            time.sleep(0.5)

    connection.settimeout(1.0)

    transcript = bytearray()
    pending = bytearray()
    attempts = 0

    while time.monotonic() < deadline:
        try:
            chunk = connection.recv(4096)
        except socket.timeout:
            continue
        except OSError as exc:
            print(f"serial read failed: {exc}", file=sys.stderr)
            break

        if not chunk:
            break

        transcript += chunk
        pending += chunk
        sys.stdout.buffer.write(chunk)
        sys.stdout.buffer.flush()

        if PANIC.search(pending):
            print("\nconsole reported a failure, giving up", file=sys.stderr)
            write_log(args.log, transcript)
            return 2

        if LOGIN_PROMPT.search(pending):
            write_log(args.log, transcript)
            return 0

        if PASSPHRASE_PROMPT.search(pending):
            attempts += 1
            if attempts > args.max_attempts:
                print("\npassphrase rejected repeatedly", file=sys.stderr)
                write_log(args.log, transcript)
                return 3
            connection.sendall(passphrase + b"\n")
            # Drop what we have matched so the same prompt is not answered
            # twice from one buffer.
            pending.clear()

        # Keep the search window bounded on a long boot.
        if len(pending) > 65536:
            del pending[:-4096]

    print("\ntimed out waiting for a login prompt", file=sys.stderr)
    write_log(args.log, transcript)
    return 1


def write_log(path: str | None, transcript: bytearray) -> None:
    if not path:
        return
    with open(path, "wb") as handle:
        handle.write(transcript)


if __name__ == "__main__":
    sys.exit(main())
