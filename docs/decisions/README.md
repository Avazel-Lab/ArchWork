# ArchWork decisions

This directory records agreed design decisions from the Arch desktop planning discussions. These documents are inputs to the implementation; they should be updated when a decision changes rather than allowing code and documentation to diverge.

Two shapes live here, doing different jobs.

**Topic documents** hold the settled shape of the platform by subject. They read as a whole and get edited in place when something changes.

**[The decision log](log.md)** holds individual decisions with IDs, dates and status. Milestones in `../STATUS.yml` point at those IDs to say what blocks them. New decisions go there first, then the relevant topic document gets updated to match.

Each topic document carries front matter:

```yaml
status: accepted        # or needs-verification, superseded
decided: 2026-08-27
review: 2027-02-27
```

## Topic documents

- [Desktop shell](desktop-shell.md)
- [Applications and tooling](applications-tooling.md)
- [Storage and boot](storage-boot.md)
- [Security and power](security-power.md)
- [Desktop and laptop differences](desktop-laptop-differences.md)

## Decision log

- [Decision log](log.md)

## Project target

- Standard Arch Linux underneath.
- Hyprland desktop.
- Reproducible bootstrap from a fresh minimal Arch installation.
- Packages, system configuration, user configuration and services captured as code.
- Safe update workflow with snapshots, reconciliation and health checks.
- Documented rollback and recovery.
- Automated clean-VM rebuild testing before deployment to primary machines.
