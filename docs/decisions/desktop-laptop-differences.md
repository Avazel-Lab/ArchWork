---
status: accepted
decided: 2026-08-27
review: 2027-02-27
---

# Desktop and laptop differences

Track these differences explicitly in code and documentation rather than allowing them to emerge as incidental conditionals.

| Area | Desktop | Laptop |
|---|---|---|
| CPU | AMD | Intel |
| AI models | Enabled / supported | No local AI models |
| `@ai_models` Btrfs subvolume | Present for model storage | May remain structurally present if useful for a common layout, but no models are deployed |
| Gaming | Gaming configuration and applications enabled | Gaming configuration and applications excluded |
| Steam | Install/configure | Exclude |
| OpenDeck | Install/configure | Exclude |
| Controllers | Xbox controller support relevant | Not part of default laptop profile |
| Encryption | LUKS2, subject to desktop performance validation | LUKS2 |
| Kernel parameters | Desktop hardware-specific profile | Laptop hardware-specific profile |
| Power management | 5 min dim / 15 min display off / 30 min sleep | 5 min dim / 15 min display off / 30 min sleep |
| Sleep inhibition | 1h / 2h / 4h / manual re-enable | 1h / 2h / 4h / manual re-enable |
| Secure Boot | Enable only after roughly one month of proven use | Enable only after roughly one month of proven use |

## Implementation principle

Prefer explicit inventory/profile data such as:

- `desktop`
- `laptop`
- shared defaults
- profile-specific package groups
- profile-specific kernel parameters
- profile-specific services/configuration

Avoid scattering hostname checks throughout roles and scripts where a higher-level machine profile can express the distinction cleanly.
