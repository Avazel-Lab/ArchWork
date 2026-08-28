#!/usr/bin/env python3
"""Talk to a QEMU HMP monitor socket.

Two things drive the guest's display from outside it: screendump.py captures
the framebuffer, sendkey.py types at it. Both speak the same protocol over the
same socket, so it lives here rather than in whichever of them was written
first.

Nothing here runs on its own. A monitor connection is a context manager so a
run of keystrokes shares one connection: reconnecting per keystroke works, but
a password then takes half a minute to type.
"""

from __future__ import annotations

import socket
import time

PROMPT = b"(qemu)"


class Monitor:
    """One connection to a QEMU HMP monitor socket."""

    def __init__(self, path: str, timeout: float = 10.0) -> None:
        self.path = path
        self.timeout = timeout
        self._sock: socket.socket | None = None

    def __enter__(self) -> "Monitor":
        self._sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self._sock.settimeout(self.timeout)
        self._sock.connect(self.path)
        # The monitor greets first and ends its greeting with the prompt.
        # Swallow it, or it turns up in the reply to the first command.
        self._sock.settimeout(1.0)
        self._read_until_prompt()
        return self

    def __exit__(self, *_exc: object) -> None:
        if self._sock is not None:
            self._sock.close()
            self._sock = None

    def command(self, text: str) -> str:
        """Send one command and return whatever the monitor said back."""
        if self._sock is None:
            raise RuntimeError("the monitor connection is not open")
        self._sock.sendall(text.encode() + b"\n")
        return self._read_until_prompt()

    def _read_until_prompt(self) -> str:
        deadline = time.monotonic() + self.timeout
        out = b""
        while time.monotonic() < deadline:
            try:
                chunk = self._sock.recv(65536)  # type: ignore[union-attr]
            except socket.timeout:
                break
            if not chunk:
                break
            out += chunk
            if PROMPT in out:
                break
        return out.decode(errors="replace")


def monitor_command(path: str, command: str, timeout: float = 10.0) -> str:
    """Send a single command over its own connection."""
    with Monitor(path, timeout) as monitor:
        return monitor.command(command)
