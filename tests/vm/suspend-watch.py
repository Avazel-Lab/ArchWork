#!/usr/bin/env python3
"""Watch the guest suspend, and wake it again, from outside it.

A machine cannot time its own suspend. The last thing it does before S3 is
stop running, and the journal it writes afterwards records that a sleep
happened rather than when it was asked for. So the M4 sleep timing is
measured out here, against the QEMU monitor, from the keystroke that reset
the compositor's idle clock.

`info status` reports the guest's run state. A guest in S3 reads as
suspended; one still running reads as running. Waking it is `system_wakeup`,
which is the emulated equivalent of pressing a key on a sleeping machine.
"""

from __future__ import annotations

import argparse
import sys
import time

from qemu_monitor import Monitor


def run_state(monitor: Monitor) -> str:
    """The guest's run state as `info status` reports it."""
    reply = monitor.command("info status")
    for line in reply.splitlines():
        line = line.strip()
        if line.startswith("VM status:"):
            return line.split(":", 1)[1].strip()
    return ""


def wait_for_suspend(path: str, deadline: float, poll: float) -> int:
    """Seconds from now until the guest suspends. Non-zero if it never does."""
    started = time.monotonic()
    with Monitor(path) as monitor:
        while True:
            state = run_state(monitor)
            elapsed = time.monotonic() - started
            if "suspended" in state:
                print(f"{elapsed:.0f}")
                return 0
            if elapsed >= deadline:
                print(
                    f"the guest was still '{state}' after {elapsed:.0f}s",
                    file=sys.stderr,
                )
                return 1
            time.sleep(poll)


def wake(path: str) -> int:
    with Monitor(path) as monitor:
        monitor.command("system_wakeup")
        # Waking is not instant, and a guest asked twice does not wake twice.
        for _ in range(30):
            time.sleep(2)
            if "suspended" not in run_state(monitor):
                return 0
    print("the guest did not come back from suspend", file=sys.stderr)
    return 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--monitor", required=True, help="QEMU monitor socket")
    parser.add_argument(
        "--wait",
        type=float,
        metavar="SECONDS",
        help="wait up to this long for the guest to suspend, then print the "
        "seconds it took on stdout",
    )
    parser.add_argument("--wake", action="store_true", help="wake a suspended guest")
    parser.add_argument("--status", action="store_true",
                        help="print the guest's run state and exit. For saying what a "
                             "guest was doing when something timed out waiting on it")
    parser.add_argument("--poll", type=float, default=5.0, help="seconds between checks")
    args = parser.parse_args()

    if args.status:
        with Monitor(args.monitor) as monitor:
            print(run_state(monitor))
        return 0
    if args.wake:
        return wake(args.monitor)
    if args.wait is not None:
        return wait_for_suspend(args.monitor, args.wait, args.poll)

    parser.error("one of --wait, --wake or --status is required")
    return 2


if __name__ == "__main__":
    sys.exit(main())
