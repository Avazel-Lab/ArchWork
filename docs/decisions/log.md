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

- **Verify the NAS runs btrfs before relying on this.** `btrfs receive` needs a btrfs target. A ZFS or ext4 NAS means either a btrfs-formatted dataset on it, or a different backup tool, and finding that out at M8 is late. Check during M5, when btrbk goes in.
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
- A rebuild being tested alongside the machine it replaces gets the next number, not a special-case name.

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

- `ansible_connection: local` goes in `group_vars/all.yml`. The installer already sets the host name to `hmlxdesktop01` or `hmlxlaptop01` and `inventory/hosts.yml` already names those hosts, so the committed inventory then works unchanged on hardware and in a VM with `ansible-playbook -l "$(hostname)" site.yml`. No synthetic inventory, no connection flags at the call site.
- The harness keeps SSH, but only as the terminal driving a machine nobody can physically touch. Ansible no longer travels over it.
- The installer clones the checkout it runs from rather than fetching fresh, so the installed system carries the commit that built it. The same reasoning already governs `git archive HEAD` in the harness. It then points `origin` upstream, because a clone keeping its local origin works until the first `git pull`.
- The repository lives at `/home/<user>/src/ArchWork`, inside `@home` and so outside the rollback boundary. Inside `@`, a rollback would rewind the checkout at the moment it was being used to debug that rollback.
- `--authorized-key` stays a virtual-machine-only test affordance. With no push model, sshd has no place in the build path.
- Driving Ansible from another machine is not forbidden, but it is unsupported and untested. Nothing may come to depend on it.

This collides with nothing. D-015 is the recovery UKI shell decision, and D-016 supersedes no earlier decision.
