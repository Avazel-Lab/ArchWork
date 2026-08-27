---
status: accepted
decided: 2026-08-27
review: 2027-02-27
---

# Security and power decisions

## Passwords and secrets

- NordPass is the primary password manager.
- Vaultwarden / Bitwarden is also used and should remain compatible with the desktop design.
- Use `gnome-keyring` as the Secret Service implementation for keyring integration (D-012). Its PAM module unlocks the keyring from the greetd login password, which is what D-004 depends on.
- The greetd login password unlocks the keyring through PAM (D-004). This is why session entry is not autologin.
- Repository secrets use `age` only (D-006). `git-crypt` is not used.
- The age private key is committed, wrapped with a diceware passphrase. Bootstrap unwraps it in memory. Store that passphrase in NordPass.
- Keep the encrypted set small: WiFi PSKs, Tailscale auth key, service tokens. SSH private keys stay out of the repository.
- Avoid designs that interfere with Tailscale, hosted services, tmux, SSH or normal development workflows.

## Security posture

- Security controls should be enabled on both desktop and laptop unless a hardware/workload difference requires otherwise.
- Prefer controls that are transparent during normal use rather than creating repeated friction.
- Security configuration must coexist cleanly with remote access and automation tooling.
- Transparency has a limit: a control that is transparent to the user and to an attacker alike is not a control. D-008 applies this to disk unlock, and D-004 to session entry.

## Disk unlock

- LUKS2 passphrase at every boot until Secure Boot is enabled (D-008).
- TPM2 enrolment happens at M10, against PCR 7 and PCR 11, never before. Without Secure Boot the TPM hands the key to anyone who boots a modified UKI.
- Print a LUKS2 recovery key and store it offline before enrolling the TPM. A firmware update changes PCR values.

## Boot prompts

During the Secure Boot deferral there are two prompts at boot: LUKS, then greetd. After M10 there is one.

## Display and sleep defaults

Apply to both desktop and laptop:

- Dim display after 5 minutes.
- Turn display off after 15 minutes.
- Sleep after 30 minutes.

The laptop then hibernates through `suspend-then-hibernate` (D-013), because sleep alone flattens a battery overnight. The desktop never hibernates.

## Temporary sleep inhibition

Provide an explicit desktop control to suppress sleep while leaving display dim/off behaviour intact.

Supported durations:

- 1 hour
- 2 hours
- 4 hours
- until manually re-enabled

## Hardware notes

- Desktop CPU: AMD.
- Laptop CPU: Intel.
- CPU vendor differences may require profile-specific configuration, but should not change the overall security design.
- Gaming-specific security/performance choices should favour the best practical gaming experience on the desktop while preserving the agreed security baseline.
