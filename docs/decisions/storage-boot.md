---
status: accepted
decided: 2026-08-27
review: 2027-02-27
---

# Storage and boot decisions

## Disk encryption

- Use LUKS2 by default on both desktop and laptop.
- Desktop encryption remains subject to real-world performance validation before being treated as permanently settled.

## Filesystem

Use Btrfs on both systems.

### Subvolumes

- `@`
- `@home`
- `@var_log`
- `@var_cache`
- `@ai_models`
- `@snapshots`

### Compression

- Enable Zstandard compression.

### Rollback boundaries

- `/home` is excluded from automatic system rollback.
- Logs survive rollback.
- Caches are excluded from rollback.
- AI model storage is excluded from rollback.

## Boot architecture

- Use systemd-based boot tooling rather than GRUB.
- Use Unified Kernel Images (UKIs).
- Maintain a recovery UKI.
- Document a rescue/recovery workflow.
- Kernel parameters should be deliberately defined up front rather than accumulated ad hoc.
- Maintain separate desktop and laptop kernel-parameter profiles where hardware requires it.

## Secure Boot

- Do not make Secure Boot a prerequisite for initial bring-up.
- Build and prove the desktop/laptop first.
- Use each system for approximately one month before enabling Secure Boot.
- UKIs and the surrounding boot design should be stable enough that enabling Secure Boot later does not require redesigning the installation.

## Update and recovery intent

- Take a pre-update Btrfs snapshot.
- Apply Arch package updates.
- Apply AUR updates.
- Reconcile configuration afterwards.
- Run health checks after updating.
- Support rollback to a known-good system snapshot and config state.
