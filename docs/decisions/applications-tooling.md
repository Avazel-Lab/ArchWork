---
status: accepted
decided: 2026-08-27
review: 2027-02-27
---

# Applications and tooling decisions

## Development and platform tooling

- Git
- Bash + coreutils
- awk
- findmnt
- Python 3.13 + pip
- Ansible
  - `community.general >= 8.0.0`
- devtools
  - Provides the clean chroot that AUR builds run in (D-005).
- Node.js + npm
- age
- jq
- curl
- Docker
  - Required for managing existing Docker workloads, including the VPS.
- Podman
  - Install on the desktop as well so it can be learned and used alongside Docker.
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

- `age` only (D-006). `git-crypt` is not used.
- The age private key is committed, wrapped with a diceware passphrase through `age -p`.
- Bootstrap prompts for that passphrase and unwraps the key in memory.
- Keep the encrypted set small: WiFi PSKs, Tailscale auth key, service tokens. Not SSH private keys.

## Package management

- paru as the AUR helper (D-005).
- AUR packages build in a clean chroot through `devtools`, never on the workstation.
- The update workflow uses the same chroot.

## Audio

- PipeWire with WirePlumber on both profiles (D-003).
- Include `pipewire-pulse`, `pipewire-alsa` and `pipewire-jack`.
- Shared package group. Not desktop-only.

## Networking

- NetworkManager on both profiles (D-002).
- `nmtui` covers the terminal case until the Quickshell applet lands at M6.
- Must coexist with Tailscale. Verify this rather than assuming it.

## Desktop applications

- FSearch
  - Chosen as the closest fit to Everything-style indexed search.
  - NAS indexing is desirable where practical.
- PDF Arranger
- No dedicated download manager by default.

## Scanning

### Epson FastFoto FF-680W

- Batching is important.
- Linux workflow still needs implementation/research.

### Epson M28-series wireless scanner/printer

- Treat the wireless model as M28W unless later hardware verification shows otherwise.

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
