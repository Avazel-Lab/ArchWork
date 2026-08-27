---
status: accepted
decided: 2026-08-27
review: 2027-02-27
---

# Applications and tooling decisions

## Development and platform tooling

- Git
- git-crypt
- Bash + coreutils
- awk
- findmnt
- Python 3.13 + pip
- Ansible
  - `community.general >= 8.0.0`
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

## General principles

- Keep package selection declarative in manifests/Ansible rather than installing ad hoc.
- Separate desktop-only packages from packages required on both desktop and laptop.
- Optional software that has no demonstrated regular use should remain outside the default build.
