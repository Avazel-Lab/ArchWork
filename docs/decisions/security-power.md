---
status: accepted
decided: 2026-08-27
review: 2027-02-27
---

# Security and power decisions

## Passwords and secrets

- NordPass is the primary password manager.
- Vaultwarden / Bitwarden is also used and should remain compatible with the desktop design.
- Use a Secret Service implementation for Linux desktop secret/keyring integration.
- Avoid designs that interfere with Tailscale, hosted services, tmux, SSH or normal development workflows.

## Security posture

- Security controls should be enabled on both desktop and laptop unless a hardware/workload difference requires otherwise.
- Prefer controls that are transparent during normal use rather than creating repeated friction.
- Security configuration must coexist cleanly with remote access and automation tooling.

## Display and sleep defaults

Apply to both desktop and laptop:

- Dim display after 5 minutes.
- Turn display off after 15 minutes.
- Sleep after 30 minutes.

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
