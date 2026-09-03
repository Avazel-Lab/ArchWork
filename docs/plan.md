# ArchWork plan

This file defines the milestones, what proves each one, and the test ladder. It changes rarely and on purpose.

It does not record progress. `docs/STATUS.yml` does that, and it is the only file that does.

## How to read this

Each milestone has exit criteria that someone can check. "Working" is not an exit criterion. "Two consecutive unattended runs produce a bootable VM" is.

Milestones run roughly in order, but M1 through M5 build on each other while M6 can start once M5 holds. M8 and M9 wait on M7. M7.5 does not: it is the one milestone that deliberately runs ahead of the proving run, because the platform is more useful being used than it is waiting (D-036). M10 waits thirty days per machine after M8 or M9.

A milestone inserted between two existing ones takes a fractional number rather than renumbering the ones after it. Milestone IDs are referenced from `docs/STATUS.yml`, the decision log and commit messages, so they are cheaper to leave alone.

## Milestones

### M0 Repository contract

Set up the rules and the tracking before any code exists, so the first code written conforms.

Exit criteria:

- `CLAUDE.md` binds agent work to the decision documents.
- `docs/plan.md` and `docs/STATUS.yml` exist and cross-check clean.
- `docs/decisions/log.md` records dated decisions with IDs, and any that remain open.
- The `unslop` skill sits at `.claude/skills/unslop/SKILL.md`.
- CI runs L0 lint and the plan/status cross-check, and passes.

### M1 Encrypted base in a VM

A scripted installation from the stock Arch ISO, no desktop.

Covers LUKS2, the Btrfs layout from `decisions/storage-boot.md`, systemd-boot and Unified Kernel Images.

Exit criteria:

- The script produces a VM that boots to a login prompt, unattended, twice in a row.
- `lsblk` shows LUKS2. `btrfs subvolume list` shows `@`, `@home`, `@var_log`, `@var_cache`, `@ai_models` and `@snapshots`, plus `@swap` on the laptop profile (D-013).
- Mount options carry `compress=zstd`.
- `/var/lib` sits inside `@`.
- A primary UKI and a recovery UKI both exist and both boot.
- Kernel parameters come from a profile file, not from accumulated edits. The laptop file carries `resume=` and `resume_offset=`, the desktop file carries neither (D-013).
- zram is active on both profiles. On the laptop, hibernate and resume both work (D-013).
- The recovery UKI reaches a rescue shell, and `/usr/local/bin/archwork-rollback` is installed (D-011, D-014).
- The script refuses to run against a device it cannot confirm, and refuses outside a VM without an explicit override flag. Each guard is proven by making it refuse, not by reading it.

### M2 Ansible reconciliation

Bring a freshly installed machine to a defined state, repeatably.

Ansible runs on the target with a local connection (D-016). Nothing here may require a second machine. `bootstrap.sh` prompts for the age passphrase, decrypts the secrets, brings up networking, then runs the playbook, in that order, because a wireless-only laptop has no network until the WiFi PSK has been decrypted.

Exit criteria:

- Inventory defines `desktop` and `laptop` groups plus shared defaults.
- Package manifests split shared packages from profile-only packages.
- No role, task or template contains a hostname conditional.
- `ansible-playbook --check` runs clean against a fresh VM.
- A real run followed by a second run reports zero changed tasks.
- `ansible-lint` passes.
- `host_vars/` is empty, or every entry in it is a genuine per-machine fact (D-010).
- The whole run completes on the target alone, with no second machine involved and nothing connecting inward to it (D-016).
- The machine arrives able to do that: `ansible` and `age` are installed by the installer, this repository is cloned into the user's home and owned by them, `origin` points upstream rather than at a path on the ISO, and `bootstrap.sh` is present and executable.
- The run uses the committed inventory, not one generated for the test.

### M3 Minimal Hyprland desktop

A usable desktop with no Quickshell in it. This milestone deliberately uses conventional tools so that the platform works before any custom shell code exists.

Includes Hyprland, `xdg-desktop-portal`, `xdg-desktop-portal-hyprland`, `xdg-desktop-portal-gtk`, `hyprpolkitagent`, Kitty, Hyprpaper, Hyprlock, an audio stack, networking, and fuzzel as the interim launcher. The launcher in `decisions/desktop-shell.md` is a Quickshell module, which does not exist until M6, so M3 needs its own.

Exit criteria:

- On a VM rebuilt from scratch: log in, open a terminal, launch an application from the launcher, lock the session, unlock it, take a screenshot.
- Portals work. A file picker opens from a GTK application and from a Qt application.
- The greetd login password unlocks the Secret Service keyring through PAM, with no second prompt (D-004, D-012).
- Tailscale comes up and coexists with NetworkManager (D-002).
- Kvantum and the matching GTK theme apply.
- No step in the above requires manual configuration after the rebuild.

### M4 Power and sleep behaviour

The timings and the inhibit control from `decisions/security-power.md`.

Exit criteria:

- Display dims after 5 minutes, switches off after 15, system sleeps after 30.
- A sleep inhibit control offers 1 hour, 2 hours, 4 hours and until manually re-enabled.
- While inhibited, the display still dims and still switches off. Only sleep is suppressed.
- An automated check asserts each timing and asserts that `systemd-inhibit --list` shows the expected lock during an inhibit window.

### M5 Update, snapshot and rollback

The safe update workflow, and the recovery path that makes it safe.

Exit criteria:

- The update script takes a pre-update Btrfs snapshot, applies Arch updates, applies AUR updates, reconciles configuration, then runs health checks.
- Health checks assert subvolume mounts, encryption state, UKI presence, required services and the M4 timings.
- Break a VM on purpose, roll back, and health checks pass afterwards.
- After rollback, `pacman -Qi` agrees with what is on disk. This is the check that catches a broken subvolume boundary.
- The recovery UKI boots and the rollback script on it works.
- The NAS is confirmed to run btrfs, so that `btrfs receive` will work at M8 (D-009).

### M6 Quickshell integration

The custom desktop shell. Bar, notifications, clipboard through `wl-clipboard` and `cliphist`, screenshots through `grim` and Satty, recording through `wf-recorder`, the sleep inhibit control, and the launcher.

This is the largest block of custom code in the project and the one most likely to break on upgrade. `decisions/desktop-shell.md` requires that shell choices stay replaceable rather than coupled into bootstrap logic. That requirement is load-bearing here.

Exit criteria:

- Every component above works on a VM rebuilt from scratch.
- The M3 fallback set still installs and still produces a working desktop with Quickshell removed. Test this, do not assume it.
- Nothing in `bootstrap.sh` or in a base role depends on Quickshell.
- The shell survives a Quickshell version bump, or the breakage is recorded and pinned.

### M7 Rebuild proving run

The point of the whole project.

"Full desktop" means the workstation, not a compositor with a terminal on it. Until D-024 that was implied and therefore not true: no milestone installed the bulk of `decisions/applications.md`, so the applications would have arrived by nobody's decision during M8, on a machine already meant to be in daily use. The manifest criterion below is where that gets caught, and it belongs here rather than later, because a rebuild that repeatably produces something short of the workstation proves repeatability of the wrong thing.

Exit criteria:

- Three consecutive clean-VM rebuilds, bare ISO to full desktop, zero manual steps.
- Both profiles rebuilt at least once each.
- The package manifests account for every application in `decisions/applications.md`, or name the ones deliberately left out and say why. An entry that is deferred is fine; an entry nobody has looked at is not.
- Nothing needed to reach that desktop was installed by hand. The check is the same one M2 uses: reconcile twice, and require the second run to change nothing.
- Wall-clock timings recorded in `docs/STATUS.yml` with the commit SHA.

### M7.5 MVP daily driver

The point of this milestone is to stop developing the platform only in virtual machines. `hmlxdesktop02` becomes a machine the repository owner uses for real work, and the machine this repository is developed on, while Kubuntu stays the primary boot and the place end-to-end VM testing runs.

It sits before M8 rather than inside it because M8 is about the desktop being finished: gaming, local AI, a NAS restore and thirty days of green health checks. This is about it being usable at all. It runs ahead of M7 deliberately, because M7 wants three consecutive zero-touch rebuilds and waiting for that keeps the platform in VMs for as long as the last bug takes (D-036).

The machine is disposable, and that is what makes this cheap. Losing the whole Arch installation costs nothing, so no backup, snapshot or `/home` protection is in scope.

Everything reaches the machine through Ansible, exactly as a deployment does. Manual configuration is not a shortcut that is permitted here and tidied up later. Avoiding it is most of the point.

Exit criteria:

- Installed from the ISO at one named commit on `main`, and brought to a desktop by `bootstrap.sh` alone with no manual step after it.
- Zen Browser, Visual Studio Code and the Claude Code CLI launch on the machine, installed from the manifests by the AUR path. That path has never run on hardware.
- `make check` passes on `hmlxdesktop02` itself. That is what proves the repository's own tooling is on the machine rather than assumed: git, ansible, ansible-lint, shellcheck, yamllint and python.
- A second reconcile on the hardware reports zero changed tasks. The M2 rule has only ever been proven in a VM.
- `archwork-health` passes on the machine.
- Claude Code can commit and push from `hmlxdesktop02`, through an ed25519 key generated on that machine and added to the GitHub account. No private key enters this repository or the `age` set (`CLAUDE.md`, D-006).
- Kubuntu is still the default boot entry, and Arch is still chosen deliberately from the firmware boot menu. Nothing here changes the boot order.

Out of scope, named so that nobody adds them: `/home` backup, the NAS, Steam and controllers, local AI models, configuration drift detection, and every part of the thirty-day clock. Those stay in M8.

### M8 Physical desktop

Deploy to the AMD desktop. Gaming and local AI workloads included, per `decisions/desktop-laptop-differences.md`.

Exit criteria:

- Deployed from the same bootstrap as the VMs.
- Steam, OpenDeck and Xbox controller support work.
- Local AI models live on `@ai_models` and survive a system rollback.
- Thirty days of daily use with health checks green.
- LUKS2 performance validated in real use, per `decisions/storage-boot.md`.
- A restore from the NAS backup tested, not just a backup taken (D-009).

### M9 Physical laptop

Deploy to the Intel laptop. No gaming, no local AI models.

Exit criteria:

- Deployed from the same bootstrap, differing only through inventory.
- Thirty days of daily use with health checks green.

### M10 Secure Boot

Per machine, after thirty days of proven use.

Exit criteria:

- Custom keys enrolled, UKIs signed, both the primary and the recovery UKI boot with Secure Boot enabled.
- A LUKS2 recovery key printed and stored offline before TPM2 enrolment (D-008).
- TPM2 enrolled with `systemd-cryptenroll` against PCR 7 and PCR 11.
- Unlock retested after a deliberate firmware setting change.
- The M5 rollback path retested with Secure Boot on.
- The rescue workflow retested with Secure Boot on.

## Test ladder

Six levels. Nothing gets written that passes without exercising something.

| Level | What | Where it runs |
|---|---|---|
| L0 | Lint: ShellCheck, ansible-lint, yamllint, plan/status cross-check | CI |
| L1 | Unit: bats, for script logic with real branching | CI |
| L2 | Idempotence: playbook twice, second run zero changed | Local VM |
| L3 | Clean rebuild: full bootstrap in a throwaway VM | Local VM |
| L4 | Health checks: post-boot assertions | Local VM, and on real machines |
| L5 | Recovery: snapshot rollback and recovery UKI boot | Local VM |

ShellCheck is the documented lint bar, per `decisions/applications-tooling.md`.

Do not write bats tests for three-line wrappers. A wrapper gets L0 and nothing else. L2 will find more real bugs in this project than L1 ever does.

### What CI can and cannot do

GitHub Actions runs L0 and L1. That is the whole list.

L2 through L5 need nested virtualisation or a local runner. Do not add a CI job that skips itself and reports green, because a green badge that proves nothing is worse than no badge. L2 through L5 run locally behind `make` targets, and their results go into `docs/STATUS.yml` with a date and a commit SHA.

`scripts/check-plan-status.py` rejects a passing rebuild record that has no SHA.

## Milestone status values

`docs/STATUS.yml` uses exactly these:

- `not-started`
- `blocked`, with `blocked_by` listing decision IDs
- `in-progress`
- `complete`, set only by the repository owner, and carrying an `evidence` block with a commit SHA and a date

`scripts/check-plan-status.py` rejects a milestone marked `complete` with no evidence behind it. That is the `CLAUDE.md` evidence rule applied to milestones rather than only to rebuild claims.
