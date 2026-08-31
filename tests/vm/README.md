# VM test harness

L3 of the test ladder: install ArchWork into a throwaway VM, reconcile it, log
in at the greeter and assert the M1 and M3 exit criteria.

CI does not run any of this. GitHub Actions has no nested virtualisation, and a
job that skips itself and reports green is worse than no job. See
`docs/plan.md`.

## Work directory and memory

The harness writes the disk image into `${TMPDIR:-/tmp}`. With the M2 package
set that image reaches roughly 4.4G. Where `/tmp` is a tmpfs, as it is on
Ubuntu, that sits in RAM alongside the guest's own memory. Set `TMPDIR` to
somewhere disk-backed on a machine with less RAM to spare:

```bash
TMPDIR=~/.cache/archwork make vm-idempotence ISO=/path/to/archlinux.iso
```

## What you need

- `qemu-system-x86_64` and `/dev/kvm`
- `edk2-ovmf` for UEFI firmware
- `libarchive` for `bsdtar`
- A stock Arch Linux ISO

## Running it

```bash
make vm-rebuild ISO=/path/to/archlinux.iso

# or directly, with more control
tests/vm/run-install.sh --iso /path/to/archlinux.iso --profile desktop
tests/vm/run-install.sh --iso /path/to/archlinux.iso --profile laptop --repeat 2 --keep
```

M1 needs `--repeat 2`, on both profiles. M3 needs `--reconcile`: greetd is
configured by the session role, so a machine that has only been installed has
no greeter to log in at.

## Resuming, when the bug is in the harness

A full run takes about forty minutes, nearly all of it installing. On
2026-08-29 four of them were spent discovering one-line harness bugs: a check
that asked the wrong question, a keypress sent before the lock screen existed,
another sent before the shell reached a prompt, and an argument the remote
shell expanded. Each cost a complete reinstall to find.

So a kept run can be booted again and its later phases repeated:

```bash
tests/vm/run-install.sh --iso /path/to/archlinux.iso --reconcile --keep
# ... it fails in phase 8, you fix the harness, then:
tests/vm/run-install.sh --resume ~/.cache/archwork/archwork-vm.XXXXXX \
    --phases greeter,session,desktop,portals
```

That took 38 seconds, against the 40 minutes a full run costs.

## The power phase

M4's criteria are wall clock timings, so measuring them costs wall clock time.
`--power` on a reconciled run, or `--phases session,power` on a resumed one,
adds about 65 minutes: two idle windows of half an hour, one with a sleep
inhibitor held and one without.

```bash
make vm-power ISO=/path/to/archlinux.iso
```

Nothing can shorten it. The compositor's idle counter only resets on real
input, which is why each window starts with a keystroke sent through QEMU, and
there is no way to wind it forward.

Two of the three timings are observed from inside the session, by
`assert-m4.sh`. The third cannot be: a machine that suspends stops being able
to report anything, so `suspend-watch.py` measures that one from out here
against the monitor socket, and wakes the guest afterwards.

The dim at five minutes is the criterion a VM cannot show you. There is no
backlight device, `brightnessctl` no-ops, and nothing observable changes
(D-028). `assert-m4.sh` prints that as a skip rather than a pass, and says so
in its summary. Only the laptop panel can settle it.

`session` has to come before `desktop`, `portals` or `power`. A resumed run boots the
machine from cold, so it arrives at the greeter with nobody logged in and an
empty `/tmp`, and `phase_session` is both what types the password at that
greeter and what puts the check scripts on the machine. Leaving it out is
refused during preflight rather than 30 seconds later with "command not
found".

`--resume` needs no `--iso`, implies `--keep`, and takes the profile, the login
and the SSH key out of the kept directory rather than from its own defaults,
because those belong to that machine.

**What it does not do, and this is the whole caveat.** It re-runs the harness
against a machine an earlier run installed. Nothing updates that machine's copy
of this repository, so it proves a change to `tests/vm/`, and proves nothing at
all about a change to `ansible/` or `dotfiles/`. `phase_install` and
`phase_reconcile` are not resumable for that reason.

**A resumed run is never evidence.** It prints no commit SHA and says so when
it finishes. `docs/STATUS.yml` takes clean rebuilds only.

## What happens

1. **Install.** QEMU boots the ISO with the kernel and initramfs extracted from
   it, so that archiso's `script=` parameter can point at `provision.sh` served
   over HTTP from the host. The VM installs itself and powers off.
2. **Boot.** QEMU boots the installed disk. `serial-unlock.py` watches the
   serial console and answers the LUKS passphrase prompt.
3. **Assert.** `assert-m1.sh` runs on the guest over SSH and checks every M1
   criterion.
4. **Reconcile**, with `--reconcile`. The guest runs `bootstrap.sh`, which is
   the command an operator runs, once with `--dry-run` and then twice for
   real. The second real run has to report `changed=0`.
5. **Greeter.** `screendump.py` captures the framebuffer through the QEMU
   monitor and refuses a screen with nothing drawn on it.
6. **Log in.** `sendkey.py` types the user name and password at the real
   greeter, from outside the guest. `assert-m3.sh` then asserts the session
   over SSH, including the criterion the whole shape exists for: the login
   password unlocked the keyring through PAM, with no second prompt.
7. **Use the desktop.** Real key presses at the framebuffer open a terminal,
   close it, open the launcher, start an application from it, lock the session
   and unlock it. `check-session.sh` answers one question about the session
   between presses.
8. **Recovery.** The recovery UKI is selected with `bootctl set-oneshot` and
   booted, and has to reach a rescue shell.

The repository reaches the guest as a git bundle of committed state, so an
uncommitted change cannot quietly alter what the test installs.

## Looking at what it drew

D-021 has a person judge appearance, because a pixel check that claimed to
verify themes and fonts would be worse than no check. `--captures DIR` keeps
the screen captures a run takes, including the ones a failing phase saves:

```bash
tests/vm/run-install.sh --iso /path/to/archlinux.iso --reconcile \
    --captures ~/archwork-captures
```

They are PPM files, which anything can open. Nothing else in this repository
says whether the desktop looks right.

## Why the keys are typed from outside

The greetd password has to go through the real PAM stack at the real greeter,
or the keyring criterion is unprovable (D-021). Autologin, a unit that starts
Hyprland and `machinectl shell` all bypass it.

`sendkey` puts scancodes on the emulated keyboard, so it works before a
session exists and needs nothing installed on the machine under test. QEMU
names keys by position and the guest's keymap decides what they produce, so
`sendkey.py` refuses any character whose key means something different under
the `uk` keymap the installer sets and the `us` one it does not.

## Why the passphrase is typed rather than a keyfile

M1 asks for an unattended boot, and LUKS2 with no TPM enrolment asks for a
passphrase at every boot. TPM2 enrolment waits for M10 (D-008).

Putting a keyfile in the initramfs for tests would make the test pass while
exercising a boot path neither real machine ever uses. Driving the real prompt
over the serial console costs about forty lines and tests the real thing.

## Recording a result

A passing run prints the commit SHA. Put it in `docs/STATUS.yml`:

```yaml
last_rebuild:
  status: passed
  commit: <the SHA it printed>
  date: <today>
```

`scripts/check-plan-status.py` rejects a passing rebuild with no SHA. If there
is no SHA, it did not happen.
