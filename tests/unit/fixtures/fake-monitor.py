#!/usr/bin/env python3
"""A stand-in for QEMU's HMP monitor, for tests that must not need QEMU.

Greets the way QEMU does, echoes a prompt after every command, and records
what it was sent. That is the whole protocol tests/vm/qemu_monitor.py speaks,
so a client that works against this works against QEMU.

  fake-monitor.py SOCKET RECORD

Serves one connection, then exits.
"""

import socket
import sys

GREETING = b"QEMU 8.2.0 monitor - type 'help' for more information\n(qemu) "


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2

    path, record = sys.argv[1], sys.argv[2]

    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as server:
        server.bind(path)
        server.listen(1)
        conn, _ = server.accept()
        with conn, open(record, "wb") as handle:
            conn.sendall(GREETING)
            buffer = b""
            while True:
                chunk = conn.recv(4096)
                if not chunk:
                    break
                buffer += chunk
                while b"\n" in buffer:
                    line, buffer = buffer.split(b"\n", 1)
                    handle.write(line + b"\n")
                    handle.flush()
                    conn.sendall(line + b"\n(qemu) ")
    return 0


if __name__ == "__main__":
    sys.exit(main())
