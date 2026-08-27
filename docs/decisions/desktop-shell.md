---
status: accepted
decided: 2026-08-27
review: 2027-02-27
---

# Desktop shell decisions

## Core desktop

| Area | Decision | Notes |
|---|---|---|
| Window manager / compositor | Hyprland | Core desktop platform. |
| Desktop shell | Quickshell | Primary shell framework for integrated desktop UI. |
| Launcher | Quickshell | Launcher is a Quickshell module (D-001). Until Quickshell lands at M6, use fuzzel, and keep it in the fallback set afterwards. |
| Lock screen | Hyprlock | Longer-term goal is to replace/integrate with Quickshell. |
| Wallpaper | Hyprpaper | Use initially; review later. |
| Notifications | Quickshell | Notification UI handled by Quickshell. |
| Clipboard | wl-clipboard + cliphist | Surfaced through Quickshell. |
| Screenshots | grim + Satty + Quickshell UI | Chosen as the closest practical Linux workflow to KDE Spectacle. |
| Screen recording | wf-recorder + Quickshell UI | OBS excluded by default; install manually if ever needed. |
| Terminal | Kitty | Selected initially; mark for future review. |
| Qt theming | Kvantum | Use with a matching GTK theme. |
| Desktop UI integration | Quickshell | Prefer Quickshell for integrated controls and desktop functions. |

## Session entry

- greetd with tuigreet on both profiles (D-004).
- Hyprland launches from the greetd session command, not from a shell profile.
- The login password unlocks the Secret Service keyring through PAM.

## Portals and privilege UI

Install:

- `xdg-desktop-portal`
- `xdg-desktop-portal-hyprland`
- `xdg-desktop-portal-gtk`
- `hyprpolkitagent`

These provide desktop portal integration and graphical PolicyKit authentication under Hyprland.

## Behaviour

- Provide a way to temporarily inhibit system sleep without preventing normal display dimming or display-off behaviour.
- Sleep inhibition should be available for:
  - 1 hour
  - 2 hours
  - 4 hours
  - indefinitely until manually re-enabled
- Prefer a minimal shell initially, but retain the ability to expand the Quickshell UI later.
- Desktop shell choices marked for review should remain replaceable rather than deeply coupled into bootstrap logic.

## Fallback set

Quickshell carries the bar, notifications, clipboard UI, screenshot UI, recorder UI, the sleep inhibit control and the launcher (D-001). That is most of the custom code in this platform, in a young QML framework with a moving API.

The requirement above that shell choices stay replaceable is what makes that survivable, so it is load-bearing rather than aspirational:

- M3 builds a working desktop with no Quickshell in it: fuzzel, mako and a conventional bar.
- That fallback set stays installed and configured after M6. A broken Quickshell must leave an ugly desktop, not an unusable machine.
- Nothing in `bootstrap.sh` or in a base role may depend on Quickshell.
- M6 tests the fallback rather than assuming it.
