# ARCHIVED

> **Archived 2026-10-15.** Read-only on GitHub (public). Local copy at `~/projects/archived/ArchWork`.
> This file is the resurrection guide; the rest of the repo is the project as it was left.

## Why

Superseded. The desktop (`hmlxdesktop02`) moved to Fedora, and no host runs Arch. The laptop
runs Ubuntu. Nothing is broken; the project just no longer has a machine to target.

## What was running, and what was done about it

Nothing outside this repo. Surveyed 2026-10-09: no services, packages, containers, mounts,
network exposure, or credentials created by the project. No GitHub secrets, deploy keys,
webhooks, environments, Pages or releases. Git history (171 commits) scanned with gitleaks:
clean.

Removed: this repo's entries in the local AI-agent manager.

Two PRs were closed unmerged on 2026-10-15, with their branches kept:

- **#48** `fix/nvidia-suspend-resume`: NVIDIA suspend/resume fix. 3 commits, never verified
  on hardware, conflicts with `main`.
- **#49** `docs/suspend-evidence-on-hardware`: a proposed suspend/resume criterion for M7.5.

## Where it left off

Per `docs/STATUS.yml` (last updated 2026-09-05): M0–M4 complete (through power and sleep);
**M5 (update, snapshot and rollback)**, M7.5 (MVP daily driver) and M8 (physical desktop) in
progress; M6, M7, M9, M10 not started. Milestones are defined in `docs/plan.md`, decisions in
`docs/decisions/`.

## Resurrecting it

1. `gh repo unarchive Avazel-Lab/ArchWork` and `mv ~/projects/archived/ArchWork ~/projects/active/`.
2. Read `docs/STATUS.yml` and `docs/plan.md`, then `docs/first-install.md`.
3. Expect drift: Arch, Hyprland and Quickshell move fast, and nothing here has been run since
   September 2026. Re-run the VM tests (`tests/vm`) before trusting anything on hardware.
4. Look at PR #48 before redoing NVIDIA suspend work; it is a starting point, not a verified fix.
5. Re-add the AI-agent manager profile.
