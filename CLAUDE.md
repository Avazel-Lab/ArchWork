# AI agent instructions

These rules apply to every AI-assisted change in this repository. A closer `CLAUDE.md` may add stricter rules but may not weaken this file.

ArchWork builds a reproducible personal Arch Linux workstation platform on Hyprland. It is not a distribution. Everything here stays close to standard Arch, and a fresh Arch installation should reach a complete workstation by cloning this repository and running the bootstrap.

## Reading order

Before editing:

1. Read this file.
2. Read `docs/STATUS.yml` to find out where the project is.
3. Read `docs/plan.md` for the milestone you are working on and its exit criteria.
4. Read the decision documents under `docs/decisions/` that cover the area you are touching.
5. Read `docs/decisions/log.md` for decisions made since those documents were written, and for open questions that block your milestone.

Do not load the whole repository into context when the relevant milestone, decision documents and target files are enough.

## Precedence

Decision documents beat the plan. The plan beats code.

Where code and a decision document disagree, change one of them on purpose and say which in the commit message. Never leave the two contradicting each other. A decision document that no longer reflects reality is worse than no document.

## Repository structure

```
bootstrap.sh      entry point for a fresh installation
ansible/          roles, inventory, package manifests
dotfiles/         user configuration
scripts/          installer, installation media, update, snapshot, rollback, health check, repository checks
tests/            bats unit tests and VM test harness
docs/             plan, status, decisions
```

Do not invent top-level directories. Extend this list here first if the project genuinely needs another one.

`bootstrap.sh` runs on the machine being built, never from another machine. **Nothing in the build path may require a second machine to be working.** A rebuild that needs the other workstation alive fails on the day it matters, and has no answer at all for the first machine. D-016 holds the reasoning, and this rule is easy to erode one convenient shortcut at a time.

## Profile model

Two machine profiles share one platform:

- `desktop` runs an AMD CPU with gaming and local AI workloads.
- `laptop` runs an Intel CPU with neither.

Express the difference through Ansible inventory groups, group variables and profile-specific package manifests. Do not put hostname conditionals inside roles, tasks or scripts. When a role needs to know about a difference, it reads a variable that the profile sets.

`docs/decisions/desktop-laptop-differences.md` holds the authoritative list of what differs.

## Status discipline

`docs/STATUS.yml` is the only place project status lives. Nothing else records what is done, in progress or blocked. Status duplicated across files goes stale in one of them within weeks.

Rules:

- Keep at most three entries under `next_actions`.
- Record current blockers only. Resolved blockers get deleted, not annotated.
- Keep no history. Git holds history.
- Update `updated` to the current date whenever you change the file.
- Never mark a milestone `complete`. That is the repository owner's call.
- A milestone marked `complete` carries an `evidence` block with a commit SHA and a date. The checker rejects one without.

`scripts/check-plan-status.py` enforces the mechanical parts. Run it before you present work as finished.

## Evidence

A claim that something passed needs a commit SHA and a date recorded in `docs/STATUS.yml`. This applies to clean-VM rebuilds, health check runs and rollback tests.

If there is no SHA, it did not happen. Do not write "tested", "verified" or "working" into any file in this repository on the strength of reading the code.

## Capture rule

Manual configuration during VM exploration is allowed and useful. It is also temporary. Nothing manual survives the next rebuild.

Anything worth keeping goes into code before the next rebuild runs. This is what makes the README's exploration step compatible with its minimal manual configuration principle.

## Destructive operations

This repository exists to write scripts that partition and format disks. Treat every one of them as dangerous.

Any script that partitions a device, creates a filesystem, writes a bootloader or wipes a block device must:

- Detect that it is running in a virtual machine, or refuse to run without an explicit `--i-know-this-wipes-my-disk` style flag.
- Print the target device, its size and its current partition table, then require confirmation.
- Never default a device path. Take it as an argument.
- Never guess. If it cannot identify the target with certainty, it exits non-zero.

`/home` sits outside the automatic rollback boundary and holds the only data that is not reproducible. Nothing in this repository writes to it without an explicit instruction.

## Storage constraints

`docs/decisions/storage-boot.md` fixes the subvolume layout. Two constraints follow from it that the document does not spell out, so they live here:

- `/var/lib` must stay inside `@` and roll back with it. The pacman database lives at `/var/lib/pacman`. If it survives a rollback of `@`, pacman reports package versions that are not on disk and every later update fights the filesystem. Do not carve `@var` or `@var_lib` out of the layout.
- `/home`, `@var_log`, `@var_cache` and `@ai_models` sit outside the rollback boundary by design. A rollback must not touch them.

## Quality bar

Shell scripts:

- Start with `#!/usr/bin/env bash` and `set -euo pipefail`.
- Pass ShellCheck with no suppressions. Where a suppression is unavoidable, put it on the single line it applies to with a comment explaining why.
- Quote every variable expansion.
- Take a `--dry-run` flag where the script changes system state.

Ansible:

- Passes `ansible-lint`.
- Runs idempotently. A second run reports zero changed tasks. Idempotence catches more real problems here than unit tests will.
- Declares packages in manifests. Never install ad hoc.
- Requires `community.general >= 8.0.0`.

Both:

- Run `make check` before presenting work as complete.

## Secrets

Never commit a plaintext secret, key or password. Not in a variable file, not in a comment, not in a test fixture.

Repository secrets use `age` and nothing else (D-006). `git-crypt` is not used.

The age private key is committed, wrapped with a diceware passphrase through `age -p`. Bootstrap prompts for that passphrase, unwraps the key in memory, and never writes the unwrapped key to the new system's disk outside its final destination.

Keep the encrypted set small. WiFi PSKs, the Tailscale auth key and service tokens belong there. SSH private keys and anything a password manager already holds do not, because putting them in the repository widens what one passphrase protects for no gain.

## Writing style

The `unslop` skill at `.claude/skills/unslop/SKILL.md` applies to every prose change in this repository. Read it before writing documentation.

Beyond it:

- British English.
- Sentence case headings.
- Metric first, useful imperial equivalents where they help.
- ISO dates, 24-hour time.
- No em dashes.
- Name packages exactly as Arch or the AUR names them.

## Git workflow

Use a branch and a pull request for anything that touches partitioning, encryption, boot, the update path or the rollback path. Direct commits to `main` are for genuinely low-risk corrections.

- Lowercase branch names in `type/topic` form.
- Commit messages in the existing style: `docs: add storage and boot decisions`.
- Do not rebase a branch after someone has reviewed it.
- Pin GitHub Actions to full commit SHAs.

## What an agent may do

Create and edit code, roles, scripts and tests within an accepted milestone. Update `docs/STATUS.yml` to reflect real progress. Add decisions to `docs/decisions/log.md`. Correct contradictions between code and documentation. Propose changes to the plan.

## What an agent may not do

- Mark a milestone complete.
- Claim a rebuild, health check or rollback passed without a recorded commit SHA.
- Invent hardware verification results, benchmark figures or package behaviour.
- Enable Secure Boot, or change the Secure Boot deferral.
- Answer an open decision in `docs/decisions/log.md` on the owner's behalf. Raise it, state a recommendation, then stop.
- Weaken a destructive operation guard.
- Add a package that no decision document lists.

## Completion checks

Before saying work is done:

1. Run `make check`.
2. Confirm `docs/STATUS.yml` matches reality, with any evidence recorded as a SHA.
3. Confirm nothing you wrote contradicts a decision document.
4. Report what changed, what evidence supports it and what remains uncertain.
