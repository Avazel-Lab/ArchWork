# ArchWork decisions

This directory records agreed design decisions from the Arch desktop planning discussions. These documents are inputs to the implementation; they should be updated when a decision changes rather than allowing code and documentation to diverge.

## Categories

- [Desktop shell](desktop-shell.md)
- [Applications and tooling](applications-tooling.md)
- [Storage and boot](storage-boot.md)
- [Security and power](security-power.md)
- [Desktop and laptop differences](desktop-laptop-differences.md)

## Project target

- Standard Arch Linux underneath.
- Hyprland desktop.
- Reproducible bootstrap from a fresh minimal Arch installation.
- Packages, system configuration, user configuration and services captured as code.
- Safe update workflow with snapshots, reconciliation and health checks.
- Documented rollback and recovery.
- Automated clean-VM rebuild testing before deployment to primary machines.
