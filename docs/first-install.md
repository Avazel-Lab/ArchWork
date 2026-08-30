# First install on the desktop hardware

A runbook for the first physical ArchWork install, on `hmlxdesktop02`. Written before the attempt rather than reconstructed at the keyboard during it.

This is exploration, not M8. M8 asks for thirty days of daily use with health checks green; this is the first time the thing runs on metal, and the expectation is several attempts. Everything after the first wipe is repeatable, so the only step that costs anything is the one that destroys the NTFS data, and that data is confirmed expendable (D-017).

## Before you start

**Boot Windows from `sdb` once.** Prerequisite met and recorded in D-017 on 2026-08-29, but this runbook is what gets followed on the day: the disk about to be wiped carries an ESP of its own, and Windows must already be reaching its own one on `sdb` before that goes.

**Know which disk is which.** The desktop has two Samsung 970 EVO Plus 2 TB drives. The kernel names can swap between boots, so they are not identification.

| Disk | Serial | Holds | Do |
|---|---|---|---|
| Kubuntu root | `S6P1NS0T304068E` | the development install, this repository | leave alone |
| ArchWork target | `S4J4NX0R804138P` | Windows, NTFS data, its own ESP | destroy |

Check with `lsblk -d -o NAME,SIZE,SERIAL,MODEL`, and check the serial again at the installer's own confirmation prompt.

## 1. Write the installation medium

From the Kubuntu side, with a USB stick in:

```bash
lsblk -d -o NAME,SIZE,SERIAL,MODEL,TRAN     # find the stick, note the device
sudo scripts/make-install-usb.sh --iso ~/.cache/archwork/archlinux-x86_64.iso \
    --sha256 <sum from the Arch mirror> /dev/sdX
```

The stick is stock Arch. Nothing of ArchWork is on it: appending a partition to an isohybrid image means moving the backup GPT header, and a stick that boots is worth more than one that saves a `git clone`.

The script refuses a device that reports `removable=0`. If your enclosure lies about that, `--i-know-this-wipes-my-disk` overrides it, and at that point you are the guard.

## 2. Boot it

Firmware boot menu, choose the stick. Not the boot order: leave that alone, because it is what gets you back to Kubuntu if you stop here.

Ethernet is already up on the desktop, so networking needs nothing.

## 3. Get the repository onto the ISO

```bash
pacman -Sy git
git clone https://github.com/Avazel-Lab/ArchWork
cd ArchWork
```

The ISO does not ship `git`, and the installer refuses to run without it, because D-016 has it clone the checkout it runs from onto the target. That clone is how the installed machine carries the commit that built it.

## 4. Dry run first

```bash
./scripts/archwork-install.sh --profile desktop --dry-run \
    --expect-serial S4J4NX0R804138P \
    /dev/disk/by-id/nvme-Samsung_SSD_970_EVO_Plus_2TB_S4J4NX0R804138P
```

Writes nothing, prints every command. Read the device line in the summary and confirm it resolved to the disk you meant.

Address the disk by that `by-id` path rather than `/dev/nvme0n1`. The serial is in the path, and the serial is the only thing that separates the two identical drives. The installer resolves the symlink itself and shows both names at the prompt.

## 5. Install

```bash
./scripts/archwork-install.sh --profile desktop \
    --i-know-this-wipes-my-disk \
    --expect-serial S4J4NX0R804138P \
    /dev/disk/by-id/nvme-Samsung_SSD_970_EVO_Plus_2TB_S4J4NX0R804138P
```

`--i-know-this-wipes-my-disk` is required because this is not a virtual machine. That flag is the whole difference between a test and the real thing.

`--expect-serial` is optional, and is the guard that matters most here, so give it. The installer reads the target's serial and refuses unless it matches, so a mistyped device path becomes a refusal rather than a wipe. The serial appears twice on that command line, in the path and in the check, and they have to agree with the disk.

The two drives are the same model and size and their `nvme0n1` names can swap between boots, so the serial is the only thing that tells them apart. `S6P1NS0T304068E` is the Kubuntu root. If you see that serial anywhere in what you are about to run, stop.

You will be asked for:

1. **A LUKS passphrase**, twice. This is typed at every boot, before any keyboard layout beyond the console default exists.
2. **Confirmation of the target.** It prints the device, its size, model and serial, and its current partition table, then asks you to type the device path back. Either the `by-id` path or `/dev/nvme0n1` is accepted. **Check the serial here.** It is the last point at which the Windows disk is still there.

Then it partitions, encrypts, installs the base system, clones this repository to `/home/gary/src/ArchWork`, builds the recovery UKI and installs the bootloader.

## 6. Set a password, then reboot

The installer says this too:

```bash
arch-chroot /mnt passwd gary
```

Do not skip it. greetd will ask for that password, and D-012 has it unlock the keyring through PAM.

Reboot, remove the stick, and answer the LUKS prompt.

## 7. Bootstrap

Log in at the text console as `gary`:

```bash
cd ~/src/ArchWork
./bootstrap.sh
```

It prompts for the age passphrase, unwraps the private key in memory, brings up NetworkManager, and runs the playbook with a local connection. Nothing here needs a second machine (D-016).

`./bootstrap.sh --dry-run` runs the playbook with `--check` first if you want to see it before it acts.

Reboot again, or `systemctl start greetd`, and you should land at the greeter.

## 8. What to check

The VM criteria that M3 proved, on hardware this time, and the things a VM could not show:

- Log in at the greeter. A terminal on `SUPER+Return`, the launcher on `SUPER+D`, lock on `SUPER+L`, and the password unlocks it.
- `secret-tool store --label=test a b` prompts for nothing. That is D-012 holding.
- Open a file picker from PDF Arranger and from Okular. Both should be the portal's chooser, dark, matching the desktop.
- `tailscale status` answers. It will say logged out, which is correct until the auth key arrives.
- **Both monitors, at their real resolutions and refresh rates.** No VM has ever shown this. `dotfiles/hypr/hyprland.lua` names no monitor layout, which is fine for one virtual head and probably not for the real desk.
- **Audio, actual sound out of the actual speakers.** PipeWire is installed and has never been asked to make a noise.
- **The AMD GPU.** Hardware acceleration, and whether the desktop is smooth.
- **Suspend and resume**, which M4 is about but which you will hit by accident first.

Anything you fix by hand here goes into the repository before the next rebuild. That is the capture rule, and it is the whole reason this is worth doing more than once.

## Getting back

Kubuntu and Windows both keep their own bootloaders on their own disks (D-017). `bootctl install` makes systemd-boot the first EFI entry and systemd-boot only scans its own ESP, so it will not offer either of them. Use the firmware boot menu, or reorder with `efibootmgr`.

## If it goes wrong

The install is not the risky part; the wipe is, and after the first attempt there is nothing left to lose. Reinstalling is the same procedure from step 4.

The recovery UKI is on the ESP as a second boot entry, and `scripts/archwork-rollback` is on the installed system. Neither has been exercised on hardware.
