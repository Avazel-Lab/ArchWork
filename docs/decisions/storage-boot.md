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
- `@swap` on the laptop only (D-013)

`/var/lib` stays inside `@` and rolls back with it. The pacman database lives at `/var/lib/pacman`, and if it survives a rollback of `@` then pacman reports package versions that are not on disk. Do not carve `@var` or `@var_lib` out of this layout.

### Compression

- Enable Zstandard compression.

### Rollback boundaries

- `/home` is excluded from automatic system rollback.
- Logs survive rollback.
- Caches are excluded from rollback.
- AI model storage is excluded from rollback.
- `@swap` is excluded from rollback. Rolling back a swapfile achieves nothing, and it would change `resume_offset`, which is baked into the laptop kernel command line.

## Swap and hibernation

Decided at D-013.

- zram on both profiles, through `zram-generator`.
- The laptop additionally gets a swapfile sized to RAM on `@swap`, with `NODATACOW` set and compression off. Btrfs will not host a swapfile on a compressed copy-on-write subvolume.
- The laptop hibernates, using `suspend-then-hibernate` so that a machine left asleep overnight does not go flat.
- The desktop never hibernates and has no swapfile.
- `resume=` and `resume_offset=` go in the laptop kernel command line at install time, never retrofitted. Adding them later would regenerate the UKIs and change the PCR values that D-008 enrols against at M10.

## Boot architecture

- Use systemd-based boot tooling rather than GRUB. GRUB was reconsidered and rejected at D-011.
- Use Unified Kernel Images (UKIs).
- Maintain a recovery UKI.
- Document a rescue/recovery workflow, and ship a rollback script rather than a manual procedure (D-011).
- The rollback script lives at `/usr/local/bin/archwork-rollback` on the root filesystem, and the recovery UKI boots to a rescue shell (D-014). A root filesystem too corrupt to read needs the Arch ISO; say so in the rescue workflow rather than leaving it implied.
- The recovery UKI carries every module rather than an autodetected set.
- Use the `systemd` mkinitcpio hooks including `sd-encrypt`, not the busybox set. TPM2 enrolment at M10 needs them, and hibernating from a LUKS2 volume needs the resume device available in the initramfs.
- Kernel parameters should be deliberately defined up front rather than accumulated ad hoc.
- Maintain separate desktop and laptop kernel-parameter profiles where hardware requires it.

## Disk unlock

- LUKS2 passphrase at every boot until Secure Boot is enabled (D-008).
- TPM2 enrolment happens at M10, against PCR 7 and PCR 11, never before.
- Print a recovery key and store it offline before enrolling the TPM.

## Secure Boot

- Do not make Secure Boot a prerequisite for initial bring-up.
- Build and prove the desktop/laptop first.
- Use each system for approximately one month before enabling Secure Boot.
- UKIs and the surrounding boot design should be stable enough that enabling Secure Boot later does not require redesigning the installation.

## Snapshot tooling

- btrbk (D-007). One tool for snapshots, retention and off-machine send/receive.
- A pacman pre-transaction hook triggers the pre-update snapshot.
- Retention policy lives in the btrbk config in this repository.

## Backup

- btrbk send and receive to the NAS (D-009). Scope: `@home` and `@ai_models`.
- Snapshots are not backups. They share a device with the data.
- Verify the NAS runs btrfs before relying on this.
- Residual risk accepted: the NAS is in the same building, so fire and theft are not covered.

## Update and recovery intent

- Take a pre-update Btrfs snapshot.
- Apply Arch package updates.
- Apply AUR updates.
- Reconcile configuration afterwards.
- Run health checks after updating.
- Support rollback to a known-good system snapshot and config state.
