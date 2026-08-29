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
