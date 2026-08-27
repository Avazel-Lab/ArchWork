# Decision log

Dated decisions made after the five topic documents in this directory were written, plus open questions that block milestones.

The topic documents hold the settled shape of the platform by subject. This log holds individual decisions with IDs, so that `docs/STATUS.yml` can point at one and say a milestone is blocked on it. When a decision here closes, update the relevant topic document to match and leave the entry as a record of when and why.

Status values: `open`, `accepted`, `superseded`.

## D-001 Launcher

**Status:** accepted
**Date:** 2026-08-27
**Affects:** `desktop-shell.md`, M3, M6

`desktop-shell.md` recorded the launcher as "Quicksilver". That was autocorrect. The launcher is Quickshell, meaning a Quickshell module rather than a separate application.

Consequence: the launcher does not exist until M6. M3 needs a conventional launcher of its own, and the fallback set needs to keep one after M6 so that a broken Quickshell leaves a usable desktop. Use fuzzel.

Second consequence: Quickshell now carries the bar, notifications, clipboard UI, screenshot UI, recorder UI, sleep inhibit control and the launcher. That is a lot of function in one young QML framework with a moving API. The requirement in `desktop-shell.md` that shell choices stay replaceable rather than coupled into bootstrap logic is the control that keeps this survivable. Hold to it.

## D-002 Networking stack

**Status:** open
**Blocks:** M1, M3

No decision document covers networking. Choose NetworkManager, or systemd-networkd with iwd.

NetworkManager integrates with desktop applets and handles roaming well, which matters on the laptop. systemd-networkd is lighter and fits the systemd-everywhere posture in `storage-boot.md`. `security-power.md` requires that whatever is chosen coexists cleanly with Tailscale.

Recommendation: NetworkManager on both profiles. The laptop needs roaming, and running two different stacks across profiles adds difference for no gain.

## D-003 Audio stack

**Status:** open
**Blocks:** M3

PipeWire is assumed everywhere and stated nowhere. Confirm PipeWire with WirePlumber and the PulseAudio and JACK compatibility layers, and record it in `applications-tooling.md`.

Recommendation: accept PipeWire. There is no serious alternative under Hyprland in 2026, and gaming on the desktop needs the PulseAudio compatibility layer.

## D-004 Session entry

**Status:** open
**Blocks:** M3

How the user reaches Hyprland after boot. Choose greetd with tuigreet, or TTY autologin into Hyprland from a shell profile.

This interacts with disk unlock, keyring unlock and Secret Service integration in `security-power.md`. Autologin plus full disk encryption gives one password prompt at boot, which is the transparent behaviour that document prefers, at the cost of leaving the session unlocked to anyone who boots the machine. greetd adds a second prompt and gives PAM a clean place to unlock the keyring.

Recommendation: greetd with tuigreet. The keyring integration is cleaner and the second prompt is the honest trade for it.

## D-005 AUR helper and build isolation

**Status:** open
**Blocks:** M2, M5

Choose an AUR helper, and choose whether AUR packages build on the target machine or in a clean chroot.

`storage-boot.md` puts AUR updates in the update workflow, so this affects the update path as well as bootstrap. Building on the target machine is simpler and pulls build dependencies onto the workstation. Building in a chroot keeps the machine clean and takes longer to set up.

Recommendation: paru, building in a clean chroot. The chroot costs a day at M2 and stops build dependencies accumulating on a machine that is meant to be reproducible.

## D-006 Secrets and key bootstrap

**Status:** open
**Blocks:** M1

`applications-tooling.md` lists both `git-crypt` and `age` with no division of labour between them, and neither answers the bootstrap problem: a fresh machine needs the decryption key before it can read the encrypted repository, and the key cannot live in the repository.

Decide what each tool guards, and decide how the key reaches a fresh machine. Options include a passphrase typed during bootstrap, a key on removable media, or fetching from a password manager that `security-power.md` already names.

Until this closes, do not build anything that depends on encrypted repository content.

Recommendation: `age` for everything, one key, delivered by typing a passphrase during bootstrap and derived to the key. Drop `git-crypt`. Two encryption tools with overlapping jobs means two sets of failure modes.

## D-007 Snapshot tooling

**Status:** open
**Blocks:** M5

Choose snapper, btrbk, or a purpose-written script.

`storage-boot.md` requires a pre-update snapshot and rollback to a known-good system snapshot and config state. snapper has the widest ecosystem and a boot menu integration that does not apply here, because this platform uses UKIs rather than GRUB. btrbk handles send and receive to another host, which matters for D-009.

Recommendation: btrbk. Its send and receive support means the snapshot decision and the backup decision share one tool rather than two.

## D-008 Disk unlock during the Secure Boot deferral

**Status:** open
**Blocks:** M1

`storage-boot.md` defers Secure Boot for about a month per machine. `security-power.md` prefers controls that stay transparent during normal use. Those pull in opposite directions.

TPM2 auto-unlock of LUKS2 only means anything with Secure Boot enabled. Without it, an attacker who boots a modified UKI is handed the key. So during the deferral month, either type a passphrase at every boot, or enrol the TPM and accept an unlock that does not hold up.

Recommendation: passphrase during the deferral, TPM2 enrolment as part of M10. Thirty days of typing a passphrase beats shipping a control that pretends to work.

## D-009 Off-machine backup

**Status:** open
**Blocks:** M8

Nothing in the decision documents covers backup. Btrfs snapshots are not backups. They live on the same device as the data, so one dead SSD takes the data and every snapshot with it.

`applications-tooling.md` mentions a NAS in passing, for FSearch indexing. Decide whether that NAS is also the backup target, what gets backed up, how often, and how a restore gets tested.

This does not block VM work. It blocks putting real data on a physical machine at M8.

Recommendation: btrbk send and receive to the NAS, matching D-007, with `/home` and `@ai_models` in scope. Add a restore test to the M8 exit criteria once this closes.

## D-010 Hostname and inventory naming

**Status:** open
**Blocks:** M2

Fix the naming convention for machines before the inventory exists, because renaming later touches every group variable file.

Other repositories in this account use names such as `hmlxdesktop01`. Decide whether ArchWork follows that convention, and decide whether inventory group names stay as the plain `desktop` and `laptop` that `desktop-laptop-differences.md` uses.

Recommendation: keep the group names `desktop` and `laptop` exactly as the decision document writes them, and let host names follow the existing convention. Groups express the profile. Host names identify the box.
