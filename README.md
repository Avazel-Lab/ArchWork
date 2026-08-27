# ArchWork

ArchWork is a project to build a reproducible personal Arch Linux workstation platform based on Hyprland.

## Goal

The aim is to create a polished, integrated desktop experience similar in principle to projects such as Omarchy, while retaining standard Arch Linux underneath and keeping ownership of the configuration, automation, update process and recovery mechanisms.

A fresh Arch Linux installation should eventually be able to clone this repository, run the bootstrap process, and become a complete workstation with minimal manual intervention.

The platform will support two related but distinct builds:

- **Desktop** — primary workstation, including development tooling, gaming and local AI workloads.
- **Laptop** — portable workstation using the same core platform, but without gaming or local AI components.

Differences between the two should be explicit and managed by the automation rather than maintained as separate, divergent configurations.

## Principles

- **Arch underneath** — remain close to standard Arch Linux rather than creating a separate distribution.
- **Configuration as code** — packages, system configuration, services and user configuration should be captured in the repository.
- **Reproducible builds** — rebuilding a workstation should be a normal, tested operation rather than a recovery of last resort.
- **Minimal manual configuration** — changes made interactively during development should ultimately be captured in code.
- **Safe updates** — system updates should be preceded by appropriate snapshots and followed by automated health checks.
- **Recoverable** — provide documented and tested mechanisms for snapshot rollback, configuration restoration and system repair.
- **Testable** — bootstrap and rebuild processes should be tested against clean Arch installations before relying on them on physical machines.
- **Shared core, explicit differences** — desktop and laptop builds should share the same foundation while hardware and workload differences remain clearly defined.
- **Own the integration** — understand and control how the desktop is assembled rather than depending on an opaque collection of scripts or configuration.

## Target Platform

The common platform is expected to include:

- Arch Linux
- Hyprland
- Quickshell-based desktop integration
- Btrfs
- LUKS2 encryption
- systemd
- Unified Kernel Images
- Secure Boot after the platform has been proven stable
- automated package and configuration management
- dotfile management
- development tooling
- security hardening
- update, snapshot and rollback tooling
- automated health checks

Desktop-specific functionality includes gaming and local AI workloads.

## Development Approach

The platform will initially be assembled and tested in a clean Arch virtual machine.

The intended development cycle is:

1. Build a minimal Arch VM.
2. Configure a working desktop manually where exploration is useful.
3. Capture each successful change in code.
4. Develop a bootstrap process capable of reproducing the system.
5. Rebuild clean VMs regularly to verify reproducibility.
6. Add safe update, health-check and recovery mechanisms.
7. Dogfood the platform in VMs until rebuilds are repeatable.
8. Deploy to physical desktop and laptop systems only once the platform is sufficiently proven.

## Repository Direction

The repository is expected to evolve towards a structure similar to:

    bootstrap.sh
    ansible/
    dotfiles/
    scripts/
    tests/
    docs/

Architecture and platform decisions are recorded under:

    docs/decisions/

These decision documents describe the intended state of the platform and should guide its eventual implementation.
