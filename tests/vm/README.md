# VM test harness

L3 of the test ladder: install ArchWork into a throwaway VM and assert the M1
exit criteria.

CI does not run any of this. GitHub Actions has no nested virtualisation, and a
job that skips itself and reports green is worse than no job. See
`docs/plan.md`.

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

M1 needs `--repeat 2`, on both profiles.

## What happens

1. **Install.** QEMU boots the ISO with the kernel and initramfs extracted from
   it, so that archiso's `script=` parameter can point at `provision.sh` served
   over HTTP from the host. The VM installs itself and powers off.
2. **Boot.** QEMU boots the installed disk. `serial-unlock.py` watches the
   serial console and answers the LUKS passphrase prompt.
3. **Assert.** `assert-m1.sh` runs on the guest over SSH and checks every M1
   criterion.

The repository reaches the guest as `git archive HEAD`, so an uncommitted
change cannot quietly alter what the test installs.

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
