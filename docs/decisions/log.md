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

**Status:** accepted
**Date:** 2026-08-27
**Affects:** `applications-tooling.md`, M1, M3

Use NetworkManager on both profiles.

The laptop roams between networks and hits captive portals. NetworkManager handles both without custom logic, and systemd-networkd with iwd does not. Running one stack on the desktop and another on the laptop would break the shared-core principle for a daemon that gets touched twice a year, and would double the surface where Tailscale integration can go wrong.

Consequences:

- M1 configures NetworkManager, not `systemd-networkd`. Mask `systemd-networkd` and `systemd-resolved` conflicts explicitly rather than leaving both installed and racing.
- The Quickshell bar at M6 gets a NetworkManager applet. Until then M3 uses `nmtui`.
- Verify Tailscale coexistence as part of the M3 exit criteria, per `security-power.md`.

## D-003 Audio stack

**Status:** accepted
**Date:** 2026-08-27
**Affects:** `applications-tooling.md`, M3

Use PipeWire with WirePlumber and the full compatibility set on both profiles: `pipewire`, `wireplumber`, `pipewire-pulse`, `pipewire-alsa`, `pipewire-jack`.

There is no serious alternative under Hyprland. Gaming on the desktop needs the PulseAudio layer. The JACK and ALSA layers cost nothing to install and save an afternoon the first time something wants them.

Consequences:

- Audio is a shared package group, not a desktop-only one. A laptop without working sound is broken, not minimal.
- Health checks at M5 assert that `wireplumber` is running and that a sink exists.

## D-004 Session entry

**Status:** accepted
**Date:** 2026-08-27
**Affects:** `desktop-shell.md`, `security-power.md`, M3

Use greetd with tuigreet on both profiles.

`security-power.md` requires a Secret Service implementation for keyring integration, and PAM can only unlock the keyring if it sees a password at login. Autologin gives one password at boot but leaves PAM nothing to unlock with, so the keyring prompt reappears at first use and anyone who boots the machine lands in an unlocked session. The second prompt is what buys the keyring integration, so it is the price rather than the flaw.

SDDM would give the same keyring benefit and would pick up the Kvantum theming, but it pulls a Qt stack into the boot path for a screen that is on screen for two seconds.

Consequences:

- The login password unlocks the keyring through `pam_gnome_keyring` or the equivalent for whichever Secret Service implementation gets chosen. That implementation is still unnamed in `security-power.md` and needs picking during M3.
- Hyprland launches from a greetd session command, not from a shell profile.
- Two password prompts at boot: LUKS, then greetd. D-008 decides whether the LUKS one stays.

## D-005 AUR helper and build isolation

**Status:** accepted
**Date:** 2026-08-27
**Affects:** `applications-tooling.md`, M2, M5

Use paru, building in a clean chroot through `devtools`.

Building on the target machine leaves `base-devel` and every AUR package's make dependencies on a workstation that is meant to be reproducible, and lets two machines drift apart in ways an M7 rebuild test cannot detect. The chroot costs setup time at M2 and slower builds, and buys a machine whose installed set matches its manifest.

aurutils with a local repository would be cleaner still for two machines, but it means maintaining a package repository, which is a subproject this platform does not need yet.

Consequences:

- M2 sets up `devtools` and the chroot before installing any AUR package.
- The update script at M5 runs AUR updates through the same chroot. Never build outside it.
- AUR packages get pinned by name in a manifest like everything else. `applications-tooling.md` already requires declarative package selection.
- Revisit aurutils if chroot build times become the reason updates get skipped.

## D-006 Secrets and key bootstrap

**Status:** accepted
**Date:** 2026-08-27
**Affects:** `applications-tooling.md`, `security-power.md`, M1

Use `age` for everything. Drop `git-crypt`.

The age private key lives in the repository, itself encrypted with a long diceware passphrase through `age -p`. Bootstrap prompts for the passphrase, unwraps the key, then decrypts everything else with it.

This depends on nothing external. No network, no removable media, no reachable Vaultwarden. Recovery is the point of this platform, and a rebuild path that needs a VPS to be up is a rebuild path that fails on the day it matters. Pulling the key from Vaultwarden would add the network, the VPS, the master password and a TOTP device to the list of things that must work during a rebuild.

Two encryption tools with overlapping jobs means two sets of failure modes, so `git-crypt` comes out of `applications-tooling.md`.

Consequences:

- Store the passphrase in NordPass as well. It protects everything, and forgetting it means the encrypted content is gone.
- Keep the encrypted set small. WiFi PSKs, a Tailscale auth key and service tokens belong there. SSH private keys and anything a password manager already holds do not: putting them in the repository widens what one passphrase protects for no gain.
- Bootstrap must prompt for the passphrase once and hold the unwrapped key in memory, never writing it to the new system's disk outside its final destination.
- Rotating the passphrase means re-wrapping one key, not re-encrypting every secret. That is the main practical reason for the wrapped-key layer rather than encrypting each secret with a passphrase directly.
- Add an M1 exit check: on a machine with the wrong passphrase, bootstrap fails cleanly and leaves no partial state.

## D-007 Snapshot tooling

**Status:** accepted
**Date:** 2026-08-27
**Affects:** `storage-boot.md`, M5, M8

Use btrbk.

One declarative config covers snapshots, retention and `btrfs send`/`receive` to another host, so D-009 reuses this tool instead of adding a second one. snapper's headline feature is its GRUB menu integration, and D-011 keeps systemd-boot, so that is dead weight here. Running snapper for snapshots and btrbk for backup would mean two tools with overlapping models of the same subvolumes and two retention policies that can disagree, which is the same objection that removed `git-crypt` at D-006.

The cost is writing the pacman pre-transaction hook that `snap-pac` would have given free. That is roughly ten lines and it goes through ShellCheck like everything else.

Consequences:

- M5 writes a `/etc/pacman.d/hooks/` pre-transaction hook that calls btrbk before any package transaction.
- Retention policy lives in the btrbk config, in the repository, like all other configuration.
- Snapshots land on `@snapshots`, which `storage-boot.md` already provides.
- `@home`, `@var_log`, `@var_cache` and `@ai_models` stay outside the rollback set. btrbk still snapshots `@home` for backup purposes at D-009, but a system rollback must not touch it.

## D-008 Disk unlock during the Secure Boot deferral

**Status:** accepted
**Date:** 2026-08-27
**Affects:** `storage-boot.md`, `security-power.md`, M1, M10

Type the LUKS2 passphrase at every boot until Secure Boot is enabled. Enrol TPM2 as part of M10, not before.

TPM2 auto-unlock only means anything with Secure Boot on. Without it, an attacker boots a modified UKI and the TPM hands over the key, so the unlock is transparent to the user and to the attacker alike. `security-power.md` prefers controls that stay transparent during normal use, but a control that pretends to work is worse than a prompt.

Enrolling now and re-enrolling at M10 was rejected because the re-enrolment is easy to forget, and forgetting it means unlock silently keeps working against the weak policy with nothing to indicate it.

Consequences:

- Two prompts at boot during the deferral: LUKS, then greetd from D-004. One after M10.
- M10 enrols with `systemd-cryptenroll` against PCR 7 and PCR 11. PCR 11 is the UKI measurement that `systemd-stub` provides, which D-011 preserved by keeping UKIs.
- Keep a recovery key printed and stored offline before enrolling the TPM. A firmware update changes PCR values and locks you out otherwise. Add this to the M10 exit criteria.
- The M10 exit criteria already require retesting rollback and rescue with Secure Boot on. Retest TPM2 unlock after a deliberate firmware setting change too.

## D-009 Off-machine backup

**Status:** accepted
**Date:** 2026-08-27
**Affects:** `storage-boot.md`, M8

Back up to the NAS using btrbk send and receive. Scope is `@home` and `@ai_models`.

This reuses the D-007 tool, so one config covers snapshots, retention and backup. Incremental sends are cheap because btrfs already knows what changed between snapshots.

Everything else on the machine is reproducible from this repository, which is the point of the platform. `@home` and `@ai_models` are the only subvolumes holding data that a rebuild cannot recreate.

Consequences:

- **Verify the NAS runs btrfs before relying on this.** `btrfs receive` needs a btrfs target. A ZFS or ext4 NAS means either a btrfs-formatted dataset on it, or a different backup tool, and finding that out at M8 is late. Check during M5, when btrbk goes in. Confirmed by the repository owner on 2026-08-28: the NAS runs btrfs. M5 still has to prove a send and receive actually completes, which is a different claim from the filesystem being right.
- Residual risk accepted: the NAS is in the same building. This covers drive failure, accidental deletion and a bad update. It does not cover fire or theft. Revisit if the data on `@home` becomes worth more than that.
- Add a restore test to the M8 exit criteria. A backup nobody has restored from is a hypothesis.
- `@ai_models` is desktop-only per `desktop-laptop-differences.md`, so the laptop backs up `@home` alone.

## D-010 Hostname and inventory naming

**Status:** accepted
**Date:** 2026-08-27
**Affects:** `desktop-laptop-differences.md`, M2

Host names follow the existing convention: `hmlxdesktop01`, `hmlxlaptop01`. Ansible inventory groups stay `desktop` and `laptop`, exactly as `desktop-laptop-differences.md` writes them.

Groups express the profile. Host names identify the box. Keeping the two jobs separate is what lets a second laptop join the `laptop` group without any variable file changing, and it keeps ArchWork consistent with the other repositories in this account.

Consequences:

- `ansible/inventory/` defines `desktop` and `laptop` groups. `group_vars/desktop.yml`, `group_vars/laptop.yml` and `group_vars/all.yml` hold the differences from `desktop-laptop-differences.md`.
- `host_vars/` stays empty unless a genuine per-machine fact appears. A value that belongs to the profile goes in `group_vars`, not `host_vars`.
- No role, task or template reads the host name to decide behaviour. `CLAUDE.md` already forbids this.
- A rebuild being tested alongside the machine it replaces gets the next number, not a special-case name. Applied on 2026-08-28: the Arch desktop is `hmlxdesktop02`, because the same hardware already carries `hmlxdesktop01` as its Kubuntu development install and the two dual boot.

## D-011 Bootloader, reopened

**Status:** accepted
**Date:** 2026-08-27
**Affects:** `storage-boot.md`, M1, M5, M10

Keep systemd-boot with Unified Kernel Images. Do not switch to GRUB.

GRUB was reconsidered because `grub-btrfs` with snapper puts snapshots in the boot menu, making rollback a menu entry rather than a command. That is the only serious argument for it, and it is a real one.

It loses to the costs. GRUB means abandoning UKIs and returning to `grub-mkconfig`, which is exactly the ad hoc kernel parameter accumulation `storage-boot.md` warns against. Secure Boot at M10 goes from a single `sbctl` signature over one EFI binary to a standalone GRUB image with modules baked in, on a bootloader with a history of Secure Boot CVEs and DBX revocations. TPM2 measured boot loses the predictable PCR 11 measurement that `systemd-stub` provides, which D-008 depends on at M10.

The recovery UKI already covers the same need. Boot it, swap the subvolume, reboot.

One point in GRUB's favour is commonly overstated and does not apply here: GRUB cannot unlock a LUKS2 volume that uses Argon2id, but only an encrypted `/boot` needs that. This design leaves the ESP unencrypted and unlocks root from the initramfs, so the limitation is irrelevant.

Consequences:

- M1 ships a rollback script on the recovery UKI, not just a documented procedure. The gap against GRUB is keystrokes, and a script closes most of it.
- M5 exercises that script rather than a documented manual sequence.
- Revisit only if the recovery UKI path proves painful in real use, and record the evidence if so.

## D-012 Secret Service implementation

**Status:** accepted
**Date:** 2026-08-27
**Affects:** `security-power.md`, `applications-tooling.md`, M3, D-004

`security-power.md` requires a Secret Service implementation for keyring integration but does not name one. D-004 depends on it, because the whole reason for choosing greetd over autologin was that PAM unlocks the keyring from the login password.

Candidates are `gnome-keyring`, KWallet, or `keepassxc` acting as the Secret Service provider.

`gnome-keyring` has the mature PAM module and is what most Wayland desktops assume. It also drags in a GNOME dependency on a Hyprland system. KWallet fits the Kvantum and Qt theming already chosen but expects more of Plasma than is present here. `keepassxc` would consolidate with the password managers in `security-power.md`, but its PAM story is weaker, which undercuts D-004.

Use `gnome-keyring`. The PAM integration is the thing being bought, and it is the only one of the three that does it well.

The GNOME dependency was weighed and accepted. `gnome-keyring` pulls in libraries rather than a session, and nothing in it requires GNOME to be running.

Consequences:

- M3 installs `gnome-keyring` and configures `pam_gnome_keyring` in the greetd PAM stack, so the login password unlocks the keyring with no second prompt (D-004).
- `security-power.md` names the implementation rather than leaving it open.
- The M3 exit criteria already test this. Keep that test rather than assuming the PAM module works.

## D-013 Swap and hibernation

**Status:** accepted
**Date:** 2026-08-27
**Affects:** `storage-boot.md`, `security-power.md`, `desktop-laptop-differences.md`, M1

zram for swap on both profiles, through `zram-generator`. The laptop additionally gets a swapfile sized to RAM, and hibernates.

`security-power.md` specifies sleep after 30 minutes and says nothing beyond it, so a laptop left asleep overnight goes flat. The laptop therefore uses `suspend-then-hibernate`, sleeping first and hibernating after a delay. The desktop never hibernates and needs no swapfile.

This has to be settled before M1 rather than after, because `resume=` and `resume_offset=` belong in the kernel command line at install time. Adding them later means regenerating UKIs and re-enrolling TPM2 against changed PCR values at M10, which is the retrofit `storage-boot.md` says the boot design should avoid.

**This amends the subvolume layout.** Btrfs will not host a swapfile on a compressed copy-on-write subvolume, so the laptop needs a seventh subvolume, `@swap`, with `NODATACOW` set and compression off. `storage-boot.md` fixed the layout at six, so that document changes here rather than the installer quietly creating a subvolume no decision lists.

Consequences:

- `@swap` exists on the laptop only. The desktop layout stays at six subvolumes.
- `@swap` sits outside the rollback boundary. Rolling back a swapfile achieves nothing and would change `resume_offset`, which is baked into the laptop command line.
- The laptop command line carries `resume=` and `resume_offset=`. The desktop command line carries neither.
- M1 asserts that hibernate and resume work on the laptop profile before M9 depends on it.
- Hibernating from a LUKS2 volume needs the resume device available in the initramfs. The `systemd` hooks handle this, which is another reason not to use the busybox set.

## D-014 Rollback script delivery

**Status:** accepted
**Date:** 2026-08-27
**Affects:** `storage-boot.md`, M1, M5

The rollback script lives on the root filesystem at `/usr/local/bin/archwork-rollback`. The recovery UKI boots to a rescue shell, from which the Btrfs top level gets mounted and the script run.

D-011 said the script ships on the recovery UKI rather than as a documented procedure. This is the practical reading of that. Rollback means the filesystem is intact and `@` is merely bad, which is the case this covers.

Baking the script into the recovery initramfs through a custom mkinitcpio install hook would also survive an unreadable root filesystem. It was rejected as machinery out of proportion to the gain: a custom hook is one more thing that can silently stop being included when mkinitcpio changes, and a filesystem too broken to read is a job for the Arch ISO regardless.

Consequences:

- M1 delivers the script and proves the recovery UKI reaches a shell. M5 exercises the rollback itself.
- The recovery UKI carries every module rather than an autodetected set, so it can reach the disk on hardware the primary image was tuned for.
- Accepted limitation: a root filesystem too corrupt to read needs the Arch ISO. Document that in the rescue workflow rather than leaving it implied.

## D-015 Reaching a shell on the recovery UKI

**Status:** accepted
**Date:** 2026-08-27
**Affects:** `storage-boot.md`, M1, M5, D-011, D-014

The recovery UKI boots and reaches rescue mode, then refuses to open a shell.

Observed on a clean desktop VM at commit fc70e8a, on the serial console:

    [  OK  ] Reached target Rescue Mode.
    You are in rescue mode. After logging in, type "journalctl -xb" ...
    Cannot open access to console, the root account is locked

`rescue.target` hands over to `sulogin`, and `sulogin` refuses when the root
account is locked. A fresh Arch installation leaves it locked, and
`archwork-install.sh` never sets a root password, so this is the state every
machine this repository builds will be in.

This matters beyond M1. D-014 says M1 "proves the recovery UKI reaches a
shell", and it does not. D-011 kept systemd-boot over GRUB partly because "the
recovery UKI already covers the same need", and at present it covers nothing:
the operator gets a banner and a dead console.

Options:

1. Install a `rescue.service` drop-in setting `SYSTEMD_SULOGIN_FORCE=1`, so
   sulogin opens a root shell without a password.
2. Set a root password during installation, from the age-encrypted secret set
   or by prompting.
3. Give the recovery entry its own cmdline that bypasses `sulogin`, for
   example `init=/bin/bash`.

Accepted: option 1.

Root is unreachable behind LUKS2 already. Anyone who can boot the recovery UKI
has typed the passphrase, and D-008 confirms there is no TPM auto-unlock
before M10, so the passphrase is always a real prompt. A password on top of a
passphrase protects nothing and is one more secret to hold at the exact moment
the machine is broken. Option 2 also puts a second long-lived credential in
the secret set, which the `CLAUDE.md` guidance on keeping that set small
argues against. Option 3 skips the systemd rescue environment entirely, which
means no mounted filesystems and no journal, and D-014 wants the Btrfs top
level mounted from that shell.

The cost of option 1 is that `rescue.service` lives on the root filesystem and
is shared with the primary UKI, so forcing sulogin applies to both. Reaching
`rescue.target` from the primary entry still requires editing the kernel
command line at the boot menu, which is itself behind the LUKS prompt.

Consequences:

- `archwork-install.sh` writes `/etc/systemd/system/rescue.service.d/10-archwork-sulogin.conf`
  setting `SYSTEMD_SULOGIN_FORCE=1`.
- M1 exit criteria stay as they are. The test that found this stays, and the
  harness now fails the run on "the root account is locked" rather than timing
  out with no reason given.
- M5 exercises the rollback from that shell, so M5 depends on this too.
- The M10 Secure Boot work retests rescue, per D-008. Retest this drop-in then:
  Secure Boot changes what can reach the boot menu, not what sulogin does, but
  the rescue path is worth re-proving rather than assuming.

## D-016 Configuration model

**Status:** accepted
**Date:** 2026-08-28
**Affects:** `applications-tooling.md`, `storage-boot.md`, M2, M7

Ansible runs on the target machine with a local connection. Nothing in the build path requires a second machine.

A machine being installed cannot configure itself from the machine being installed, which raised whether to drive Ansible from the other workstation over SSH. Three things settle it against that, in increasing order of weight.

**Recovery.** Push means rebuilding the desktop needs the laptop alive. That is the same shape as fetching the age key from Vaultwarden, which D-006 rejected: a rebuild path depending on a second thing being up fails on the day you need it. It also has no answer for the first machine, or for both being down at once.

**One tested path.** M7 proves reproducibility through three clean rebuilds. If VMs are configured one way and hardware another, that test proves the wrong path.

**The wireless deadlock, which is what actually fixes the ordering.** A laptop with no wired connection has no network at first boot. The WiFi PSK lives in the encrypted secrets, which live in the repository, which cannot be cloned without network.

So the order is fixed rather than chosen:

1. The ISO has network. Install the base system, `ansible` and `age`, and clone the repository onto the target.
2. Reboot. There may be no network yet.
3. `bootstrap.sh` prompts for the age passphrase, decrypts the secrets, brings up networking, then runs `ansible-playbook` locally and can finally fetch packages.

`ansible` and `age` are therefore pacstrapped during install. Bootstrap cannot install what it needs before it has the network that needs it.

Rejected alternatives:

- **Push over SSH.** Above. This is what the M2 harness did until this decision, so `phase_reconcile` changes with it.
- **Both models supported.** Two connection models, two authentication stories, and M2 and M7 would each have to prove both. Twice the surface for a convenience.
- **Ansible inside the chroot during install**, so the machine boots already configured. The tempting shortcut, and it lies. `systemctl` cannot start units in a chroot, so service state cannot be verified and idempotence cannot be measured at all. Idempotence is M2's exit criterion. It would report success for work that never happened.

Consequences:

- `ansible_connection: local` goes in `group_vars/all.yml`. The installer already sets the host name to `hmlxdesktop02` or `hmlxlaptop01` and `inventory/hosts.yml` already names those hosts, so the committed inventory then works unchanged on hardware and in a VM with `ansible-playbook -l "$(hostname)" site.yml`. No synthetic inventory, no connection flags at the call site.
- The harness keeps SSH, but only as the terminal driving a machine nobody can physically touch. Ansible no longer travels over it.
- The installer clones the checkout it runs from rather than fetching fresh, so the installed system carries the commit that built it. The stock Arch ISO does not ship `git`, so step 1 installs it. Found on 2026-08-28 by running the path rather than reading it: the ISO carries curl, tar and `arch-install-scripts`, and no git. The same reasoning already governs `git archive HEAD` in the harness. It then points `origin` upstream, because a clone keeping its local origin works until the first `git pull`.
- The repository lives at `/home/<user>/src/ArchWork`, inside `@home` and so outside the rollback boundary. Inside `@`, a rollback would rewind the checkout at the moment it was being used to debug that rollback.
- `--authorized-key` stays a virtual-machine-only test affordance. With no push model, sshd has no place in the build path.
- Driving Ansible from another machine is not forbidden, but it is unsupported and untested. Nothing may come to depend on it.

This collides with nothing. D-015 is the recovery UKI shell decision, and D-016 supersedes no earlier decision.

## D-017 Sharing hardware with another operating system

**Status:** accepted
**Date:** 2026-08-28
**Affects:** `storage-boot.md`, M8

ArchWork takes a whole disk and owns the ESP on it. It does not share an ESP with another operating system, and it does not enumerate other operating systems in its boot menu yet. Choosing between installs is a firmware boot menu job for now.

The desktop hardware dual boots three systems: Kubuntu on `nvme1n1`, Windows 11 on `sdb`, and ArchWork on `nvme0n1`. Each keeps its own bootloader on its own disk. The two NVMe drives are the same model and size, a Samsung 970 EVO Plus 2 TB each, so the kernel names alone do not identify them: the Kubuntu root is serial S6P1NS0T304068E and the disk ArchWork is to take is serial S4J4NX0R804138P. Address it as `/dev/disk/by-id/nvme-Samsung_SSD_970_EVO_Plus_2TB_S4J4NX0R804138P` and confirm the serial in the installer's own partition table printout before answering its prompt. That instruction was unfollowable until 2026-08-30: the installer refused a by-id path, because `guard_is_whole_disk` looks the device up in `/sys/block` under its own name and a by-id path mangles into a name that is not there. It resolves the symlink first now, and the confirmation prompt shows both names.

On 2026-08-30 the check stopped having to be a matter of reading carefully. `--expect-serial` makes the installer read the target's serial and refuse unless it matches, so a mistyped device path becomes a refusal rather than a wipe.

It is offered rather than required. Requiring it would mean looking a serial up before every install on every machine, and the repository owner asked to keep the freedom to install wherever, so the flag names a disk per run rather than fixing one. Use it here: this is the machine where the neighbouring drive is the Kubuntu root, and `docs/first-install.md` carries the serial in the path and in the check so that either one being wrong stops the install. The installer already behaves this way, because it writes a fresh GPT with its own ESP to the device it is given and `bootctl install` only ever scans the ESP it installed to.

**What is on the target disk today, checked on 2026-08-29 rather than remembered.** `nvme0n1` is not empty. It carries five partitions: a 500 MB NTFS, a 1.8 TB NTFS, a 954 MB NTFS, a 100 MB EFI system partition and a 569 MB NTFS. That is a Windows installation with its own ESP and recovery partitions, plus the bulk of the data on the machine. Installing ArchWork there destroys all of it, which is the intent, and is the reason this paragraph exists rather than being left to the installer's confirmation prompt.

One prerequisite followed from that, and it has now been met. Windows also lives on `sdb`, and until 2026-08-28 that disk had no ESP of its own: one was created at `sdb3` and holds `Boot0000`. Because the disk about to be wiped carries an ESP too, Windows booting from `sdb` had to be proven before the wipe rather than discovered after it. **Confirmed by the repository owner on 2026-08-29: Windows boots from `sdb`.** The wipe no longer takes anything with it that has not been accounted for.

The NTFS data on the target disk was confirmed expendable the same day, so nothing needs pulling off it first. Worth stating plainly because it is the one irreversible step in a process that is otherwise repeatable: the first install destroys it and every install after that is free. The owner expects to reinstall several times, which is what this repository is for.

**The keyboard layout is a trap on the first install.** The installer writes `KEYMAP=uk` and puts `sd-vconsole` in the initramfs, so the LUKS prompt at every boot uses a UK layout. The Arch ISO boots US. A passphrase set on the ISO and typed back at the boot prompt therefore disagrees on `@ " # \ | ~`, which is an encrypted disk that cannot be opened by the person who just encrypted it. `docs/first-install.md` documented its way around that by running `loadkeys uk` before the installer. On 2026-08-31 the installer took the job: `set_console_keymap` loads `$KEYMAP` after the target is confirmed and before the disk is partitioned, so the layout the passphrase is set on is the layout the boot prompt uses. A missing or failing `loadkeys` stops the install, because the alternative is finding out at the first reboot, after the disk has been written. The guide now explains the trap without asking the operator to remember anything.

Two facts make the separation worth writing down rather than leaving implicit.

**A shared ESP is a shared failure.** The 1 GiB ESP the installer creates is sized for UKIs, and a UKI is large. An ESP that another installer also writes to is one Windows feature update away from a full filesystem or a rewritten boot entry, and the recovery UKI is exactly the thing that must still be there on the day something else has gone wrong.

**os-prober would undo D-011.** The conventional way to get a menu covering every install is GRUB with `os-prober`, which D-011 already rejected and re-rejected. Do not reach for it as a convenience here.

Deferred rather than rejected: adding `systemd-boot` loader entries for Kubuntu and Windows 11, so one menu covers all three. `bootctl` can chain a `.efi` on another ESP through a type 1 entry that names the other partition, and doing it by hand in the repository is compatible with D-011. It is not needed to install, so it is not M8 work. Nothing may make it a prerequisite for a rebuild.

Consequences:

- The installer keeps taking a whole disk. It gains no option to install alongside an existing operating system, and no option to reuse an ESP it did not create.
- `bootctl install` makes ArchWork the first entry in the firmware boot order. That is a side effect of installing, not a decision to be the default, and reordering with `efibootmgr` or the firmware menu changes it back.
- Before wiping a disk on shared hardware, prove the other systems boot without it. Observed on `hmlxdesktop01` on 2026-08-28: `efibootmgr -v` showed `Windows Boot Manager` registered against the ESP on `nvme0n1p4`, the disk ArchWork is to take, while the Windows install on `sdb` carried no ESP of its own. Wiping `nvme0n1` would have left a Windows install on disk with nothing to boot it.
- Resolved the same day: Windows on `sdb` was given its own ESP at `sdb3`, and `efibootmgr` now shows a `Windows Boot Manager` entry against it, ahead of the stale `nvme0n1p4` one in the boot order. That entry is what survives the wipe. Boot Windows from it once before `nvme0n1` is touched, because an entry that exists is not the same as one that works, and this is the last chance to find out cheaply.
- When the loader entries do arrive, they go in the repository as configuration like everything else, and a rebuild has to recreate them. An entry typed once into a live ESP is exactly the manual configuration the capture rule exists to prevent.

**Correction, 2026-08-28:** this entry first named the two NVMe drives the other way round. They are identical 2 TB Samsung 970 EVO Plus units, and the mistake pointed the wipe at the running Kubuntu system. Names replaced with serials above.

## D-018 Where AUR builds run, and as whom

**Status:** accepted
**Date:** 2026-08-28
**Affects:** `applications-tooling.md`, `storage-boot.md`, M2, M5

The devtools chroot lives at `/var/cache/archwork/chroot`, and builds run as a dedicated system account, `archwork-build`, which holds no privileges at all.

D-005 settled that AUR packages build in a clean chroot rather than on the workstation. It did not say where the chroot sits or which account drives it, and neither answer is obvious.

**Where.** `/var/cache` is `@var_cache`, which `storage-boot.md` puts outside the rollback boundary. A base-devel chroot is around a gigabyte of entirely reproducible content, so carrying it through every snapshot buys nothing. `/var/lib` was the alternative and is wrong twice over: it sits inside `@` by a constraint `CLAUDE.md` spells out, so the chroot would roll back with the system, and it would bloat every snapshot to do it.

**As whom.** `makepkg` refuses to run as root, so something in this chain has to be an unprivileged account. The administrator account is the obvious candidate and the wrong one: it logs in, has SSH access and runs the desktop session, and a build writing into its home is a standing reason to widen what that session can reach.

So the build gets its own system account, with a locked password, no authorized keys and no login route. It holds no privileges of its own and appears in no sudoers file. Ansible already runs the reconciliation as root, and root becomes another user without needing a rule.

`makechrootpkg` fits this exactly, once read rather than assumed. Its `check_root` returns immediately when `EUID` is 0, so the tool expects to be root and re-execs itself under sudo when it is not, and `-U` names the unprivileged account it drops to for the makepkg step.

Rejected alternatives:

- **Give the build account a passwordless sudoers rule.** This decision said to do that for several hours, on the belief that `makechrootpkg` refuses to run as root. It does not. The rule was never needed, and a privilege granted for a reason that turns out not to exist is the kind that stays forever.
- **Run the build as the administrator account.** Above.
- **Drive `mkarchroot` and `arch-nspawn` directly and skip `makechrootpkg`.** Reimplements the tool D-005 chose, and the reimplementation would have to track devtools rather than being carried by it.

Consequences:

- `@var_cache` now holds build state a rebuild recreates. Nothing may come to depend on the chroot surviving a rollback.
- The M5 update script builds AUR updates through this same chroot and this same account, per D-005.
- `archwork-build` stays unprivileged. If something later seems to need it in sudoers, read the tool first: this decision already made that mistake once.
- A half-built chroot blocks `mkarchroot`, which refuses a working directory that already exists. The role reports it and names the command to clear it rather than deleting it, because `@var_cache` is btrfs and the chroot is a subvolume, not a plain directory.

## D-019 Which daemons run, and where Tailscale belongs

**Status:** accepted
**Date:** 2026-08-28
**Affects:** `applications-tooling.md`, M2, M3

Docker starts on demand through `docker.socket`, not at boot. The administrator account joins the `docker` group. Podman gets no system daemon. Tailscale stays out of the M2 manifests and arrives at M3.

Raised while extending M2 from packages to service state. Two things the documents did not answer, and neither should be inferred from a package list.

**Do the container runtimes run at boot?** `applications-tooling.md` lists Docker, "required for managing existing Docker workloads, including the VPS", and Podman "so it can be learned and used alongside Docker". It says nothing about whether either daemon starts at boot, and the answer carries a security consequence rather than being a convenience: reaching a running Docker daemon means membership of the `docker` group, and that group is root without a password prompt.

Recommendation: enable `docker.socket` rather than `docker.service`, so the daemon starts when something first asks for it and is otherwise not running. Leave Podman alone, since rootless Podman needs no system daemon and that is most of why it is worth learning alongside Docker. Decide the `docker` group separately from the daemon: it is the part that actually widens what a compromised session reaches.

**Where does Tailscale belong?** It appears in `applications-tooling.md` as something NetworkManager must coexist with, in `security-power.md` twice, and in D-002's consequences, which put the verification in the M3 exit criteria. It is in no package manifest, so nothing installs it.

Recommendation: leave it to M3, and treat its absence from the M2 manifests as deliberate rather than an oversight, because M3 is where the exit criteria test it and installing a VPN daemon a milestone early proves nothing.

Both recommendations accepted by the repository owner on 2026-08-28, with the `docker` group added.

Consequences:

- `docker.socket` is enabled, `docker.service` is not. Nothing on the workstation may come to depend on a container being up before something asks for it, which rules out restart policies as a way of running anything that matters. If that becomes wanted, this decision is the thing to reopen.
- The administrator account joins the `docker` group, so it reaches the daemon without a password prompt, and the daemon is root. Accepted knowingly for a single-user workstation whose owner already holds sudo: it changes where the prompt is, not the ceiling. It does mean anything running as that account reaches root without asking, which is a real widening and the reason it is written down rather than assumed.
- Podman gets no system daemon and no group. Rootless Podman needs neither, and that is most of why `applications-tooling.md` wants it learned alongside Docker.
- Tailscale enters at M3, in that milestone's manifests, tested by that milestone's exit criteria.

One thing to carry into M3: D-002 has this repository mask `systemd-resolved`, and Tailscale's split DNS works best through it. That may be a real tension rather than a theoretical one, and M3 tests coexistence rather than assuming it.

## D-020 Three things M3 needs that no document names

**Status:** accepted
**Date:** 2026-08-28
**Affects:** `desktop-shell.md`, M3, M6

The M3 session manifest is otherwise fully specified: every package in it traces to `desktop-shell.md`, D-001, D-004 or D-012. Three things are required by the documents in prose but named by none of them, and `CLAUDE.md` forbids adding a package no decision document lists.

**A bar.** `desktop-shell.md` says M3 builds "a working desktop with no Quickshell in it: fuzzel, mako and a conventional bar", and that the fallback set stays installed after M6 so a broken Quickshell leaves an ugly desktop rather than an unusable one. It does not say which bar.

Recommendation: `waybar`. It is in `extra`, it is what most Hyprland setups use, and its configuration is a JSON and CSS pair that this repository can hold as dotfiles like anything else. The M3 exit criteria do not test a bar, so this is about the fallback set at M6 rather than about M3 working.

**A GTK theme.** `desktop-shell.md` says Kvantum is used "with a matching GTK theme". Kvantum themes Qt only, so without a GTK counterpart every GTK application stays light while the Qt ones follow the theme, which the M3 portal criteria will make immediately visible.

Recommendation: leave this open until the Kvantum theme itself is chosen, because "matching" is the requirement and neither is picked yet. It is the one of the three that most deserves being looked at rather than decided on paper.

**Fonts.** Nothing names any. A session with no font packages falls back to whatever came in as a dependency, which is how a desktop ends up looking wrong in a way nobody can quite attribute.

Recommendation: `ttf-dejavu` as the general fallback, `noto-fonts` and `noto-fonts-emoji` for coverage, and one monospace face for Kitty and the bar. All are in `extra`. Worth deciding before M3's first screenshot rather than after.

**Answered on 2026-08-28.** The bar is `waybar`, installed with the configuration it ships rather than a set of dotfiles: it is the fallback that M6 replaces, so effort spent styling it now is spent twice. The GTK theme stays open until the Kvantum theme it has to match is chosen.

**Fonts answered on 2026-08-29,** and the premise of the question was wrong. A document did name them: the application baseline the repository owner holds has a Fonts section, and this entry was written without it. The answer is that document's, not a recommendation: `noto-fonts`, `noto-fonts-emoji` and `noto-fonts-cjk` for Unicode, emoji and CJK coverage, `inter-font` as the UI face, `ttf-liberation` for metric compatibility with the common Microsoft faces, and `ttf-jetbrains-mono-nerd` as the terminal and editor face. All six are in `extra`.

A recommendation of `ttf-dejavu` briefly stood here and was wrong twice over: the baseline uses Liberation for that job, and it left out CJK and Inter entirely. It is recorded rather than quietly deleted because the lesson is about where the decision lived, not about a font. See D-024, which is about that document not being in this repository.

**The GTK theme answered on 2026-08-29,** which closes this entry. `materia-gtk-theme` and `kvantum-theme-materia`, `Materia-dark` and `MateriaDark` respectively, both in `extra`.

The recommendation had been to leave it until the Kvantum theme was chosen, because "matching" was the requirement and neither half was picked. Choosing a project that ships both settles the pair at once, which is why this is one answer rather than two. Neither is in the AUR, so neither takes the clean chroot path D-005 requires.

What the choice actually consists of, since it is less obvious than it sounds. Qt and GTK share no theming machinery at all: Kvantum styles Qt through `QT_STYLE_OVERRIDE`, and GTK applications read a GTK theme that knows nothing about it. So "matching" means either two themes chosen to resemble each other or one project shipping both, and it governs GTK 3 far more than GTK 4, because libadwaita applications follow their own stylesheet and take only the dark preference.

The visible consequence is the one the M3 captures kept showing: `xdg-desktop-portal-gtk` is a GTK 3 application, so the portal file chooser was coming up light against a dark desktop in every run. `dotfiles/gtk-3.0/settings.ini` is what fixes that.

The forward-looking consequence is M6. A theme with a defined palette gives Quickshell colours to match rather than inventing them.

**Judged and accepted by the repository owner on 2026-08-29,** from the captures saved against 0d20ddf. That is the verdict D-021 reserves for a person: the portal file chooser comes up dark and matching the desktop, where every run before it had that chooser light against a dark desktop. It is the only M3 criterion decided by looking rather than by asserting, and it is decided.

**The icon theme answered the same day: `papirus-icon-theme`, using `Papirus-Dark`.** Materia ships no icons, so without this the desktop falls back to whatever a dependency dragged in, which is how the fonts nearly went wrong. Taken "for now": it is the conventional pairing with a dark Materia rather than a considered match, and it is the part of this entry most worth revisiting when M6 puts a real shell on the screen.

None of these block the session manifest, which is complete without them. They block M3 looking finished.

## D-021 How the graphical session gets tested

**Status:** accepted
**Date:** 2026-08-28
**Affects:** `plan.md`, M3, M6

Log in at the real greeter by typing at the framebuffer from outside the guest, assert everything inside the session over SSH, and judge appearance by looking at saved captures rather than by asserting on pixels.

M3's criteria are about what a person sees: log in, open a terminal, launch something, lock, unlock, screenshot, open a file picker from GTK and from Qt. The harness drove a serial console, and none of that is reachable over one.

One criterion decides the shape. The greetd password must unlock the keyring through PAM with no second prompt (D-004, D-012), and proving that needs a real password going through the real PAM stack at the real greeter. Autologin, a unit that starts Hyprland, or `machinectl shell` all bypass the password, so none of them can prove it, and D-004 chose greetd over autologin for exactly this. greetd runs on a VT, so there has to be a display and a way to type at it.

So the harness gains a virtio VGA device and a QEMU monitor socket. `sendkey` types at the greeter and `screendump` captures the framebuffer, both from outside the guest, which means a machine that is quietly broken cannot report otherwise. Everything after login is asserted from inside over SSH with `hyprctl`, `grim`, `gdbus` and `secret-tool`, which is cheaper and more precise than reading pixels.

Rejected alternatives:

- **Assert only from inside the session.** Much less harness work, and it cannot start a session without bypassing greetd, so the keyring criterion becomes unprovable. That criterion is the reason D-004 accepted a second password prompt at every boot.
- **Guest-side input injection** with `wtype` or `ydotool`. Its distinctive ability, simulated typing, is what `sendkey` does anyway, except `sendkey` works before a session exists and needs nothing installed on the machine under test.
- **Text recognition on the captures**, so assertions could name what is on screen. Strongest evidence and the most machinery, with a new failure mode when it misreads. Revisit if looking at images by hand stops being enough.
- **Run the criteria by hand each rebuild.** The plan's wording allows it. It stops being true the first time nobody repeats it.

Consequences:

- The pixel check asserts only that something is drawn, as a count of pixels differing from the background. It does not read the screen and claims nothing about themes, fonts or layout. A check that claimed to verify theming and did not would be worse than none, and this repository has found several of those.
- Appearance is therefore judged by a person looking at the captures a run saves, recorded against a commit like any other evidence. That is a deliberate manual step, and the only one in the test ladder.
- The count is absolute rather than a ratio. The first version asked that the dominant colour cover under 99.5% of the screen; a real tuigreet measured 99.450% and the next run 99.453%, so the run-to-run variance was larger than the margin. `tests/unit/screendump.bats` holds those measurements.
- The kernel command line names both `tty0` and `ttyS0`, because a machine with a display would otherwise leave the serial console silent and the LUKS prompt unanswerable.

## D-022 Two M3 choices the documents leave to implementation

**Status:** accepted
**Date:** 2026-08-29
**Affects:** `desktop-shell.md`, M2, M3, M6

Both were reached while building the M3 desktop. Neither is answered anywhere, both had to be answered for a rebuild to produce a desktop at all, and the code now does what is recommended below so that M3 could be tested. Reversing either is a small change, and this entry exists so that the choices are visible rather than buried in a role.

**How user configuration reaches the machine.** `CLAUDE.md` gives `dotfiles/` its place in the repository and says nothing about how a file there becomes a file in `~/.config`. The two answers are copying, which Ansible does natively, and linking the clone D-016 already puts in the user's home directory.

Recommendation: link. An edit made at the machine is then an edit to the repository, so `git status` in the clone shows what was changed at 23:00 on a Tuesday, and Hyprland reloads a saved file immediately. Copying leaves the two diverging silently until the next rebuild throws the local changes away, which for a personal workstation is the failure that actually happens. The cost is that the desktop depends on the clone staying where it is: delete it and the configuration goes with it.

**Whether tailscaled runs at boot.** D-019 puts Tailscale in M3 and the M3 criteria say it "comes up", which implies a daemon that starts by itself, but D-019 answered the same question for Docker explicitly rather than leaving it implied, and a VPN daemon deserves the same treatment.

Recommendation: enable `tailscaled.service`. Unlike `docker.socket` this widens nothing on its own: the daemon carries no traffic until something signs it in, and the auth key that would is one of the secrets D-006 has yet to bring. A machine that has to be told to start its own network every boot is a machine that will be found offline.

Neither blocks M3. Both should be confirmed or reversed before M7 treats the rebuild as the thing being proven.

**Both confirmed by the repository owner on 2026-08-29**, as built. Status accepted.

Consequences:

- The desktop's configuration is the clone. Deleting `~/src/ArchWork` takes the Hyprland configuration with it, and an edit made at 23:00 on a Tuesday shows up in `git status` rather than being lost at the next rebuild.
- `tailscaled.service` is enabled. The daemon starts at boot and carries nothing until an auth key signs it in, which is a D-006 secret that has yet to arrive.

## D-023 Which applications prove the portal file picker, and the environment they need

**Status:** accepted
**Date:** 2026-08-29
**Affects:** `desktop-shell.md`, M3

M3 asks that "a file picker opens from a GTK application and from a Qt application". No application on an ArchWork machine could open one: the session manifest is a compositor, a terminal, a launcher, a bar, a lock screen and a notifier, and none of them has a file to choose. The criterion was untestable rather than failing, which is worse, because a run could pass without ever touching the code path.

The applications are `pdfarranger` for GTK and `kvantummanager` for Qt. Neither is installed for the test alone: `applications-tooling.md` already lists PDF Arranger, so this decides where it lands rather than adding it, and Kvantum Manager arrives inside the `kvantum` that the theming criterion needs anyway.

Rejected: toolkit demo applications such as `gtk3-demo`. They would be honest test scaffolding and would need a decision document to name a package that exists for no other reason, which is a worse trade than using two applications the workstation wants regardless. Also rejected: narrowing the criterion to a `gdbus` ping of the FileChooser interface. `assert-m3.sh` already pings the portal, and that check stays, but it says the portal is reachable and nothing about whether a picker opens.

The environment matters more than the applications. Two settings are needed and one of them contradicts the usual advice:

- `GTK_USE_PORTAL=1`. Without it a GTK application opens its own chooser, which looks the same on screen and proves nothing about `xdg-desktop-portal-gtk`.
- `QT_QPA_PLATFORMTHEME=xdgdesktopportal` with `QT_STYLE_OVERRIDE=kvantum`. Setting the platform theme to `kvantum`, which is what most Kvantum instructions say, hands Qt its own file dialog and takes the portal out of the path. Splitting the two keeps the portal drawing dialogs and Kvantum painting widgets, so the picker criterion and the theming criterion stop competing.

Consequences:

- Both criteria can be tested by the same session. Before this they could not both hold.
- `phase_portals` in the harness opens each application from the launcher, presses Ctrl+O, and asserts a window appears that does not belong to the application that asked for it. That last part is what distinguishes a portal dialog from an application's own.
- Ctrl+O is a convention rather than a documented binding for either application, and whether each honours it is unverified until a run says so. The check therefore prints every window the compositor has when it fails, so one run names the right key instead of leaving the next to guess.
- The window match is loose, on class and title. It can be tightened once a run has shown what the portal actually calls its chooser. Guessing the exact string now would fail a run for the wrong reason.

**Amended on 2026-08-29, after the run that was supposed to confirm it.** The diagnostic above did its job and both halves were wrong.

Kvantum Manager binds no accelerator. It opened, Ctrl+O did nothing, and the capture shows why: its only file dialog sits behind a "Select a Kvantum theme folder" button, and it chooses a directory rather than a file. There is no key to press. It is replaced by `okular`, which the baseline names, which is Qt, and whose Ctrl+O is the standard KDE binding. The cost is 19.5 MiB and a KDE dependency chain in a session set meant to stay small, which is worth it for a criterion that can actually be tested. This was the repository owner's question 4, recommended and not yet answered when the change was made; reversing it is one line in the manifest and one in the harness.

PDF Arranger opened perfectly and the harness looked for the wrong window. Its class is `com.github.jeromerobert.pdfarranger`, not `pdfarranger`, which is the reverse-DNS application id rather than the binary name. It also greets a new profile with a modal about the limits of cropping, and a modal swallows the accelerator, so the harness now dismisses it before pressing anything.

Both facts came from the window list the failure printed rather than from another guess, which is the whole reason that dump exists.

**The GTK half passed on the next run.** Ctrl+O in PDF Arranger opened the portal chooser: Recent, Home and Other Locations down the side, the file columns across, an "Open files read-only" box. That is `xdg-desktop-portal-gtk` drawing it, which is what `GTK_USE_PORTAL=1` was set for, and it is the first time this criterion has been shown rather than assumed.

Okular then failed on exactly the mistake PDF Arranger had already taught: its class is `org.kde.okular`, not `okular`. Both applications name their windows by application id rather than by binary, which is what a Wayland client does. Anything added to this phase should start from the application id and confirm it against a window list, rather than assuming the two match. They rarely do.

The captures also show what the assertions cannot: the portal chooser comes up light against a dark desktop, because the GTK theme is the part of D-020 still open.

## D-024 The application baseline is not in this repository

**Status:** accepted
**Date:** 2026-08-29
**Affects:** `applications-tooling.md`, `CLAUDE.md`, D-006, D-019, D-020, M8, M9

D-020 asked which fonts to install and said "nothing names any". That was wrong. The repository owner holds an application baseline with a Fonts section, and this repository does not contain it. `docs/decisions/applications-tooling.md` is a much shorter document that overlaps it in places and disagrees with it in others.

The immediate cost was a font set invented on 2026-08-29 that named `ttf-dejavu`, which the baseline does not use, and omitted CJK coverage and the UI face entirely. That is now corrected. The cost worth preventing is the next one: an agent reading only what is in this repository cannot tell that a fuller document exists, and `CLAUDE.md` tells it not to add a package no decision document lists. It will keep inventing answers that already have them.

Three disagreements matter more than the fonts, and none should be settled by an agent picking whichever document it read last.

**Docker and Podman.** Answered on 2026-08-29 and moved to D-025, which supersedes the container half of D-019. Podman is the engine, Docker is a client for remote systems, and the `docker` group is removed rather than merely no longer added.

**git-crypt.** The baseline lists it under Git. `CLAUDE.md` says repository secrets use age and nothing else, and that git-crypt is not used. D-006 decided that.

Recommendation was to drop it from the baseline. **Answered on 2026-08-29: keep it.** It is not a contradiction, it is two different questions that were being read as one. git-crypt is installed on the workstation because other repositories the owner works on use it. Nothing about that makes it a mechanism for *this* repository's secrets, which remain age and nothing else. The wording in `CLAUDE.md` and here now says which of the two it means, so that a future reader finding `git-crypt` in a package manifest does not conclude the rule was broken.

The owner added "perhaps I need to question it", about those other repositories. The comparison that matters there: git-crypt is transparent, so a pattern that does not match, or a file added before the filter was configured, commits plaintext, and history keeps it. It also encrypts deterministically, so identical content produces identical ciphertext and the history leaks when a secret reverts to an earlier value, and revoking access means rewriting history. Against that, its convenience is real when secrets are edited constantly by several people. That is a decision for those repositories rather than this one, and it is recorded here only because the question was asked.

**SOPS.** The baseline lists it for encrypted configuration. D-006's "age only" was about repository secrets, and SOPS is a different job, so this may be no contradiction at all.

Recommendation was to leave it out. **Answered on 2026-08-29: not in scope.** It stays off the workstation, and D-006 is unchanged beyond the wording clarification above. Worth reopening only if hand editing `.age` files becomes a real irritation, in which case SOPS with the age backend keeps the crypto and adds reviewable diffs, which is a smaller change than it sounds.

Recommendation for the entry as a whole: bring the baseline into `docs/decisions/` as the applications document, with `applications-tooling.md` either replaced by it or reduced to the decisions that are genuinely about this repository rather than about which applications the owner wants. Where the two disagree, the baseline wins except on git-crypt.

**Answered on 2026-08-29.** The baseline is now `docs/decisions/applications.md`, carried in whole. `applications-tooling.md` keeps only what is a decision about this repository rather than a list of what the owner wants installed, and points at the new file for the list. Where they disagreed, the baseline won, and git-crypt turned out not to be a disagreement at all.

This entry stays open on one point, and reading the plan for it made it sharper rather than softer: **no milestone installs the bulk of the baseline.**

M4 is power, M5 is update and rollback, M6 is Quickshell, M7 is the rebuild proving run, M8 and M9 are deployments to physical machines. M7's wording is "bare ISO to full desktop", which is the only place the applications could be implied, but its exit criteria are about three consecutive rebuilds and their timings, not about what is on the finished machine. M8 names Steam, OpenDeck and Xbox controller support because those are desktop-profile differences, not because it is the applications milestone.

So a browser, an editor, an office suite and everything else in `applications.md` would arrive by nobody's decision, at no stated point, most likely as a scramble during M8 when the machine is meant to be in daily use.

Recommendation, and this one is a change to the plan rather than to a document, so it needs the repository owner: add an applications milestone between M6 and M7, or widen M7 with an exit criterion that names the manifests as complete against `applications.md`. The second is cheaper and keeps the milestone count where it is. Either way M7 should not be able to pass while "full desktop" means a compositor and a terminal.

**Answered on 2026-08-29: widen M7.** It now says what "full desktop" means, and carries two more criteria. The manifests must account for every application in `applications.md`, or name what is deliberately left out and why, because an entry that is deferred on purpose is fine and an entry nobody has looked at is not. And nothing needed to reach that desktop may have been installed by hand, checked the way M2 checks it: reconcile twice and require the second run to change nothing.

This closes D-024.

There is a reason to prefer doing it before M7 rather than during M8. M7 proves that three consecutive rebuilds land the same machine. If the applications are not in the manifests by then, M7 proves repeatability of something that is not the workstation, and the first thing installed by hand afterwards makes it untrue.

## D-025 Podman is the desktop container engine, and Docker is a client

**Status:** accepted
**Date:** 2026-08-29
**Affects:** `applications-tooling.md`, D-019, M2

Supersedes the container half of D-019, which read the application baseline backwards.

Podman is the container engine on this workstation, chosen over Docker deliberately and partly to gain practical Podman experience. Docker stays installed as tooling for remote Docker systems such as the VPS. Confirmed by the repository owner on 2026-08-29, from the baseline D-024 raises.

D-019 had it the other way round, and the consequence was not cosmetic. It enabled `docker.socket` and put the administrator account in the `docker` group, and wrote down that the group reaches a root daemon with no password prompt. That widening was accepted on the understanding that Docker was the engine the workstation used. It was not, so the machine carried a root-equivalent group for a daemon nothing was meant to talk to.

Consequences:

- No `docker.socket`, and nobody in the `docker` group. Reconciliation actively removes that group membership rather than only stopping adding it, because a machine built under D-019 already has it and would otherwise keep it for its life while every document said otherwise.
- Rootless Podman needs no daemon and no group, so there is nothing to enable and nothing to widen. `podman-compose` joins the manifest, which the baseline names and no manifest had.
- Docker's daemon is installed and never started. Arch ships no separate client package, so the CLI arrives with a dockerd that this machine does not run. Verified against the package repositories rather than assumed: there is no `docker-cli` in `extra`.
- Reaching a local Docker daemon now needs sudo, deliberately. If something on this workstation ever genuinely needs one, reopen this decision rather than restoring the socket, because the group comes back with it.
- D-019's Tailscale half stands unchanged.

## D-026 Hyprland says we start it the wrong way, and that our config format is going away

**Status:** accepted
**Date:** 2026-08-29
**Affects:** `desktop-shell.md`, D-004, M3, M5, M6

Neither of these was looked for. Both were read off a screen capture the M3 run saved on 2026-08-29, in two notifications Hyprland drew on its own desktop.

**"Hyprland was started without start-hyprland. This is strongly discouraged unless you are in a debugging environment."**

D-004 has greetd run `tuigreet --time --cmd Hyprland`, which is what every Hyprland and greetd guide said when it was written. The package now ships `/usr/bin/start-hyprland` and a `hyprland-uwsm.desktop` session alongside `/usr/bin/Hyprland`, and the compositor tells anyone who starts it directly that they should not. Verified against the package file list rather than inferred from the message.

Recommendation: switch the greeter's command to `start-hyprland` and re-run the M3 criteria. The reason to change it is that a wrapper the project tells you to use is where session setup will keep landing, and a workstation that skips it drifts further from the supported path every release. The reason to be careful is that the wrapper's job is precisely the session environment, so it can move the keyring, the portal and the D-Bus activation environment, which are three criteria that currently pass. That makes it a change to make deliberately and test, not one to slip in. M3's criteria are the test.

**"You are using the .conf config format, support for which will be removed in Hyprland 0.57."**

`extra` has 0.56.2 today, so the release that drops the format is the next one. Every file in `dotfiles/hypr/` is in it. On a rolling distribution this arrives on its own schedule rather than ours, and a desktop that stops reading its configuration on an ordinary update is exactly the failure this repository exists to prevent.

Recommendation: do not chase it before the first hardware install, and do not let it arrive unannounced either. What the replacement format is, and whether a converter ships, needs establishing before 0.57 lands. This also argues for the M5 update path surfacing deprecation warnings rather than discarding them, because this one was found by looking at a screenshot, which is not a process.

**Both answered by the repository owner on 2026-08-29.** Switch the launcher before the first hardware install if the M3 criteria still pass with it, and migrate the configuration format now rather than at M5.

What the launcher change is: greetd's session command becomes `tuigreet --time --cmd start-hyprland`. The wrapper carries crash recovery and a safe mode that starts a default configuration when the user's own is broken, which is worth having on a machine whose configuration is a git clone that an edit at 23:00 can break. It needs no new package: `hyprland-guiutils`, which safe mode uses, is already a hard dependency of `hyprland`.

What the format change is, and it is larger than it sounds: hyprlang is not being tweaked, it is being replaced by Lua. `~/.config/hypr/hyprland.lua` holds a script that calls into an `hl` API rather than a list of assignments. `hl.config({ general = { gaps_in = 4 } })` where the old file said `general { gaps_in = 4 }`, `hl.bind("SUPER + Q", hl.dsp.window.close())` where it said `bind = $mod, Q, killactive`, and `hl.on("hyprland.start", ...)` where it said `exec-once`. Upstream has already deleted `example/hyprland.conf` from its repository.

The dispatcher names were taken from `src/config/lua/bindings/LuaBindingsDispatchers.cpp` and the shape of the file from upstream's `example/hyprland.lua`, rather than guessed from the old names. They do not map one to one: `killactive` is `hl.dsp.window.close()`, `togglefloating` is `hl.dsp.window.float({ action = "toggle" })`, and `movetoworkspace` is `hl.dsp.window.move({ workspace = n })`.

Consequences:

- `dotfiles/hypr/hyprland.conf` is gone and `dotfiles/hypr/hyprland.lua` replaces it. The dotfiles role links the directory rather than the file, so nothing else changes.
- `hyprlock.conf` stays as it is. The deprecation notice came from Hyprland about its own configuration, and hyprlock is a separate program that still reads hyprlang. If that changes it will announce itself the same way, which is an argument for the M5 update path surfacing deprecation warnings rather than discarding them.
- Both changes are tested by the M3 criteria rather than by inspection. A wrong dispatcher name is a keybinding that does nothing, and the harness presses every keybinding it depends on.
- The capture that carried both notifications is the first evidence in this repository that came from looking at the screen rather than from an assertion. D-021 argued for saving captures and having a person look at them. This is what that was for.

## D-027 The desktop's GPU is NVIDIA, and nouveau cannot run the M3 session on it

**Status:** accepted
**Date:** 2026-08-30
**Affects:** `desktop-laptop-differences.md`, M3, M8

The first login attempt on `hmlxdesktop02` failed: greetd accepted the password, Hyprland started, and tuigreet redrew the username prompt, which looked exactly like a rejected password. `journalctl` from a text console told a different story: `start-hyprland` reported `Hyprland exit cleanly` after Aquamarine logged `drm: Starting backend for /dev/dri/card0, with driver nouveau` and `WARN drm: failed to set DRM_CLIENT_CAP_ATOMIC, falling back to legacy`.

Every M3 run before this one was against a VM's virtual head, so nothing in this repository had ever asked what GPU the desktop hardware carries. It carries a discrete NVIDIA GeForce RTX 3060 (12 GB, confirmed by the machine's owner), driven by `nouveau` because no package here installs anything else. `nouveau` falls back to legacy (non-atomic) KMS on this card, and Hyprland cannot get a working render context from that: it starts, fails to render, and exits cleanly, which is indistinguishable at the greeter from a rejected login.

Two driver families were weighed. `nvidia-open`, NVIDIA's open-source kernel modules, only supports Turing and later; the proprietary `nvidia` package is required on anything older. Confirmed against NVIDIA's own compatibility list: Ampere, which the RTX 3060 is, is on the open-modules side of that line. The repository owner chose `nvidia-open` on 2026-08-30, once the GPU model was known.

What the fix is, and what it deliberately does not touch: `nvidia-open` and `nvidia-utils` join `archwork_packages_profile` on the desktop, gated behind a new `archwork_nvidia_gpu` group variable (`CLAUDE.md` bars hostname conditionals in roles, so the packages role reads a variable rather than asking which machine it is). The packages role then writes `/etc/modprobe.d/nvidia.conf`, blacklisting `nouveau` and setting `nvidia_drm modeset=1`, and regenerates the initramfs so the blacklist reaches the `modconf` hook there too. That gets NVIDIA modesetting working at the normal (post-initramfs) point in boot, which is all M3 needs.

Deliberately not done: adding the NVIDIA modules to `mkinitcpio.conf`'s `MODULES=` for truly early KMS, and adding an `nvidia-drm.modeset=1` kernel parameter to `/etc/kernel/cmdline`. Both files are written once by `scripts/archwork-install.sh` at install time and never touched by Ansible reconciliation afterwards (`configure_initramfs()`), which is a real gap in what reconciliation can reach on an already-installed machine. Late KMS through `modprobe.d` sidesteps that gap rather than closing it, and is enough to get login working. Whether reconciliation ever needs to manage `mkinitcpio.conf` and the kernel command line is an open question this decision does not answer, and is left for whoever next needs early KMS for a real reason.

Consequences:

- `archwork_nvidia_gpu: true` on the desktop profile, `false` by default in `group_vars/all.yml`. A second desktop with a different GPU would need its own value; nothing here assumes only one ever exists.
- The change needs a reboot to take effect: `nouveau` already holds the card, and blacklisting it does nothing until the kernel starts fresh without loading it.
- Not yet run on `hmlxdesktop02` as this is written. `docs/STATUS.yml` carries the blocker until someone reruns the playbook, reboots, and confirms Hyprland actually reaches a session, per the evidence rule in `CLAUDE.md`.
- `desktop-laptop-differences.md` does not gain a GPU row for this. Its table tracks profile-level differences already expressed as group variables and package lists, which is what `archwork_nvidia_gpu` and the two packages above already are.

## D-028 Two things M4 needs that no document names

**Status:** accepted
**Date:** 2026-08-30
**Affects:** `security-power.md`, `desktop-shell.md`, M4, M6

The same shape as D-020: `security-power.md` and `desktop-shell.md` between them fully specify what M4 has to do, dim at 5 minutes, display off at 15, sleep at 30, a sleep inhibit control offering 1h/2h/4h/indefinite that leaves dim and display-off alone, but neither document names the tool that watches for idle or the interface the inhibit control takes before Quickshell exists to hold it.

**An idle daemon.** Hyprland does not watch for idle time itself.

Recommendation: `hypridle`, the Hyprland ecosystem's own companion for this, the same way `waybar` was the unnamed but obvious pick for M3's bar. It still reads the hyprlang config format rather than Lua: it is a separate binary from Hyprland, and D-026 only migrated `hyprland.conf` itself, the same reasoning that already left `hyprlock.conf` alone. `brightnessctl` runs as its dim command; it finds no backlight device on the desktop's external monitors and no-ops there, which is fine, since `security-power.md` states the timings, not that dimming has a visible effect on every profile, and hypridle does not care whether the command an `on-timeout` runs succeeds.

**What the sleep inhibit control is, before Quickshell owns it at M6.** `desktop-shell.md` gives the eventual UI to Quickshell and says nothing about M4's own version, the same gap M3 had for a launcher, which fuzzel filled without becoming the permanent answer.

Recommendation: `scripts/archwork-inhibit`, a plain command, not a GUI: over-building an interim widget here is exactly the effort D-020 warned M6 would throw away. It holds the lock through a transient `systemd-run --user` unit rather than a PID file, because `systemctl` already knows how to start, stop and describe one. `systemd-inhibit --what=sleep --mode=block` is what actually holds the lock; hypridle's own `systemctl suspend` at the 1800-second listener is what a held lock refuses, which is the entire mechanism behind "sleep is inhibited, dim and display-off are not." Nothing about the inhibitor touches those two listeners, so there is no separate code path to keep in sync with `security-power.md` if the timings ever change.

**Implemented directly, on the same basis as D-020's `waybar` and font recommendations.** Both are established, close to zero-controversy technical picks rather than genuine forks needing the owner's judgement, unlike D-027's driver choice, which depended on hardware knowledge only the owner had.

Consequences:

- `hypridle` and `brightnessctl` join `archwork_packages_session` in `group_vars/all.yml`, shared across both profiles per `security-power.md`.
- `dotfiles/hypr/hypridle.conf` carries the three listeners. Each `timeout` is measured from the same last-activity clock independently: 300, 900 and 1800 seconds, not one chained on top of the last.
- `hyprland.lua`'s `hyprland.start` handler execs `hypridle` alongside `waybar` and `mako`, the same fallback-set pattern D-020 already established.
- A new `power` Ansible role installs `scripts/archwork-inhibit` to `/usr/local/bin`. It is the one piece of M4 that is genuinely new code rather than configuration, so it is the one covered by unit tests (`tests/unit/archwork-inhibit.bats`), with `systemctl` and `systemd-run` stubbed rather than exercised against a real logind session.
- The automated check the last exit criterion asks for is `tests/vm/assert-m4.sh` and the `power` phase in `tests/vm/run-install.sh`, added on 2026-08-31. It measures rather than reads: each observation records the seconds since the keystroke that reset the idle clock, and the assertion is a window around the configured number, with the lower bound doing as much work as the upper. A listener that fires early is as wrong as one that never fires, and only the lower bound catches it.
- The sleep timing is measured from outside the guest, by `tests/vm/suspend-watch.py` against the QEMU monitor. A machine cannot time its own suspend: the last thing it does before S3 is stop running.
- One criterion a VM cannot settle. Dimming has no observable effect where there is no backlight device, which is every VM and the desktop's external monitors both. `assert-m4.sh` reports it as a skip, counted and printed apart from the passes, rather than quietly counting the listener's presence in the file as the timing being met. The laptop panel is the only thing that can prove that one.
- Still not run. The check exists and its own helpers are covered by `tests/unit/m4-checks.bats` and `tests/unit/suspend-watch.bats`, which need no VM. The 65 minute run against a real machine has not happened, so nothing here is evidence that the timings hold. `docs/STATUS.yml` carries that as the blocker.

## D-029 The application baseline reaches the manifests

**Status:** accepted
**Date:** 2026-09-01
**Affects:** `applications.md`, `desktop-laptop-differences.md`, D-024, M7

D-024 closed by widening M7: the manifests must account for every application in `applications.md`, or name what is left out and why. This entry is that accounting, done now rather than at M7.

The reason for doing it early is the one D-024 already gave, sharpened by using the machine. `hmlxdesktop02` logged in for the first time on 2026-08-30 and the desktop on it was a compositor, a terminal, a launcher, a bar, a lock screen, a notifier, and the two applications M3 needed to open a portal file picker from. There was nothing to do with it. M7 proves three consecutive rebuilds land the same machine, and until the applications are in the manifests that would prove repeatability of something that is not the workstation.

Every package name here was checked against the official repository search API and the AUR RPC on 2026-09-01, rather than recalled. Four names that would have been wrong from memory: `bind` carries `dig` rather than a `bind-tools` package, `kubectx` ships `kubens` too, `memtest86+-efi` is the build a UEFI machine with systemd-boot can launch, and Mission Center is in `extra` as `mission-center` rather than in the AUR.

What the lists are, and why there is a new one:

- `archwork_packages_applications` in `group_vars/all.yml`, 84 packages from the official repositories, on both profiles. It is separate from `archwork_packages_shared` for the same reason `archwork_packages_session` is: the two answer different questions. `shared` is the tooling the platform needs to build and maintain itself, and a rebuild that dropped `applications` would still be a working machine, just not the workstation.
- `archwork_packages_aur`, 9 packages, shared. The `-bin` variants are deliberate where upstream ships a binary: building Chromium or VS Code from source in the D-005 chroot costs hours and produces the same program.
- `archwork_packages_gaming` and `archwork_packages_ai` on the desktop, empty on the laptop, plus `archwork_packages_aur_profile`. These are the two application rows in `desktop-laptop-differences.md`. The laptop file sets them to `[]` rather than omitting them, so the difference is visible in the file rather than implied by an absent variable.

**Multilib, which no document had to name until now, and which took two goes.** Steam is a `multilib` package and the stock `pacman.conf` ships that repository commented out, so the gaming profile could not install the one application the differences table names for it. The packages role now uncomments the pair, gated on `archwork_multilib`, which is true on the desktop and false everywhere else. It runs before the database refresh, because a cache refreshed without multilib does not know about the packages the install then asks for. The laptop does not get a 32-bit repository it would never use.

That was not sufficient, and a run on 2026-09-02 found out three minutes in:

    error: 'steam': could not find or read package

`ansible-playbook --check` changes nothing by definition, so the multilib task does not run during a dry run, so pacman still does not know about `steam`, so the check fails against a machine that is perfectly fine. M2 requires that check to pass, which makes this a real blocker rather than a cosmetic one.

So the installer enables multilib too, on the desktop profile, right after `pacstrap`. Having both do it is deliberate rather than duplication: D-027 observed that files written only by the installer are a real gap in what reconciliation can reach afterwards, and a machine installed before this existed still needs to converge. The installer's `sed` is anchored on the commented pair the stock file ships, is idempotent, leaves `[multilib-testing]` alone, and fails loudly if the section is not the stock one, because the alternative is matching nothing and failing later at pacman with no clue why. `sed` rather than `perl`: this runs on the Arch ISO, which carries `sed` in base and does not promise `perl`.

**Deliberately left out, which the M7 criterion asks for by name.**

- **Odysseus.** `applications.md` says the exact project or package still needs identifying. Nothing to install.
- **The personal applications**, AI Agent Manager, Game-on-itor and Kitchen Sync. `applications.md` already separates them and says they need reworking, packaging and an ArchWork-specific installation mechanism. None exists, so there is nothing a manifest could name.
- **Spotify, WhatsApp, email and calendar.** Web or PWA by decision, so no package is the correct answer rather than a gap.
- **Everything under "Explicitly not included by default".** Honoured as written; nothing from that list was added.
- **Quickshell and Satty.** M6 installs them, and installing a shell a milestone early proves nothing, which is the reasoning the manifests already carry for Tailscale arriving at M3 rather than sooner.
- **Codex CLI, Python 3.13's explicit management, the Epson scanner driver and libvirt's own dependencies.** These are four open questions rather than four decisions, and they are below rather than answered here.

**What this does not prove.** Nothing in this entry has been run. It is 93 new packages across two profiles, and the things that could go wrong with it are a name that resolves to a different program than intended, a build that fails in the chroot, an AUR package that needs an interactive prompt paru cannot answer, and a reconcile that is no longer idempotent because one of these writes to its own configuration on first run. The M2 test is the one that catches the last of those: reconcile twice, and require the second run to change nothing. `docs/STATUS.yml` carries this as unproven until a VM run says otherwise.

Also unproven and worth saying plainly: the HP LaserJet Pro MFP M28w has its whole stack in the manifests now, CUPS, HPLIP, SANE and sane-airscan, and none of it has been tested against the printer. `applications.md` only says the stack is *expected* to provide the integration. The Epson has no driver in the manifests at all, for the reason in question 4 below.

**Four questions this entry raises and does not answer.** Each is a genuine fork rather than an obvious pick, so none was decided here (`CLAUDE.md`: raise it, recommend, stop).

1. **Codex CLI has no official package.** `applications.md` names it alongside Claude Code. Claude Code is in the AUR as `claude-code` with 91 votes; Codex has no equivalent. The candidates are `openai-codex-bin` (25 votes, described as auto-updated) and `codex-app-unofficial` (8 votes). Both are unofficial repackagings of a binary, and an auto-updating AUR package is a build script that fetches whatever upstream published, on a workstation, as part of an unattended reconcile.

   Recommendation: leave it out of the manifest and install Codex through npm in the user's own environment, the way its upstream documents. The reason is not the vote count, it is that `paru --chroot` on an auto-updated PKGBUILD makes an unattended rebuild depend on an unpinned third party, and D-005 routed AUR builds through a clean chroot precisely to bound what a package build can touch. If it should be in the manifest anyway, `openai-codex-bin` is the one.

   **Still open on 2026-09-01.** The other three questions here are answered; this one was asked back rather than decided, so Codex is in no manifest and nothing installs it. Whichever way it goes, it changes one line.

2. **Python 3.13, "managed explicitly rather than depending on Arch's rolling system Python staying at 3.13".** `applications.md` asks for this and names no mechanism. The system `python` package is whatever Arch has moved to, which is exactly what the line is written against. The options are an AUR `python313` alongside the system interpreter, or a version manager such as `uv`, `mise` or `pyenv` owning it in the user's home.

   Recommendation: `uv`, which is in `extra`. It pins and fetches interpreters per project rather than installing a second system-wide Python that pacman would then also want to upgrade, and it is the option that does not put two interpreters on `PATH` and hope the right one wins. This is a real choice about how the workstation does Python, though, not a package name, which is why it is here.

   **Answered on 2026-09-01: `uv`.** It is in `archwork_packages_applications`. Nothing yet uses it to pin 3.13, so this decides the mechanism and not the pinning: the first project that needs the interpreter is what will show whether it holds.

3. **libvirt needs two packages `applications.md` does not name.** `virt-manager` is listed and called out as useful for clean ArchWork rebuild VMs, and that is the use that breaks: libvirt's default NAT network needs `dnsmasq`, and booting a UEFI guest needs `edk2-ovmf`. Neither is a hard dependency, so the stack installs and then cannot do the thing it was installed for. `CLAUDE.md` bars adding a package no decision document lists, which is why they are not in the manifest.

   Recommendation: add both, and treat this as `applications.md` naming a capability rather than a package list. Every ArchWork test VM in this repository is a UEFI guest, so a virt-manager that cannot boot one is not the tool that was asked for.

   **Answered on 2026-09-01: add both.** `dnsmasq` and `edk2-ovmf` are in `archwork_packages_applications`. `applications.md` is not amended for this: it names what the workstation is for, and the packages a listed capability needs are a manifest question.

4. **The Epson FastFoto FF-680W driver.** `epsonscan2` is in the AUR (26 votes) and is the obvious candidate, but `applications.md` is explicit that driver-level support is not sufficient: the FastFoto-style workflow, batch ADF scanning, duplex, mixed photo sizes, automatic filenames, has to be tested before scanning counts as solved.

   Recommendation: add `epsonscan2` when the scanner is next to the machine and the workflow can actually be tried, rather than now. Adding it now puts a scanner driver on the laptop for hardware it may never meet, and would let a manifest entry stand in for a test that has not happened, which is the thing the evidence rule in `CLAUDE.md` exists to stop.

   **Answered on 2026-09-01: add it now, so the workflow can be picked up later.** `epsonscan2` is in `archwork_packages_aur`. The recommendation to wait was overruled on the grounds that having the driver there already is what makes the test easy to start. The caution it carried still stands and is worth repeating rather than dropping: the package being installed is not evidence that scanning works, and the FastFoto workflow, batch ADF, duplex, mixed sizes and automatic filenames, remains untested.

## D-031 paru cannot install as root, and the AUR path had never run

**Status:** open, and it blocks the application manifests
**Date:** 2026-09-02
**Affects:** D-005, D-018, D-029, M2, M5, M7

The first reconcile ever to install AUR packages failed at the last task of the aur role:

    error: can't install AUR package as root

The role runs `paru --sync --chroot` with `become: true`, and paru refuses to run as root. It has always done that. The task never noticed because `archwork_packages_aur` was `[]` from M2 until D-029, and the task is guarded by `when: archwork_packages_aur | length > 0`, so the only part of the AUR path that had ever executed was the bootstrap that builds paru itself. That part works, because `makechrootpkg` wants to be root and `pacman -U` is root's job anyway.

So the role has been green for four milestones while the half of it that matters had never been reached. Same shape as the M4 checks that passed while testing nothing, and the reason it survived this long is that an empty list makes a `when` guard indistinguishable from a working task.

**The obvious fix is a trap, and it is worth writing down before someone tries it.** Running paru as `archwork_admin_user` works in the VM and fails on hardware. The installer writes `%wheel ALL=(ALL:ALL) ALL`, which prompts for a password, and only a *test* install also writes `99-archwork-test` with `NOPASSWD: ALL`. So paru as the admin user would pass every harness run and hang on the first real reconcile on `hmlxdesktop02`, waiting on a password prompt nobody is watching. This repository has enough of those already.

Three real options.

1. **A narrow sudoers rule for the build user**, letting it run `/usr/bin/pacman` without a password. This is what almost every Ansible AUR role does, and it directly reverses D-018's "it holds no privileges of its own: a locked password, no authorized keys, and nothing in sudoers". It should be reversed with eyes open rather than quietly: `pacman -U` on an arbitrary package file runs that package's install scripts as root, so this is a root-equivalent grant, not a narrow one. D-025 removed the `docker` group for exactly this reasoning.

2. **Build with `makechrootpkg` and install with `pacman -U`, per package, from Ansible.** No privilege changes at all, and it is precisely what the paru bootstrap in this same role already does. The cost is that Ansible takes over dependency resolution between AUR packages, which is the job paru exists to do. Most of the current set is `-bin` packages with repository-only dependencies, so it may be less painful than it sounds, and it may also be quietly wrong the first time an AUR package depends on another one.

3. **A local repository.** paru builds into a directory that is a pacman repository, and pacman installs from it as root the ordinary way. Root never builds, the build user never gains sudo, and dependency resolution stays with the tool that understands it. It is the most machinery of the three and the only one that leaves both halves of D-018 intact.

Recommendation: option 3, and option 2 if that turns out to need more moving parts than it is worth. Not option 1, because a root-equivalent grant to an account created for unattended builds is exactly the thing D-018 and D-025 both decided against, and it would be reversing two accepted decisions to save an afternoon.

This is the repository owner's call. Until it is made, `archwork_packages_aur` cannot be installed, which blocks the application manifests, which blocks M7's manifest criterion.

**A second thing this run surfaced, smaller and not blocking.** paru asked which provider to use for `java-runtime-headless`, `cargo`, and for four of the AUR names themselves, where `fsearch`, `claude-code`, `epsonscan2`, `protonup-qt` and `opendeck` each have `-git` or `-bin` siblings. `--noconfirm` takes the default, which is the first listed, so an unattended run silently picks `jdk-openjdk` and `rust` and the non-suffixed AUR package. That happens to be what is wanted in every case here. It is still a dependency chosen by list order rather than by anyone, and whichever option above is taken should pin the providers explicitly.
