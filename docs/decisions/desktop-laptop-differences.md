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
| Disk unlock | Passphrase until Secure Boot, then TPM2 (D-008) | Passphrase until Secure Boot, then TPM2 (D-008) |
| Backup scope | `@home` and `@ai_models` to the NAS (D-009) | `@home` only, since no models are deployed |
| Networking | NetworkManager (D-002) | NetworkManager (D-002). Roaming and captive portals are the reason both profiles use it |
| Session entry | greetd with tuigreet (D-004) | greetd with tuigreet (D-004) |
| Host name | `hmlxdesktop02` (D-010) | `hmlxlaptop01` (D-010) |
| Inventory group | `desktop` | `laptop` |
| Swap | zram only (D-013) | zram plus a RAM-sized swapfile on `@swap` (D-013) |
| `@swap` Btrfs subvolume | Absent | Present, `NODATACOW`, compression off, outside the rollback boundary |
| Hibernation | Never | `suspend-then-hibernate`, so an overnight sleep does not flatten the battery |
| Kernel `resume=` | Absent | `resume=` and `resume_offset=` set at install time |

## Implementation principle

Host names follow the existing estate convention (`hmlxdesktop02`, `hmlxlaptop01`). Inventory group names are `desktop` and `laptop` (D-010). Groups express the profile, host names identify the box.

The desktop is `hmlxdesktop02` rather than `hmlxdesktop01` because the hardware already carries `hmlxdesktop01` as its Kubuntu development install, and the two dual boot on the same box. D-010 already covers this: a rebuild tested alongside the machine it replaces takes the next number.

Prefer explicit inventory/profile data such as:

- `desktop`
- `laptop`
- shared defaults
- profile-specific package groups
- profile-specific kernel parameters
- profile-specific services/configuration

Avoid scattering hostname checks throughout roles and scripts where a higher-level machine profile can express the distinction cleanly.

Concretely, `ansible/inventory/` defines the two groups, and `group_vars/all.yml`, `group_vars/desktop.yml` and `group_vars/laptop.yml` hold every row of the table above. `host_vars/` stays empty unless a genuine per-machine fact appears; a value that belongs to the profile goes in `group_vars`.

Most rows in this table are identical across profiles. That is the point. The platform is shared, and the table exists so that the few genuine differences stay visible rather than emerging as conditionals.
