# Installing ArchWork on the desktop

A step by step guide for the first install on real hardware. Follow it in order.

Expect a couple of hours, most of it waiting for packages.

That estimate was an hour before the application manifests landed, and it is worth saying where the new one comes from rather than rounding up a guess. In a VM on the development machine, on 2026-09-03, the installer took under two minutes and the first reconcile took 33, of which most was building the AUR set. Real hardware has a faster disk and more cores and a worse excuse for being slow, but it is building the same packages, and `ungoogled-chromium-bin` and the rest are large downloads wherever they land. Budget two hours and be pleasantly surprised. Expect to do it more than once: this is the first time any of it runs outside a virtual machine, and the point of the exercise is to find what a VM could not show.

---

## The two disks

The desktop has two identical Samsung 970 EVO Plus 2 TB drives. Same model, same size, and their `/dev/nvme0n1` and `/dev/nvme1n1` names **can swap between boots**. Only the serial identifies them.

| | Serial | What is on it |
|---|---|---|
| ✅ **Install here** | `S4J4NX0R804138P` | Windows and NTFS data. All of it goes. |
| ⛔ **Never touch** | `S6P1NS0T304068E` | Kubuntu, the machine you develop on. |

The short version: **the target ends `138P`, Kubuntu ends `068E`.**

Windows also lives on the small SATA SSD (`sdb`) and boots from its own EFI partition there, so it survives this. Kubuntu is untouched. Both stay reachable from the firmware boot menu.

---

## Before you begin

- A USB stick, 2 GB or more. Its contents are destroyed.
- The Arch ISO. There is one at `~/.cache/archwork/archlinux-x86_64.iso`, 1.5 GB, from 2026-08-27. Download a fresh one from an Arch mirror if you would rather.
- Ethernet plugged in. The installer fetches packages.

---

## Step 1. Write the USB stick

On Kubuntu, with the stick plugged in:

```bash
lsblk -d -o NAME,SIZE,SERIAL,MODEL,TRAN
```

Find the row whose size matches your stick and whose `TRAN` says `usb`. Then:

```bash
cd ~/src/ArchWork
sudo scripts/make-install-usb.sh --iso ~/.cache/archwork/archlinux-x86_64.iso /dev/sdX
```

Replace `/dev/sdX` with the stick. The script refuses anything that is not removable, prints what it is about to destroy, and makes you type the device path back.

A couple of minutes.

---

## Step 2. Boot the stick

Reboot. As the ASUS logo appears, press **F8** for the boot menu, and choose the USB stick.

Do not change the boot order in the firmware. Leaving it alone is what gets you back to Kubuntu if you stop here.

**What you should see:** a plain Arch Linux boot menu, a lot of scrolling text, then:

```
root@archiso ~ #
```

You are running Arch from the stick. Nothing on any disk has changed yet.

---

## Step 3. The keyboard, which the installer sorts out

Nothing to type here. Read it anyway, because this is the one mistake with no way back from it.

The ISO starts on a US keyboard layout. The system you are about to install uses a UK one, and it asks for your disk passphrase at every boot from now on. Set a passphrase on US, type it back on UK, and `@ " # \ | ~` all land somewhere else. That is an encrypted disk you cannot open.

The installer runs `loadkeys uk` itself, before it touches the disk and before it asks for the passphrase, so the layout you set it on is the layout you will type it on. If `loadkeys` is missing or fails, it stops rather than carrying on.

Belt and braces: use only letters and digits in the passphrase. Those sit in the same place on both layouts.

---

## Step 4. Get the repository

```bash
pacman -Sy git
git clone https://github.com/Avazel-Lab/ArchWork
cd ArchWork
```

The ISO does not ship `git`, and the installer needs it: it clones this checkout onto the new machine, which is how the installed system records the commit that built it.

---

## Step 5. Dry run

Writes nothing. Prints everything it would do.

```bash
./scripts/archwork-install.sh --profile desktop --dry-run \
    --expect-serial S4J4NX0R804138P \
    /dev/disk/by-id/nvme-Samsung_SSD_970_EVO_Plus_2TB_S4J4NX0R804138P
```

**What you should see:** `DRY RUN. Nothing below is executed.`, the list of steps, and a summary naming the device, profile `desktop`, hostname `hmlxdesktop02` and user `gary`.

If it objects to the serial, stop and find out why. That is the guard working.

---

## Step 6. Install

The same command without `--dry-run`, plus the flag that permits it on real hardware:

```bash
./scripts/archwork-install.sh --profile desktop \
    --i-know-this-wipes-my-disk \
    --expect-serial S4J4NX0R804138P \
    /dev/disk/by-id/nvme-Samsung_SSD_970_EVO_Plus_2TB_S4J4NX0R804138P
```

The serial appears twice, in the path and in the check. Both must agree with the disk, or it stops before writing anything.

It asks for two things.

**A disk passphrase, three times.** Twice to set it, once to open the container. You type this at every boot, on a UK layout, before anything graphical exists. Choose something you can type in the dark.

**Confirmation of the target.** It prints the device, size, model and **serial**, and the current partition table, then asks you to type the device path back.

> **This is the last moment the Windows disk still exists.** Read the serial. It must end `138P`. If it ends `068E` that is Kubuntu: type anything else and it aborts.

Then it runs for a while: partition, encrypt, base packages, repository clone, recovery image, bootloader.

**What you should see at the end:** a summary of device, profile, hostname and user, and an instruction to set a password.

---

## Step 7. Set your password

```bash
arch-chroot /mnt passwd gary
```

Do not skip this one either. It is the password you log in with, and it is what unlocks your keyring, so the desktop does not ask a second time.

---

## Step 8. Reboot

```bash
reboot
```

Pull the stick out as it restarts.

**What you should see:** a boot menu offering `Arch Linux` and a recovery entry, then:

```
Please enter passphrase for disk cryptroot:
```

Type the passphrase from step 6. Nothing appears as you type. Then a text login. Log in as `gary`.

No desktop yet. That is expected.

---

## Step 9. Build the desktop

```bash
cd ~/src/ArchWork
./bootstrap.sh
```

It asks for the age passphrase, unwraps the secrets key in memory, brings up networking, and runs the playbook. This is the long part.

All of it happens on this machine. No other computer is involved at any point.

When it finishes:

```bash
reboot
```

**What you should see:** the passphrase prompt, then a graphical login screen showing the time. Log in with the password from step 7.

---

## Step 10. Look around

Day to day use, updating, health checks and rolling back are in [`user-guide.md`](user-guide.md). This section is only the first look.

A dark desktop with a bar across the top.

| Keys | What happens |
|---|---|
| `Super` + `Return` | terminal |
| `Super` + `D` | application launcher |
| `Super` + `Q` | close the window |
| `Super` + `L` | lock the screen |
| `Print` | screenshot into `~/Pictures/screenshots` |

The same table is on the wallpaper, generated from the configuration that binds the keys, so it cannot drift from them.

Worth checking, because no virtual machine could show any of it:

- **Both monitors**, at their real resolutions and refresh rates. Nothing in the configuration names a monitor layout yet, so this is the likeliest thing to need fixing.
- **Sound**, actually out of the speakers.
- **The graphics card.** It is an NVIDIA RTX 3060 running the open kernel modules, not the AMD part the CPU might lead you to expect (D-027). `hyprctl systeminfo` should name it, and `lsmod` should show `nvidia_drm` and no `nouveau`.
- **Suspend and resume.**
- Open a file from PDF Arranger and from Okular. Both pickers should be dark and match the desktop.
- `tailscale status` should answer. It will say logged out, which is right for now.

**Anything you fix by hand, tell me, and it goes into the repository before the next rebuild.** A fix that lives only on the machine disappears the next time it is rebuilt, and rebuilding is the entire point.

---

## Choosing which system boots

Nothing to do. The firmware boots the Kubuntu drive by default and you pick the Arch drive deliberately, which is the arrangement the repository owner already has and wants. `bootctl install` writes a boot entry on the Arch ESP; it does not change which drive this machine reaches for on its own.

Do not reorder anything with `efibootmgr`. Putting a Kubuntu entry in front of the Arch one means deliberately selecting the Arch drive and then landing back in Kubuntu, which is worse than the thing it was meant to fix.

## Getting back to Kubuntu or Windows

The install does not touch the other two bootloaders, which sit on their own disks. systemd-boot only scans its own EFI partition, so the Arch boot menu will never offer them.

Press **F8** at the ASUS logo and pick the one you want.

---

## If something goes wrong

Nothing after step 6 is dangerous, and the wiped disk has nothing left to lose, so reinstalling is steps 5 and 6 again.

- **The passphrase is refused at the boot prompt.** Almost certainly the keyboard layout in step 3, especially if the passphrase used `@ " # \ | ~`. Reinstalling is the fix.
- **No desktop after step 9.** Log in at the text console and run `journalctl -b -u greetd`.
- **A broken desktop configuration.** The compositor has a safe mode that starts with defaults, and the boot menu has a recovery entry.
- **Anything else.** The work is in git, and the machine can be reinstalled from the stick in an hour.

---

## What this is and is not

This is milestone M7.5, the machine becoming usable, not M8. M8 wants Steam, controllers, local AI models on `@ai_models`, a restore from the NAS, and thirty days of daily use with health checks green.

M7.5 asks for something smaller: a machine you can work on, and one this repository can be developed on. Everything reaches it through Ansible, exactly as it reaches a VM, so nothing is configured by hand and nothing needs capturing afterwards (D-036).

Most of this is proven in a virtual machine. Some of it has now met real firmware: the desktop was installed this way on 2026-08-30 and reached a Hyprland session on its own GPU (D-027). What a VM still cannot show is two monitors at their real resolutions, sound out of the speakers, and how the machine behaves over days rather than minutes. The only step that costs anything is the first wipe, and that data is confirmed expendable (D-017). Everything after it is repeatable.
