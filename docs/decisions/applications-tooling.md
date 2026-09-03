---
status: accepted
decided: 2026-08-27
review: 2027-02-27
---

# Applications and tooling decisions

`applications.md` next to this file is the list of what an ArchWork machine has on it. This file holds the decisions *about* those choices: the ones with a consequence for how the repository works, rather than a record of what the owner wants installed. Where the two disagree, `applications.md` wins and the disagreement gets fixed (D-024).

## Development and platform tooling

- Git
- Bash + coreutils
- awk
- findmnt
- Python 3.13 + pip
- Ansible
  - `community.general >= 8.0.0`
- devtools
  - Provides `makechrootpkg`, which paru builds through (D-005). See the note
    under Package management about where that chroot actually lives.
- Node.js + npm
- age
- jq
- curl
- Podman
  - The container engine on this workstation, chosen over Docker deliberately and partly to gain practical Podman experience (D-025).
  - No system daemon and no group. Rootless Podman needs neither.
- podman-compose
  - Compose-style multi-container management.
- Docker
  - A client for managing Docker workloads on remote systems, including the VPS. Not the engine here (D-025).
  - `docker.socket` is not enabled and nobody is in the `docker` group. That group reaches a root daemon without a password prompt, and this machine has no local daemon for it to reach.
  - Arch ships no separate client package, so dockerd is installed and never started.
- kubectl
- OpenSSH client
- ShellCheck
  - Use as the documented lint bar for health-check scripts.
- Pandoc
- Mermaid
- xorriso

## Configuration model

Decided at D-016.

- Ansible runs on the target machine with a local connection. Nothing in the build path requires a second machine.
- `ansible_connection: local` lives in `group_vars/all.yml`, so the committed inventory works unchanged on hardware and in a test VM.
- `ansible`, `python` and `age` are pacstrapped by the installer as well as listed in the shared manifest. The playbook cannot be what installs the tools it needs to run, and bootstrap needs `age` before any network exists to fetch it.
- Driving Ansible from another machine over SSH is unsupported and untested. Nothing may come to depend on it.

## Secrets

- `age` only (D-006) for this repository's secrets. `git-crypt` is not a mechanism for them.
- `git-crypt` is installed all the same, for other repositories that use it (D-024). Two different questions, and reading them as one made this look like a contradiction for a while.
- The age private key is committed, wrapped with a diceware passphrase through `age -p`.
- Bootstrap prompts for that passphrase and unwraps the key in memory.
- Keep the encrypted set small: WiFi PSKs, Tailscale auth key, service tokens. Not SSH private keys.

## Package management

- paru as the AUR helper (D-005).
- AUR packages build in a clean chroot through `devtools`, never on the workstation.
- The update workflow uses the same chroot.
- Which chroot that is turned out not to be the one this repository creates. `paru --chroot` builds in `/var/lib/aurbuild` and has no option to point it elsewhere, so the chroot the `aur` role makes at `/var/cache/archwork/chroot` is used to build paru itself and nothing after that. The two lines above are still true as written, and the placement D-018 chose is not: `@var_cache` was picked so a large build cache would sit outside the rollback boundary, and AUR builds are inside `@`. D-033 records it; it is not decided.
- The build account is not unprivileged. `archwork-build` has a passwordless sudo rule, because paru refuses to run as root and reaches for root itself (D-033, amending D-018).

## Audio

- PipeWire with WirePlumber on both profiles (D-003).
- Include `pipewire-pulse`, `pipewire-alsa` and `pipewire-jack`.
- Shared package group. Not desktop-only.

## Networking

- NetworkManager on both profiles (D-002).
- `nmtui` covers the terminal case until the Quickshell applet lands at M6.
- Must coexist with Tailscale. Verify this rather than assuming it.

## Desktop applications

The list is in `applications.md`. Two entries carry a decision rather than a preference:

- FSearch was chosen as the closest fit to Everything-style indexed search, with NAS indexing desirable where practical.
- PDF Arranger and Okular are what the M3 portal criterion opens a file picker from, GTK and Qt (D-023). They are in the M3 session manifest for that reason as well as their own.

## Scanning

The hardware and the workflow that has to be proven are in `applications.md`. The decision here is narrower: batch scanning is the requirement that decides whether the Epson FastFoto workflow is solved, and the wireless M28-series model is treated as the M28W unless hardware verification shows otherwise.

## Desktop platform packages

Recorded here so that manifests have one source. Detail and reasoning live in the decision log.

| Area | Package | Decision |
|---|---|---|
| Session entry | `greetd`, `greetd-tuigreet` | D-004 |
| Networking | `networkmanager` | D-002 |
| Audio | `pipewire`, `wireplumber`, `pipewire-pulse`, `pipewire-alsa`, `pipewire-jack` | D-003 |
| AUR | `paru`, `devtools` | D-005 |
| Secrets | `age` | D-006 |
| Snapshots and backup | `btrbk` | D-007, D-009 |
| Interim launcher and fallback | `fuzzel` | D-001 |

## General principles

- Keep package selection declarative in manifests/Ansible rather than installing ad hoc.
- Separate desktop-only packages from packages required on both desktop and laptop.
- Optional software that has no demonstrated regular use should remain outside the default build.
