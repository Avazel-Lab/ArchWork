---
status: accepted
decided: 2026-08-29
review: 2027-02-28
---

# Selected applications and tooling

The application baseline. It is intentionally not exhaustive and can be extended as applications or requirements are identified.

This document is the list of what an ArchWork machine has on it. `applications-tooling.md` next to it holds the decisions *about* those choices, the ones with a consequence for how this repository works. Where the two disagree, this one wins, and the disagreement should be fixed rather than left (D-024).

Package manifests grow milestone by milestone, so most of what is here is not installed yet. `ansible/group_vars/` is what a machine actually gets; M8 and M9 are where the bulk of this list arrives.

## Browsers

- **Zen Browser**, primary. Firefox/Gecko based.
- **Ungoogled Chromium**, secondary. Chromium/Blink compatibility without Google's browser services.

## Editors

- **Visual Studio Code**, primary IDE.
- **Neovim**, terminal editor and useful for remote work.

## Documents and office

- **LibreOffice**, office suite.
- **Okular**, PDF and document viewer. Also the Qt application the M3 portal criterion opens a file picker from (D-023).
- **PDF Arranger**, graphical PDF page merging, splitting, extraction, rotation and reordering. The GTK half of that same criterion.
- **Pandoc**, required by the PWIKI PDF and document build process.

## Notes

- **Joplin**, notes and knowledge management.

## Images

- **Gwenview**, general purpose image viewer.
- **Pinta**, lightweight image editing.

## Archives

- **PeaZip**, graphical archive management.

## Password managers

- **NordPass**, primary.
- **Bitwarden**, secondary.

## Email and calendar

Web applications only. No dedicated desktop email or calendar client.

## Media

- **VLC**, general video and audio playback.
- **Spotify PWA**, music streaming without the native client.
- **HandBrake**, video transcoding.
- **tinyMediaManager**, media library management and metadata.

## Communication

- **Discord**, desktop application.
- **WhatsApp PWA**.

## File search

- **FSearch**, the closest fit to Everything-style indexed search. Indexes local files and mounted NAS shares.

## Torrenting

- **qBittorrent**.

## Remote access and networking

- **OpenSSH**, client and associated tooling.
- **Remmina**, graphical remote desktop client.
- **Tailscale**, private connectivity to other systems and the homelab. Must coexist with NetworkManager (D-002), which M3 tests.

## Virtualisation

- **KVM/QEMU**, the native Linux virtualisation stack.
- **libvirt**, management layer.
- **virt-manager**, graphical VM management. Particularly useful for clean ArchWork rebuild and testing VMs.

## Containers

- **Podman**, the container engine on this workstation. Chosen over Docker deliberately, partly to gain practical Podman experience (D-025).
- **podman-compose**, compose-style multi-container management.
- **Docker**, not the engine here. Kept as tooling for managing Docker-based remote systems such as the VPS. No `docker.socket`, no `docker` group (D-025).

## Kubernetes

- **kubectl**, the CLI.
- **Helm**, package and deployment management.
- **k9s**, terminal management UI.
- **kubectx** and **kubens**, fast context and namespace switching.
- **Stern**, multi-pod log tailing.

## DevOps and infrastructure as code

- **Ansible**, configuration management and automation. `community.general >= 8.0.0` required.
- **ansible-lint**.
- **Terraform**, chosen explicitly rather than OpenTofu.
- **Packer**, machine and image building.
- **Vault CLI**, HashiCorp Vault interaction.
- **GitHub CLI** (`gh`) and **GitLab CLI** (`glab`).
- **pre-commit**, repository hooks.

## Git

- **Git**, core version control.
- **git-crypt**, for other repositories that use it. Not a mechanism for this repository's secrets, which are `age` and nothing else (D-006, D-024).
- **LazyGit**, terminal Git UI.
- **Meld**, graphical diff and merge.

## Languages and development runtimes

- **Python 3.13**, managed explicitly rather than depending on Arch's rolling system Python staying at 3.13.
- **pip**.
- **Node.js** and **npm**.
- **Bash**, **GNU coreutils**, **gawk**, **util-linux** (which provides `findmnt`).

## General CLI and developer utilities

- **curl**, **wget**, network transfers and downloading.
- **ripgrep** (`rg`), **fd**, **fzf**, search and fuzzy finding.
- **bat**, **eza**, **zoxide**, **tree**, enhanced file viewing, listing and navigation.
- **tmux**, terminal multiplexer.
- **rsync**, file copying and synchronisation.
- **shellcheck**, the documented lint bar for health-check scripts. **shfmt**, formatting.
- **make**, **just**, build and task running.
- **jq**, **yq**, JSON and YAML processing.

## API and network diagnostics

- **Bruno**, graphical API client with local, Git-friendly collections.
- **HTTPie**, human-friendly CLI HTTP client.
- **nmap**, **mtr**, **iperf3**, **dig**, **whois**, **netcat**, discovery, routing, throughput, DNS and registration diagnostics.
- **tcpdump** and **Wireshark**, command-line and graphical packet capture.

## AI tooling

- **Claude Code** and **Codex CLI**, AI coding and agent CLIs.
- **Ollama**, local model runtime.
- **LM Studio**, local model management, runtime and UI.
- **Odysseus**. The exact project or package still needs identifying before installation can be automated.

## Game development

- **Godot**, engine and development environment.

## Gaming

- **Steam**, primary platform.
- **ProtonUp-Qt**, manages GE-Proton and other compatibility tools.
- **MangoHud**, performance overlay. **GameMode**, game-oriented performance tuning.
- **Lutris**, game and launcher management outside Steam.
- **Heroic Games Launcher**, Epic, GOG and Amazon libraries.

## Security and secrets

- **Lynis**, host security auditing.
- **YubiKey Manager** and YubiKey tooling. **libfido2**, FIDO2 hardware authentication.
- **age**, modern file encryption, and the only mechanism for this repository's secrets (D-006).
- **GnuPG**, encryption and signing. **OpenSSL**, TLS, certificate and cryptographic tooling.

SOPS was considered and is out of scope (D-024).

## Backup and sync

- **Restic**, encrypted and scriptable backups.
- **rclone**, remote and cloud storage transfer.
- **Btrfs snapshot tooling**, selected separately as part of the update and rollback architecture.
- No **Syncthing** by default. No current requirement for continuous device-to-device synchronisation.

## System monitoring

- **btop**, terminal resource and process monitor.
- **Mission Center**, graphical system resource monitoring.
- **nvtop**, GPU monitoring.

## Disk and storage

- **GParted**, graphical partition and filesystem management.
- **GNOME Disks**, drive inspection, SMART, formatting and mounting.
- **Baobab** and **ncdu**, graphical and terminal disk usage analysis.
- **duf**, filesystem and mount usage overview.
- **xorriso**, ISO creation and manipulation. **parted**, command-line partitioning.
- **`dd`**, raw image and device copying, already supplied by coreutils.

## Hardware diagnostics and testing

- **smartmontools**, SMART storage health. **nvme-cli**, NVMe diagnostics.
- **lm_sensors**, temperature and sensor monitoring.
- **lshw**, **pciutils** (`lspci`), **usbutils** (`lsusb`), **dmidecode**, hardware inventory and firmware information.
- **memtest86+**, memory testing. **stress-ng**, system stress testing. **fio**, storage performance.

## Audio

- **pavucontrol**, detailed graphical stream and device control, for troubleshooting.

## Theming

- **Kvantum** for Qt, with **kvantum-theme-materia** (`MateriaDark`).
- **materia-gtk-theme** (`Materia-dark`) for GTK, the matching half (D-020).
- **papirus-icon-theme** (`Papirus-Dark`) for icons, which Materia does not ship (D-020).

## Diagrams and documentation

- **Mermaid** and the Mermaid CLI, diagrams as code for repositories and documentation.

## Phone integration

- **KDE Connect**.

## Peripheral management

- **Solaar**, Logitech device and receiver management.
- **OpenDeck**, Stream Deck management. Desktop-specific rather than on every ArchWork machine.

## Printing and scanning

- **CUPS**, printing subsystem. **HPLIP**, HP printer support.
- **SANE** and **sane-airscan**, scanner framework and network scanning.

### Epson FastFoto FF-680W

Required hardware support. Driver-level Linux support is not sufficient by itself: the FastFoto-style workflow has to be tested before scanning counts as solved.

- Batch and ADF scanning, which matters most.
- Duplex, front and back handling.
- Mixed photo sizes.
- Automatic filenames.
- Suitable resolution and colour controls.
- Establish what automatic photo enhancement is lost without Epson's own FastFoto software.

Test USB as the baseline before WiFi.

### HP LaserJet Pro MFP M28w

Required printer and scanner support, with wireless printing. The CUPS, HPLIP and SANE stack is expected to provide the integration. Exact behaviour to be verified on the real hardware.

## Personal applications

Treated separately from generic workstation packages, because they may need reworking, packaging and an ArchWork-specific installation and update mechanism.

- **AI Agent Manager**
- **Game-on-itor**
- **Kitchen Sync**

## Web or PWA rather than native

Spotify, WhatsApp, email and calendar.

## Explicitly not included by default

Dedicated email client, dedicated calendar client, Syncthing, database GUI or CLI tooling, Android development and device tooling, webcam utilities, download managers, `yt-dlp`, `aria2`, qpwgraph, EasyEffects, Audacity, Ventoy, Impression, draw.io, Graphviz, Inkscape, OCRmyPDF, additional PDF CLI tooling, desktop indexing beyond FSearch, OBS Studio.
